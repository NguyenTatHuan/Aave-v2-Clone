// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../interfaces/ILendingPoolCollateralManager.sol";
import "../../interfaces/IAToken.sol";
import "../../interfaces/IPriceOracleGetter.sol";
import "../../interfaces/IStableDebtToken.sol";
import "../../interfaces/IVariableDebtToken.sol";
import "../libraries/aave-upgradeability/VersionedInitializable.sol";
import "./LendingPoolStorage.sol";
import "../../openzeppelin/contracts/IERC20.sol";
import "../../openzeppelin/contracts/SafeERC20.sol";
import "../../openzeppelin/contracts/SafeMath.sol";
import "../libraries/math/WadRayMath.sol";
import "../libraries/math/PercentageMath.sol";
import "../libraries/logic/GenericLogic.sol";
import "../libraries/logic/ValidationLogic.sol";
import "../libraries/helpers/Helpers.sol";
import "../libraries/helpers/Errors.sol";
import "../libraries/types/DataTypes.sol";

contract LendingPoolCollateralManager is
    ILendingPoolCollateralManager,
    VersionedInitializable,
    LendingPoolStorage
{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using UserConfiguration for DataTypes.UserConfigurationMap;

    uint256 internal constant LIQUIDATION_CLOSE_FACTOR_PERCENT = 5000;

    struct LiquidationCallLocalVars {
        uint256 userCollateralBalance;
        uint256 userStableDebt;
        uint256 userVariableDebt;
        uint256 maxLiquidatableDebt;
        uint256 actualDebtToLiquidate;
        uint256 liquidationRatio;
        uint256 maxAmountCollateralToLiquidate;
        uint256 userStableRate;
        uint256 maxCollateralToLiquidate;
        uint256 debtAmountNeeded;
        uint256 healthFactor;
        uint256 liquidatorPreviousATokenBalance;
        IAToken collateralAtoken;
        bool isCollateralEnabled;
        DataTypes.InterestRateMode borrowRateMode;
        uint256 errorCode;
        string errorMsg;
    }

    function getRevision() internal pure override returns (uint256) {
        return 0;
    }

    function liquidationCall(
        address collateralAsset,
        address debtAsset,
        address user,
        uint256 debtToCover,
        bool receiveAToken
    ) external override returns (uint256, string memory) {
        DataTypes.ReserveData storage collateralReserve = _reserves[
            collateralAsset
        ];
        DataTypes.ReserveData storage debtReserve = _reserves[debtAsset];
        DataTypes.UserConfigurationMap storage userConfig = _usersConfig[user];

        LiquidationCallLocalVars memory vars;

        (, , , , vars.healthFactor) = GenericLogic.calculateUserAccountData(
            user,
            _reserves,
            userConfig,
            _reservesList,
            _reservesCount,
            _addressesProvider.getPriceOracle()
        );

        (vars.userStableDebt, vars.userVariableDebt) = Helpers
            .getUserCurrentDebt(user, debtReserve);

        (vars.errorCode, vars.errorMsg) = ValidationLogic
            .validateLiquidationCall(
                collateralReserve,
                debtReserve,
                userConfig,
                vars.healthFactor,
                vars.userStableDebt,
                vars.userVariableDebt
            );

        if (
            Errors.CollateralManagerErrors(vars.errorCode) !=
            Errors.CollateralManagerErrors.NO_ERROR
        ) {
            return (vars.errorCode, vars.errorMsg);
        }

        vars.collateralAtoken = IAToken(collateralReserve.aTokenAddress);
        vars.userCollateralBalance = vars.collateralAtoken.balanceOf(user);

        vars.maxLiquidatableDebt = vars
            .userStableDebt
            .add(vars.userVariableDebt)
            .percentMul(LIQUIDATION_CLOSE_FACTOR_PERCENT);

        vars.actualDebtToLiquidate = debtToCover > vars.maxLiquidatableDebt
            ? vars.maxLiquidatableDebt
            : debtToCover;

        (
            vars.maxCollateralToLiquidate,
            vars.debtAmountNeeded
        ) = _calculateAvailableCollateralToLiquidate(
            collateralReserve,
            debtReserve,
            collateralAsset,
            debtAsset,
            vars.actualDebtToLiquidate,
            vars.userCollateralBalance
        );

        if (vars.debtAmountNeeded < vars.actualDebtToLiquidate) {
            vars.actualDebtToLiquidate = vars.debtAmountNeeded;
        }

        if (!receiveAToken) {
            uint256 currentAvailableCollateral = IERC20(collateralAsset)
                .balanceOf(address(vars.collateralAtoken));
            if (
                currentAvailableCollateral < vars.maxAmountCollateralToLiquidate
            ) {
                return (
                    uint256(
                        Errors.CollateralManagerErrors.NOT_ENOUGH_LIQUIDITY
                    ),
                    Errors.LPCM_NOT_ENOUGH_LIQUIDITY_TO_LIQUIDATE
                );
            }
        }

        ReserveLogic.updateState(debtReserve);

        if (vars.userVariableDebt >= vars.actualDebtToLiquidate) {
            IVariableDebtToken(debtReserve.variableDebtTokenAddress).burn(
                user,
                vars.actualDebtToLiquidate,
                debtReserve.variableBorrowIndex
            );
        } else {
            if (vars.userVariableDebt > 0) {
                IVariableDebtToken(debtReserve.variableDebtTokenAddress).burn(
                    user,
                    vars.userVariableDebt,
                    debtReserve.variableBorrowIndex
                );
            }
            IStableDebtToken(debtReserve.stableDebtTokenAddress).burn(
                user,
                vars.actualDebtToLiquidate.sub(vars.userVariableDebt)
            );
        }

        ReserveLogic.updateInterestRates(
            debtReserve,
            debtAsset,
            debtReserve.aTokenAddress,
            vars.actualDebtToLiquidate,
            0
        );

        if (receiveAToken) {
            vars.liquidatorPreviousATokenBalance = IERC20(vars.collateralAtoken)
                .balanceOf(msg.sender);

            vars.collateralAtoken.transferOnLiquidation(
                user,
                msg.sender,
                vars.maxCollateralToLiquidate
            );

            if (vars.liquidatorPreviousATokenBalance == 0) {
                DataTypes.UserConfigurationMap
                    storage liquidatorConfig = _usersConfig[msg.sender];

                liquidatorConfig.setUsingAsCollateral(
                    collateralReserve.id,
                    true
                );

                emit ReserveUsedAsCollateralEnabled(
                    collateralAsset,
                    msg.sender
                );
            }
        } else {
            ReserveLogic.updateState(collateralReserve);

            ReserveLogic.updateInterestRates(
                collateralReserve,
                collateralAsset,
                address(vars.collateralAtoken),
                0,
                vars.maxCollateralToLiquidate
            );

            vars.collateralAtoken.burn(
                user,
                msg.sender,
                vars.maxCollateralToLiquidate,
                collateralReserve.liquidityIndex
            );
        }

        if (vars.maxCollateralToLiquidate == vars.userCollateralBalance) {
            userConfig.setUsingAsCollateral(collateralReserve.id, false);
            emit ReserveUsedAsCollateralDisabled(collateralAsset, user);
        }

        IERC20(debtAsset).safeTransferFrom(
            msg.sender,
            debtReserve.aTokenAddress,
            vars.actualDebtToLiquidate
        );

        emit LiquidationCall(
            collateralAsset,
            debtAsset,
            user,
            vars.actualDebtToLiquidate,
            vars.maxCollateralToLiquidate,
            msg.sender,
            receiveAToken
        );

        return (
            uint256(Errors.CollateralManagerErrors.NO_ERROR),
            Errors.LPCM_NO_ERRORS
        );
    }

    struct AvailableCollateralToLiquidateLocalVars {
        uint256 userCompoundedBorrowBalance;
        uint256 liquidationBonus;
        uint256 collateralPrice;
        uint256 debtAssetPrice;
        uint256 maxAmountCollateralToLiquidate;
        uint256 debtAssetDecimals;
        uint256 collateralDecimals;
    }

    function _calculateAvailableCollateralToLiquidate(
        DataTypes.ReserveData storage collateralReserve,
        DataTypes.ReserveData storage debtReserve,
        address collateralAsset,
        address debtAsset,
        uint256 debtToCover,
        uint256 userCollateralBalance
    ) internal view returns (uint256, uint256) {
        uint256 collateralAmount = 0;
        uint256 debtAmountNeeded = 0;
        IPriceOracleGetter oracle = IPriceOracleGetter(
            _addressesProvider.getPriceOracle()
        );

        AvailableCollateralToLiquidateLocalVars memory vars;

        vars.collateralPrice = oracle.getAssetPrice(collateralAsset);
        vars.debtAssetPrice = oracle.getAssetPrice(debtAsset);

        (
            ,
            ,
            vars.liquidationBonus,
            vars.collateralDecimals,

        ) = collateralReserve.configuration.getParams();

        vars.debtAssetDecimals = debtReserve.configuration.getDecimals();

        vars.maxAmountCollateralToLiquidate = vars
            .debtAssetPrice
            .mul(debtToCover)
            .mul(10 ** vars.collateralDecimals)
            .percentMul(vars.liquidationBonus)
            .div(vars.collateralPrice.mul(10 ** vars.debtAssetDecimals));

        if (vars.maxAmountCollateralToLiquidate > userCollateralBalance) {
            collateralAmount = userCollateralBalance;
            debtAmountNeeded = vars
                .collateralPrice
                .mul(collateralAmount)
                .mul(10 ** vars.debtAssetDecimals)
                .div(vars.debtAssetPrice.mul(10 ** vars.collateralDecimals))
                .percentDiv(vars.liquidationBonus);
        } else {
            collateralAmount = vars.maxAmountCollateralToLiquidate;
            debtAmountNeeded = debtToCover;
        }

        return (collateralAmount, debtAmountNeeded);
    }
}
