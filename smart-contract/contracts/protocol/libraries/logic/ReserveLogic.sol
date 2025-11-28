// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../../openzeppelin/contracts/SafeMath.sol";
import "../../../openzeppelin/contracts/IERC20.sol";
import "../../../openzeppelin/contracts/SafeERC20.sol";
import "../math/WadRayMath.sol";
import "../math/PercentageMath.sol";
import "../math/MathUtils.sol";
import "../helpers/Errors.sol";
import "../types/DataTypes.sol";
import "../configuration/ReserveConfiguration.sol";
import "../../../interfaces/IAToken.sol";
import "../../../interfaces/IStableDebtToken.sol";
import "../../../interfaces/IVariableDebtToken.sol";
import "../../../interfaces/IReserveInterestRateStrategy.sol";

library ReserveLogic {
    using SafeMath for uint256;
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using SafeERC20 for IERC20;

    event ReserveDataUpdated(
        address indexed asset,
        uint256 liquidityRate,
        uint256 stableBorrowRate,
        uint256 variableBorrowRate,
        uint256 liquidityIndex,
        uint256 variableBorrowIndex
    );

    using ReserveLogic for DataTypes.ReserveData;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    function getNormalizedIncome(
        DataTypes.ReserveData storage reserve
    ) internal view returns (uint256) {
        uint40 timestamp = reserve.lastUpdateTimestamp;

        if (timestamp == uint40(block.timestamp)) {
            return reserve.liquidityIndex;
        }

        return
            MathUtils
                .calculateLinearInterest(
                    reserve.currentLiquidityRate,
                    timestamp
                )
                .rayMul(reserve.liquidityIndex);
    }

    function getNormalizedDebt(
        DataTypes.ReserveData storage reserve
    ) internal view returns (uint256) {
        uint40 timestamp = reserve.lastUpdateTimestamp;

        if (timestamp == uint40(block.timestamp)) {
            return reserve.variableBorrowIndex;
        }

        return
            MathUtils
                .calculateCompoundedInterest(
                    reserve.currentVariableBorrowRate,
                    timestamp
                )
                .rayMul(reserve.variableBorrowIndex);
    }

    function updateState(DataTypes.ReserveData storage reserve) internal {
        uint256 scaledVariableDebt = IVariableDebtToken(
            reserve.variableDebtTokenAddress
        ).scaledTotalSupply();
        
        uint256 previousVariableBorrowIndex = reserve.variableBorrowIndex;
        uint256 previousLiquidityIndex = reserve.liquidityIndex;
        uint40 lastUpdatedTimestamp = reserve.lastUpdateTimestamp;

        (
            uint256 newLiquidityIndex,
            uint256 newVariableBorrowIndex
        ) = _updateIndexes(
                reserve,
                scaledVariableDebt,
                previousLiquidityIndex,
                previousVariableBorrowIndex,
                lastUpdatedTimestamp
            );

        _mintToTreasury(
            reserve,
            scaledVariableDebt,
            previousVariableBorrowIndex,
            newLiquidityIndex,
            newVariableBorrowIndex,
            lastUpdatedTimestamp
        );
    }

    function cumulateToLiquidityIndex(
        DataTypes.ReserveData storage reserve,
        uint256 totalLiquidity,
        uint256 amount
    ) internal {
        uint256 amountToLiquidityRatio = amount.wadToRay().rayDiv(
            totalLiquidity.wadToRay()
        );

        uint256 result = amountToLiquidityRatio.add(WadRayMath.ray());

        result = result.rayMul(reserve.liquidityIndex);
        require(
            result <= type(uint128).max,
            Errors.RL_LIQUIDITY_INDEX_OVERFLOW
        );

        reserve.liquidityIndex = uint128(result);
    }

    function init(
        DataTypes.ReserveData storage reserve,
        address aTokenAddress,
        address stableDebtTokenAddress,
        address variableDebtTokenAddress,
        address interestRateStrategyAddress
    ) external {
        require(
            reserve.aTokenAddress == address(0),
            Errors.RL_RESERVE_ALREADY_INITIALIZED
        );
        reserve.liquidityIndex = uint128(WadRayMath.ray());
        reserve.variableBorrowIndex = uint128(WadRayMath.ray());
        reserve.aTokenAddress = aTokenAddress;
        reserve.stableDebtTokenAddress = stableDebtTokenAddress;
        reserve.variableDebtTokenAddress = variableDebtTokenAddress;
        reserve.interestRateStrategyAddress = interestRateStrategyAddress;
    }

    struct UpdateInterestRatesLocalVars {
        address stableDebtTokenAddress;
        uint256 availableLiquidity;
        uint256 totalStableDebt;
        uint256 newLiquidityRate;
        uint256 newStableRate;
        uint256 newVariableRate;
        uint256 avgStableRate;
        uint256 totalVariableDebt;
    }

    function updateInterestRates(
        DataTypes.ReserveData storage reserve,
        address reserveAddress,
        address aTokenAddress,
        uint256 liquidityAdded,
        uint256 liquidityTaken
    ) internal {
        UpdateInterestRatesLocalVars memory vars;

        vars.stableDebtTokenAddress = reserve.stableDebtTokenAddress;

        (vars.totalStableDebt, vars.avgStableRate) = IStableDebtToken(
            vars.stableDebtTokenAddress
        ).getTotalSupplyAndAvgRate();

        vars.totalVariableDebt = IVariableDebtToken(
            reserve.variableDebtTokenAddress
        ).scaledTotalSupply().rayMul(reserve.variableBorrowIndex);

        (
            vars.newLiquidityRate,
            vars.newStableRate,
            vars.newVariableRate
        ) = IReserveInterestRateStrategy(reserve.interestRateStrategyAddress)
            .calculateInterestRates(
                reserveAddress,
                aTokenAddress,
                liquidityAdded,
                liquidityTaken,
                vars.totalStableDebt,
                vars.totalVariableDebt,
                vars.avgStableRate,
                reserve.configuration.getReserveFactor()
            );

        require(
            vars.newLiquidityRate <= type(uint128).max,
            Errors.RL_LIQUIDITY_RATE_OVERFLOW
        );
        require(
            vars.newStableRate <= type(uint128).max,
            Errors.RL_STABLE_BORROW_RATE_OVERFLOW
        );
        require(
            vars.newVariableRate <= type(uint128).max,
            Errors.RL_VARIABLE_BORROW_RATE_OVERFLOW
        );

        reserve.currentLiquidityRate = uint128(vars.newLiquidityRate);
        reserve.currentStableBorrowRate = uint128(vars.newStableRate);
        reserve.currentVariableBorrowRate = uint128(vars.newVariableRate);

        emit ReserveDataUpdated(
            reserveAddress,
            vars.newLiquidityRate,
            vars.newStableRate,
            vars.newVariableRate,
            reserve.liquidityIndex,
            reserve.variableBorrowIndex
        );
    }

    struct MintToTreasuryLocalVars {
        uint256 currentStableDebt;
        uint256 principalStableDebt;
        uint256 previousStableDebt;
        uint256 currentVariableDebt;
        uint256 previousVariableDebt;
        uint256 avgStableRate;
        uint256 cumulatedStableInterest;
        uint256 totalDebtAccrued;
        uint256 amountToMint;
        uint256 reserveFactor;
        uint40 stableSupplyUpdatedTimestamp;
    }

    function _mintToTreasury(
        DataTypes.ReserveData storage reserve,
        uint256 scaledVariableDebt,
        uint256 previousVariableBorrowIndex,
        uint256 newLiquidityIndex,
        uint256 newVariableBorrowIndex,
        uint40 timestamp
    ) internal {
        MintToTreasuryLocalVars memory vars;

        vars.reserveFactor = reserve.configuration.getReserveFactor();

        if (vars.reserveFactor == 0) {
            return;
        }

        (
            vars.principalStableDebt,
            vars.currentStableDebt,
            vars.avgStableRate,
            vars.stableSupplyUpdatedTimestamp
        ) = IStableDebtToken(reserve.stableDebtTokenAddress).getSupplyData();

        vars.previousVariableDebt = scaledVariableDebt.rayMul(
            previousVariableBorrowIndex
        );

        vars.currentVariableDebt = scaledVariableDebt.rayMul(
            newVariableBorrowIndex
        );

        vars.cumulatedStableInterest = MathUtils.calculateCompoundedInterest(
            vars.avgStableRate,
            vars.stableSupplyUpdatedTimestamp,
            timestamp
        );

        vars.previousStableDebt = vars.principalStableDebt.rayMul(
            vars.cumulatedStableInterest
        );

        vars.totalDebtAccrued = vars
            .currentVariableDebt
            .add(vars.currentStableDebt)
            .sub(vars.previousVariableDebt)
            .sub(vars.previousStableDebt);

        vars.amountToMint = vars.totalDebtAccrued.percentMul(
            vars.reserveFactor
        );

        if (vars.amountToMint != 0) {
            IAToken(reserve.aTokenAddress).mintToTreasury(
                vars.amountToMint,
                newLiquidityIndex
            );
        }
    }

    function _updateIndexes(
        DataTypes.ReserveData storage reserve,
        uint256 scaledVariableDebt,
        uint256 liquidityIndex,
        uint256 variableBorrowIndex,
        uint40 timestamp
    ) internal returns (uint256, uint256) {
        uint256 currentLiquidityRate = reserve.currentLiquidityRate;
        uint256 newLiquidityIndex = liquidityIndex;
        uint256 newVariableBorrowIndex = variableBorrowIndex;

        if (currentLiquidityRate > 0) {
            uint256 cumulatedLiquidityInterest = MathUtils
                .calculateLinearInterest(currentLiquidityRate, timestamp);

            newLiquidityIndex = cumulatedLiquidityInterest.rayMul(
                liquidityIndex
            );

            require(
                newLiquidityIndex <= type(uint128).max,
                Errors.RL_LIQUIDITY_INDEX_OVERFLOW
            );

            reserve.liquidityIndex = uint128(newLiquidityIndex);

            if (scaledVariableDebt != 0) {
                uint256 cumulatedVariableBorrowInterest = MathUtils
                    .calculateCompoundedInterest(
                        reserve.currentVariableBorrowRate,
                        timestamp
                    );

                newVariableBorrowIndex = cumulatedVariableBorrowInterest.rayMul(
                    variableBorrowIndex
                );

                require(
                    newVariableBorrowIndex <= type(uint128).max,
                    Errors.RL_VARIABLE_BORROW_INDEX_OVERFLOW
                );

                reserve.variableBorrowIndex = uint128(newVariableBorrowIndex);
            }
        }

        reserve.lastUpdateTimestamp = uint40(block.timestamp);
        return (newLiquidityIndex, newVariableBorrowIndex);
    }
}
