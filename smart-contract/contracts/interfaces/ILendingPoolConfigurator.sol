// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ILendingPoolConfigurator {
    struct InitReserveInput {
        address aTokenImpl;
        address stableDebtTokenImpl;
        address variableDebtTokenImpl;
        uint8 underlyingAssetDecimals;
        address interestRateStrategyAddress;
        address underlyingAsset;
        address treasury;
        address incentivesController;
        string underlyingAssetName;
        string aTokenName;
        string aTokenSymbol;
        string variableDebtTokenName;
        string variableDebtTokenSymbol;
        string stableDebtTokenName;
        string stableDebtTokenSymbol;
        bytes params;
    }

    struct UpdateATokenInput {
        address asset;
        address treasury;
        address incentivesController;
        string name;
        string symbol;
        address implementation;
        bytes params;
    }

    struct UpdateDebtTokenInput {
        address asset;
        address incentivesController;
        string name;
        string symbol;
        address implementation;
        bytes params;
    }

    event ReserveInitialized(
        address indexed asset,
        address indexed aToken,
        address stableDebtToken,
        address variableDebtToken,
        address interestRateStrategyAddress
    );

    event BorrowingEnabledOnReserve(
        address indexed asset,
        bool stableRateEnabled
    );

    event BorrowingDisabledOnReserve(address indexed asset);

    event CollateralConfigurationChanged(
        address indexed asset,
        uint256 ltv,
        uint256 liquidationThreshold,
        uint256 liquidationBonus
    );

    event StableRateEnabledOnReserve(address indexed asset);

    event StableRateDisabledOnReserve(address indexed asset);

    event ReserveActivated(address indexed asset);

    event ReserveDeactivated(address indexed asset);

    event ReserveFrozen(address indexed asset);

    event ReserveUnfrozen(address indexed asset);

    event ReserveFactorChanged(address indexed asset, uint256 factor);

    event ReserveDecimalsChanged(address indexed asset, uint256 decimals);

    event ReserveInterestRateStrategyChanged(
        address indexed asset,
        address strategy
    );

    event ATokenUpgraded(
        address indexed asset,
        address indexed proxy,
        address indexed implementation
    );

    event StableDebtTokenUpgraded(
        address indexed asset,
        address indexed proxy,
        address indexed implementation
    );

    event VariableDebtTokenUpgraded(
        address indexed asset,
        address indexed proxy,
        address indexed implementation
    );
}
