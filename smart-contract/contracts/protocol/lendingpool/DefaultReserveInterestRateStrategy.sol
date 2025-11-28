// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../interfaces/IReserveInterestRateStrategy.sol";
import "../../interfaces/ILendingPoolAddressesProvider.sol";
import "../../interfaces/ILendingRateOracle.sol";
import "../../openzeppelin/contracts/IERC20.sol";
import "../../openzeppelin/contracts/SafeMath.sol";
import "../libraries/math/WadRayMath.sol";
import "../libraries/math/PercentageMath.sol";

contract DefaultReserveInterestRateStrategy is IReserveInterestRateStrategy {
    using SafeMath for uint256;
    using WadRayMath for uint256;
    using PercentageMath for uint256;

    uint256 public immutable OPTIMAL_UTILIZATION_RATE;
    uint256 public immutable EXCESS_UTILIZATION_RATE;

    ILendingPoolAddressesProvider public immutable addressesProvider;

    uint256 internal immutable _baseVariableBorrowRate;
    uint256 internal immutable _variableRateSlope1;
    uint256 internal immutable _variableRateSlope2;
    uint256 internal immutable _stableRateSlope1;
    uint256 internal immutable _stableRateSlope2;

    constructor(
        ILendingPoolAddressesProvider provider,
        uint256 optimalUtilizationRate,
        uint256 baseVariableBorrowRate_,
        uint256 variableRateSlope1_,
        uint256 variableRateSlope2_,
        uint256 stableRateSlope1_,
        uint256 stableRateSlope2_
    ) {
        OPTIMAL_UTILIZATION_RATE = optimalUtilizationRate;
        EXCESS_UTILIZATION_RATE = WadRayMath.ray().sub(optimalUtilizationRate);
        addressesProvider = provider;
        _baseVariableBorrowRate = baseVariableBorrowRate_;
        _variableRateSlope1 = variableRateSlope1_;
        _variableRateSlope2 = variableRateSlope2_;
        _stableRateSlope1 = stableRateSlope1_;
        _stableRateSlope2 = stableRateSlope2_;
    }

    function variableRateSlope1() external view returns (uint256) {
        return _variableRateSlope1;
    }

    function variableRateSlope2() external view returns (uint256) {
        return _variableRateSlope2;
    }

    function stableRateSlope1() external view returns (uint256) {
        return _stableRateSlope1;
    }

    function stableRateSlope2() external view returns (uint256) {
        return _stableRateSlope2;
    }

    function baseVariableBorrowRate() external view override returns (uint256) {
        return _baseVariableBorrowRate;
    }

    function getMaxVariableBorrowRate()
        external
        view
        override
        returns (uint256)
    {
        return
            _baseVariableBorrowRate.add(_variableRateSlope1).add(
                _variableRateSlope2
            );
    }

    function calculateInterestRates(
        address reserve,
        address aToken,
        uint256 liquidityAdded,
        uint256 liquidityTaken,
        uint256 totalStableDebt,
        uint256 totalVariableDebt,
        uint256 averageStableBorrowRate,
        uint256 reserveFactor
    ) external view override returns (uint256, uint256, uint256) {
        uint256 availableLiquidity = IERC20(reserve).balanceOf(aToken);
        availableLiquidity = availableLiquidity.add(liquidityAdded).sub(
            liquidityTaken
        );

        return
            calculateInterestRates(
                reserve,
                availableLiquidity,
                totalStableDebt,
                totalVariableDebt,
                averageStableBorrowRate,
                reserveFactor
            );
    }

    struct CalcInterestRatesLocalVars {
        uint256 totalDebt;
        uint256 currentVariableBorrowRate;
        uint256 currentStableBorrowRate;
        uint256 currentLiquidityRate;
        uint256 utilizationRate;
    }

    function calculateInterestRates(
        address reserve,
        uint256 availableLiquidity,
        uint256 totalStableDebt,
        uint256 totalVariableDebt,
        uint256 averageStableBorrowRate,
        uint256 reserveFactor
    ) public view override returns (uint256, uint256, uint256) {
        CalcInterestRatesLocalVars memory vars;

        vars.totalDebt = totalStableDebt.add(totalVariableDebt);
        vars.currentVariableBorrowRate = 0;
        vars.currentStableBorrowRate = 0;
        vars.currentLiquidityRate = 0;

        vars.utilizationRate = (vars.totalDebt == 0)
            ? 0
            : vars.totalDebt.rayDiv(availableLiquidity.add(vars.totalDebt));

        vars.currentStableBorrowRate = ILendingRateOracle(
            addressesProvider.getLendingRateOracle()
        ).getMarketBorrowRate(reserve);

        if (vars.utilizationRate > OPTIMAL_UTILIZATION_RATE) {
            uint256 excessUtilizationRateRatio = vars
                .utilizationRate
                .sub(OPTIMAL_UTILIZATION_RATE)
                .rayDiv(EXCESS_UTILIZATION_RATE);

            vars.currentStableBorrowRate = vars
                .currentStableBorrowRate
                .add(_stableRateSlope1)
                .add(_stableRateSlope2.rayMul(excessUtilizationRateRatio));

            vars.currentVariableBorrowRate = _baseVariableBorrowRate
                .add(_variableRateSlope1)
                .add(_variableRateSlope2.rayMul(excessUtilizationRateRatio));
        } else {
            vars.currentStableBorrowRate = vars.currentStableBorrowRate.add(
                _stableRateSlope1.rayMul(
                    vars.utilizationRate.rayDiv(OPTIMAL_UTILIZATION_RATE)
                )
            );

            vars.currentVariableBorrowRate = _baseVariableBorrowRate.add(
                vars.utilizationRate.rayMul(_variableRateSlope1).rayDiv(
                    OPTIMAL_UTILIZATION_RATE
                )
            );
        }

        vars.currentLiquidityRate = _getOverallBorrowRate(
            totalStableDebt,
            totalVariableDebt,
            vars.currentVariableBorrowRate,
            averageStableBorrowRate
        ).rayMul(vars.utilizationRate).percentMul(
                PercentageMath.PERCENTAGE_FACTOR.sub(reserveFactor)
            );

        return (
            vars.currentLiquidityRate,
            vars.currentStableBorrowRate,
            vars.currentVariableBorrowRate
        );
    }

    function _getOverallBorrowRate(
        uint256 totalStableDebt,
        uint256 totalVariableDebt,
        uint256 currentVariableBorrowRate,
        uint256 currentAverageStableBorrowRate
    ) internal pure returns (uint256) {
        uint256 totalDebt = totalStableDebt.add(totalVariableDebt);

        if (totalDebt == 0) return 0;

        uint256 weightedVariableRate = totalVariableDebt.wadToRay().rayMul(
            currentVariableBorrowRate
        );

        uint256 weightedStableRate = totalStableDebt.wadToRay().rayMul(
            currentAverageStableBorrowRate
        );

        uint256 overallBorrowRate = weightedVariableRate
            .add(weightedStableRate)
            .rayDiv(totalDebt.wadToRay());

        return overallBorrowRate;
    }
}
