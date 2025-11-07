// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../../openzeppelin/contracts/SafeMath.sol";
import "../../../openzeppelin/contracts/IERC20.sol";
import "../../../openzeppelin/contracts/SafeERC20.sol";
import "./ReserveLogic.sol";
import "./GenericLogic.sol";
import "../math/WadRayMath.sol";
import "../math/PercentageMath.sol";
import "../configuration/ReserveConfiguration.sol";
import "../configuration/UserConfiguration.sol";
import "../helpers/Errors.sol";
import "../helpers/Helpers.sol";
import "../types/DataTypes.sol";
import "../../../interfaces/IReserveInterestRateStrategy.sol";

library ValidationLogic {
    using ReserveLogic for DataTypes.ReserveData;
    using SafeMath for uint256;
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using SafeERC20 for IERC20;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using UserConfiguration for DataTypes.UserConfigurationMap;

    uint256 public constant REBALANCE_UP_LIQUIDITY_RATE_THRESHOLD = 4000;
    uint256 public constant REBALANCE_UP_USAGE_RATIO_THRESHOLD = 0.95 * 1e27;

    function validateDeposit(
        DataTypes.ReserveData storage reserve,
        uint256 amount
    ) external view {
        (bool isActive, bool isFrozen, , ) = reserve.configuration.getFlags();
        require(amount != 0, Errors.VL_INVALID_AMOUNT);
        require(isActive, Errors.VL_NO_ACTIVE_RESERVE);
        require(!isFrozen, Errors.VL_RESERVE_FROZEN);
    }

    function validateWithdraw(
        address reserveAddress,
        uint256 amount,
        uint256 userBalance,
        mapping(address => DataTypes.ReserveData) storage reservesData,
        DataTypes.UserConfigurationMap storage userConfig,
        mapping(uint256 => address) storage reserves,
        uint256 reservesCount,
        address oracle
    ) external view {
        (bool isActive, , , ) = reservesData[reserveAddress]
            .configuration
            .getFlags();

        require(amount != 0, Errors.VL_INVALID_AMOUNT);

        require(
            amount <= userBalance,
            Errors.VL_NOT_ENOUGH_AVAILABLE_USER_BALANCE
        );

        require(isActive, Errors.VL_NO_ACTIVE_RESERVE);

        require(
            GenericLogic.balanceDecreaseAllowed(
                reserveAddress,
                msg.sender,
                amount,
                reservesData,
                userConfig,
                reserves,
                reservesCount,
                oracle
            ),
            Errors.VL_TRANSFER_NOT_ALLOWED
        );
    }

    struct ValidateBorrowLocalVars {
        uint256 currentLtv;
        uint256 currentLiquidationThreshold;
        uint256 amountOfCollateralNeededETH;
        uint256 userCollateralBalanceETH;
        uint256 userBorrowBalanceETH;
        uint256 availableLiquidity;
        uint256 healthFactor;
        bool isActive;
        bool isFrozen;
        bool borrowingEnabled;
        bool stableRateBorrowingEnabled;
    }

    function validateBorrow(
        address asset,
        DataTypes.ReserveData storage reserve,
        address userAddress,
        uint256 amount,
        uint256 amountInETH,
        uint256 interestRateMode,
        uint256 maxStableLoanPercent,
        mapping(address => DataTypes.ReserveData) storage reservesData,
        DataTypes.UserConfigurationMap storage userConfig,
        mapping(uint256 => address) storage reserves,
        uint256 reservesCount,
        address oracle
    ) external view {
        ValidateBorrowLocalVars memory vars;

        (
            vars.isActive,
            vars.isFrozen,
            vars.borrowingEnabled,
            vars.stableRateBorrowingEnabled
        ) = reserve.configuration.getFlags();

        require(vars.isActive, Errors.VL_NO_ACTIVE_RESERVE);
        require(!vars.isFrozen, Errors.VL_RESERVE_FROZEN);
        require(amount != 0, Errors.VL_INVALID_AMOUNT);
        require(vars.borrowingEnabled, Errors.VL_BORROWING_NOT_ENABLED);
        require(
            uint256(DataTypes.InterestRateMode.VARIABLE) == interestRateMode ||
                uint256(DataTypes.InterestRateMode.STABLE) == interestRateMode,
            Errors.VL_INVALID_INTEREST_RATE_MODE_SELECTED
        );

        (
            vars.userCollateralBalanceETH,
            vars.userBorrowBalanceETH,
            vars.currentLtv,
            vars.currentLiquidationThreshold,
            vars.healthFactor
        ) = GenericLogic.calculateUserAccountData(
            userAddress,
            reservesData,
            userConfig,
            reserves,
            reservesCount,
            oracle
        );

        require(
            vars.userCollateralBalanceETH > 0,
            Errors.VL_COLLATERAL_BALANCE_IS_0
        );

        require(
            vars.healthFactor >
                GenericLogic.HEALTH_FACTOR_LIQUIDATION_THRESHOLD,
            Errors.VL_HEALTH_FACTOR_LOWER_THAN_LIQUIDATION_THRESHOLD
        );

        vars.amountOfCollateralNeededETH = vars
            .userBorrowBalanceETH
            .add(amountInETH)
            .percentDiv(vars.currentLtv);

        require(
            vars.amountOfCollateralNeededETH <= vars.userCollateralBalanceETH,
            Errors.VL_COLLATERAL_CANNOT_COVER_NEW_BORROW
        );

        if (interestRateMode == uint256(DataTypes.InterestRateMode.STABLE)) {
            require(
                vars.stableRateBorrowingEnabled,
                Errors.VL_STABLE_BORROWING_NOT_ENABLED
            );

            require(
                !userConfig.isUsingAsCollateral(reserve.id) ||
                    reserve.configuration.getLtv() == 0 ||
                    amount >
                    IERC20(reserve.aTokenAddress).balanceOf(userAddress),
                Errors.VL_COLLATERAL_SAME_AS_BORROWING_CURRENCY
            );

            vars.availableLiquidity = IERC20(asset).balanceOf(
                reserve.aTokenAddress
            );

            uint256 maxLoanSizeStable = vars.availableLiquidity.percentMul(
                maxStableLoanPercent
            );

            require(
                amount <= maxLoanSizeStable,
                Errors.VL_AMOUNT_BIGGER_THAN_MAX_LOAN_SIZE_STABLE
            );
        }
    }

    function validateRepay(
        DataTypes.ReserveData storage reserve,
        uint256 amountSent,
        DataTypes.InterestRateMode rateMode,
        address onBehalfOf,
        uint256 stableDebt,
        uint256 variableDebt
    ) external view {
        bool isActive = reserve.configuration.getActive();

        require(isActive, Errors.VL_NO_ACTIVE_RESERVE);
        require(amountSent > 0, Errors.VL_INVALID_AMOUNT);

        require(
            (stableDebt > 0 &&
                DataTypes.InterestRateMode(rateMode) ==
                DataTypes.InterestRateMode.STABLE) ||
                (variableDebt > 0 &&
                    DataTypes.InterestRateMode(rateMode) ==
                    DataTypes.InterestRateMode.VARIABLE),
            Errors.VL_NO_DEBT_OF_SELECTED_TYPE
        );

        require(
            amountSent != type(uint256).max || msg.sender == onBehalfOf,
            Errors.VL_NO_EXPLICIT_AMOUNT_TO_REPAY_ON_BEHALF
        );
    }

    function validateSwapRateMode(
        DataTypes.ReserveData storage reserve,
        DataTypes.UserConfigurationMap storage userConfig,
        uint256 stableDebt,
        uint256 variableDebt,
        DataTypes.InterestRateMode currentRateMode
    ) external view {
        (bool isActive, bool isFrozen, , bool stableRateEnabled) = reserve
            .configuration
            .getFlags();

        require(isActive, Errors.VL_NO_ACTIVE_RESERVE);
        require(!isFrozen, Errors.VL_RESERVE_FROZEN);

        if (currentRateMode == DataTypes.InterestRateMode.STABLE) {
            require(
                stableDebt > 0,
                Errors.VL_NO_STABLE_RATE_LOAN_IN_RESERVE
            );
        } else if (currentRateMode == DataTypes.InterestRateMode.VARIABLE) {
            require(
                variableDebt > 0,
                Errors.VL_NO_VARIABLE_RATE_LOAN_IN_RESERVE
            );

            require(
                stableRateEnabled,
                Errors.VL_STABLE_BORROWING_NOT_ENABLED
            );

            require(
                !userConfig.isUsingAsCollateral(reserve.id) ||
                    reserve.configuration.getLtv() == 0 ||
                    stableDebt.add(variableDebt) >
                    IERC20(reserve.aTokenAddress).balanceOf(msg.sender),
                Errors.VL_COLLATERAL_SAME_AS_BORROWING_CURRENCY
            );
        } else {
            revert(Errors.VL_INVALID_INTEREST_RATE_MODE_SELECTED);
        }
    }

    function validateRebalanceStableBorrowRate(
        DataTypes.ReserveData storage reserve,
        address reserveAddress,
        IERC20 stableDebtToken,
        IERC20 variableDebtToken,
        address aTokenAddress
    ) external view {
        (bool isActive, , , ) = reserve.configuration.getFlags();

        require(isActive, Errors.VL_NO_ACTIVE_RESERVE);

        uint256 totalDebt = stableDebtToken
            .totalSupply()
            .add(variableDebtToken.totalSupply())
            .wadToRay();

        uint256 availableLiquidity = IERC20(reserveAddress)
            .balanceOf(aTokenAddress)
            .wadToRay();

        uint256 usageRatio = totalDebt == 0
            ? 0
            : totalDebt.rayDiv(availableLiquidity.add(totalDebt));

        uint256 currentLiquidityRate = reserve.currentLiquidityRate;

        uint256 maxVariableBorrowRate = IReserveInterestRateStrategy(
            reserve.interestRateStrategyAddress
        ).getMaxVariableBorrowRate();

        require(
            usageRatio >= REBALANCE_UP_USAGE_RATIO_THRESHOLD &&
                currentLiquidityRate <=
                maxVariableBorrowRate.percentMul(
                    REBALANCE_UP_LIQUIDITY_RATE_THRESHOLD
                ),
            Errors.LP_INTEREST_RATE_REBALANCE_CONDITIONS_NOT_MET
        );
    }

    function validateSetUseReserveAsCollateral(
        DataTypes.ReserveData storage reserve,
        address reserveAddress,
        bool useAsCollateral,
        mapping(address => DataTypes.ReserveData) storage reservesData,
        DataTypes.UserConfigurationMap storage userConfig,
        mapping(uint256 => address) storage reserves,
        uint256 reservesCount,
        address oracle
    ) external view {
        uint256 underlyingBalance = IERC20(reserve.aTokenAddress).balanceOf(
            msg.sender
        );

        require(
            underlyingBalance > 0,
            Errors.VL_UNDERLYING_BALANCE_NOT_GREATER_THAN_0
        );

        require(
            useAsCollateral ||
                GenericLogic.balanceDecreaseAllowed(
                    reserveAddress,
                    msg.sender,
                    underlyingBalance,
                    reservesData,
                    userConfig,
                    reserves,
                    reservesCount,
                    oracle
                ),
            Errors.VL_DEPOSIT_ALREADY_IN_USE
        );
    }

    function validateFlashloan(
        address[] memory assets,
        uint256[] memory amounts
    ) internal pure {
        require(
            assets.length == amounts.length,
            Errors.VL_INCONSISTENT_FLASHLOAN_PARAMS
        );
    }

    function validateLiquidationCall(
        DataTypes.ReserveData storage collateralReserve,
        DataTypes.ReserveData storage principalReserve,
        DataTypes.UserConfigurationMap storage userConfig,
        uint256 userHealthFactor,
        uint256 userStableDebt,
        uint256 userVariableDebt
    ) internal view returns (uint256, string memory) {
        if (
            !collateralReserve.configuration.getActive() ||
            !principalReserve.configuration.getActive()
        ) {
            return (
                uint256(Errors.CollateralManagerErrors.NO_ACTIVE_RESERVE),
                Errors.VL_NO_ACTIVE_RESERVE
            );
        }

        if (
            userHealthFactor >= GenericLogic.HEALTH_FACTOR_LIQUIDATION_THRESHOLD
        ) {
            return (
                uint256(
                    Errors
                        .CollateralManagerErrors
                        .HEALTH_FACTOR_ABOVE_THRESHOLD
                ),
                Errors.LPCM_HEALTH_FACTOR_NOT_BELOW_THRESHOLD
            );
        }

        bool isCollateralEnabled = collateralReserve
            .configuration
            .getLiquidationThreshold() >
            0 &&
            userConfig.isUsingAsCollateral(collateralReserve.id);

        if (!isCollateralEnabled) {
            return (
                uint256(
                    Errors
                        .CollateralManagerErrors
                        .COLLATERAL_CANNOT_BE_LIQUIDATED
                ),
                Errors.LPCM_COLLATERAL_CANNOT_BE_LIQUIDATED
            );
        }

        if (userStableDebt == 0 && userVariableDebt == 0) {
            return (
                uint256(
                    Errors.CollateralManagerErrors.CURRRENCY_NOT_BORROWED
                ),
                Errors.LPCM_SPECIFIED_CURRENCY_NOT_BORROWED_BY_USER
            );
        }

        return (
            uint256(Errors.CollateralManagerErrors.NO_ERROR),
            Errors.LPCM_NO_ERRORS
        );
    }

    function validateTransfer(
        address from,
        mapping(address => DataTypes.ReserveData) storage reservesData,
        DataTypes.UserConfigurationMap storage userConfig,
        mapping(uint256 => address) storage reserves,
        uint256 reservesCount,
        address oracle
    ) internal view {
        (, , , , uint256 healthFactor) = GenericLogic.calculateUserAccountData(
            from,
            reservesData,
            userConfig,
            reserves,
            reservesCount,
            oracle
        );

        require(
            healthFactor >= GenericLogic.HEALTH_FACTOR_LIQUIDATION_THRESHOLD,
            Errors.VL_TRANSFER_NOT_ALLOWED
        );
    }
}
