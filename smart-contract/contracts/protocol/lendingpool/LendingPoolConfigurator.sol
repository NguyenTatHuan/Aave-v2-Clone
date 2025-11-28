// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../interfaces/ILendingPoolConfigurator.sol";
import "../../interfaces/ILendingPoolAddressesProvider.sol";
import "../../interfaces/ILendingPool.sol";
import "../../interfaces/IAaveIncentivesController.sol";
import "../../interfaces/IInitializableAToken.sol";
import "../../interfaces/IInitializableDebtToken.sol";
import "../../openzeppelin/contracts/SafeMath.sol";
import "../../openzeppelin/contracts/IERC20Detailed.sol";
import "../libraries/aave-upgradeability/VersionedInitializable.sol";
import "../libraries/aave-upgradeability/InitializableImmutableAdminUpgradeabilityProxy.sol";
import "../libraries/math/PercentageMath.sol";
import "../libraries/configuration/ReserveConfiguration.sol";
import "../libraries/types/DataTypes.sol";
import "../libraries/helpers/Errors.sol";

contract LendingPoolConfigurator is
    ILendingPoolConfigurator,
    VersionedInitializable
{
    using SafeMath for uint256;
    using PercentageMath for uint256;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    ILendingPoolAddressesProvider internal addressesProvider;
    ILendingPool internal pool;

    modifier onlyPoolAdmin() {
        require(
            addressesProvider.getPoolAdmin() == msg.sender,
            Errors.CALLER_NOT_POOL_ADMIN
        );
        _;
    }

    modifier onlyEmergencyAdmin() {
        require(
            addressesProvider.getEmergencyAdmin() == msg.sender,
            Errors.LPC_CALLER_NOT_EMERGENCY_ADMIN
        );
        _;
    }

    uint256 internal constant CONFIGURATOR_REVISION = 0x1;

    function getRevision() internal pure override returns (uint256) {
        return CONFIGURATOR_REVISION;
    }

    function initialize(
        ILendingPoolAddressesProvider provider
    ) public initializer {
        addressesProvider = provider;
        pool = ILendingPool(addressesProvider.getLendingPool());
    }

    function batchInitReserve(
        InitReserveInput[] calldata input
    ) external onlyPoolAdmin {
        ILendingPool cachedPool = pool;
        for (uint256 i = 0; i < input.length; i++) {
            _initReserve(cachedPool, input[i]);
        }
    }

    function _initReserve(
        ILendingPool lendingPool,
        InitReserveInput calldata input
    ) internal {
        address aTokenProxyAddress = _initTokenWithProxy(
            input.aTokenImpl,
            abi.encodeWithSelector(
                IInitializableAToken.initialize.selector,
                lendingPool,
                input.treasury,
                input.underlyingAsset,
                IAaveIncentivesController(input.incentivesController),
                input.underlyingAssetDecimals,
                input.aTokenName,
                input.aTokenSymbol,
                input.params
            )
        );

        address stableDebtTokenProxyAddress = _initTokenWithProxy(
            input.stableDebtTokenImpl,
            abi.encodeWithSelector(
                IInitializableDebtToken.initialize.selector,
                lendingPool,
                input.underlyingAsset,
                IAaveIncentivesController(input.incentivesController),
                input.underlyingAssetDecimals,
                input.stableDebtTokenName,
                input.stableDebtTokenSymbol,
                input.params
            )
        );

        address variableDebtTokenProxyAddress = _initTokenWithProxy(
            input.variableDebtTokenImpl,
            abi.encodeWithSelector(
                IInitializableDebtToken.initialize.selector,
                lendingPool,
                input.underlyingAsset,
                IAaveIncentivesController(input.incentivesController),
                input.underlyingAssetDecimals,
                input.variableDebtTokenName,
                input.variableDebtTokenSymbol,
                input.params
            )
        );

        lendingPool.initReserve(
            input.underlyingAsset,
            aTokenProxyAddress,
            stableDebtTokenProxyAddress,
            variableDebtTokenProxyAddress,
            input.interestRateStrategyAddress
        );

        DataTypes.ReserveConfigurationMap memory currentConfig = lendingPool
            .getConfiguration(input.underlyingAsset);

        currentConfig.setDecimals(input.underlyingAssetDecimals);
        currentConfig.setActive(true);
        currentConfig.setFrozen(false);

        lendingPool.setConfiguration(input.underlyingAsset, currentConfig.data);

        emit ReserveInitialized(
            input.underlyingAsset,
            aTokenProxyAddress,
            stableDebtTokenProxyAddress,
            variableDebtTokenProxyAddress,
            input.interestRateStrategyAddress
        );
    }

    function updateAToken(
        UpdateATokenInput calldata input
    ) external onlyPoolAdmin {
        ILendingPool cachedPool = pool;

        DataTypes.ReserveData memory reserveData = cachedPool.getReserveData(
            input.asset
        );

        (, , , uint256 decimals, ) = cachedPool
            .getConfiguration(input.asset)
            .getParamsMemory();

        bytes memory encodedCall = abi.encodeWithSelector(
            IInitializableAToken.initialize.selector,
            cachedPool,
            input.treasury,
            input.asset,
            input.incentivesController,
            decimals,
            input.name,
            input.symbol,
            input.params
        );

        _upgradeTokenImplementation(
            reserveData.aTokenAddress,
            input.implementation,
            encodedCall
        );

        emit ATokenUpgraded(
            input.asset,
            reserveData.aTokenAddress,
            input.implementation
        );
    }

    function updateStableDebtToken(
        UpdateDebtTokenInput calldata input
    ) external onlyPoolAdmin {
        ILendingPool cachedPool = pool;

        DataTypes.ReserveData memory reserveData = cachedPool.getReserveData(
            input.asset
        );

        (, , , uint256 decimals, ) = cachedPool
            .getConfiguration(input.asset)
            .getParamsMemory();

        bytes memory encodedCall = abi.encodeWithSelector(
            IInitializableDebtToken.initialize.selector,
            cachedPool,
            input.asset,
            input.incentivesController,
            decimals,
            input.name,
            input.symbol,
            input.params
        );

        _upgradeTokenImplementation(
            reserveData.stableDebtTokenAddress,
            input.implementation,
            encodedCall
        );

        emit StableDebtTokenUpgraded(
            input.asset,
            reserveData.stableDebtTokenAddress,
            input.implementation
        );
    }

    function updateVariableDebtToken(
        UpdateDebtTokenInput calldata input
    ) external onlyPoolAdmin {
        ILendingPool cachedPool = pool;

        DataTypes.ReserveData memory reserveData = cachedPool.getReserveData(
            input.asset
        );

        (, , , uint256 decimals, ) = cachedPool
            .getConfiguration(input.asset)
            .getParamsMemory();

        bytes memory encodedCall = abi.encodeWithSelector(
            IInitializableDebtToken.initialize.selector,
            cachedPool,
            input.asset,
            input.incentivesController,
            decimals,
            input.name,
            input.symbol,
            input.params
        );

        _upgradeTokenImplementation(
            reserveData.variableDebtTokenAddress,
            input.implementation,
            encodedCall
        );

        emit VariableDebtTokenUpgraded(
            input.asset,
            reserveData.variableDebtTokenAddress,
            input.implementation
        );
    }

    function enableBorrowingOnReserve(
        address asset,
        bool stableBorrowRateEnabled
    ) external onlyPoolAdmin {
        DataTypes.ReserveConfigurationMap memory currentConfig = pool
            .getConfiguration(asset);

        currentConfig.setBorrowingEnabled(true);
        currentConfig.setStableRateBorrowingEnabled(stableBorrowRateEnabled);

        pool.setConfiguration(asset, currentConfig.data);

        emit BorrowingEnabledOnReserve(asset, stableBorrowRateEnabled);
    }

    function disableBorrowingOnReserve(address asset) external onlyPoolAdmin {
        DataTypes.ReserveConfigurationMap memory currentConfig = pool
            .getConfiguration(asset);

        currentConfig.setBorrowingEnabled(false);

        pool.setConfiguration(asset, currentConfig.data);
        emit BorrowingDisabledOnReserve(asset);
    }

    function configureReserveAsCollateral(
        address asset,
        uint256 ltv,
        uint256 liquidationThreshold,
        uint256 liquidationBonus
    ) external onlyPoolAdmin {
        DataTypes.ReserveConfigurationMap memory currentConfig = pool
            .getConfiguration(asset);

        require(ltv <= liquidationThreshold, Errors.LPC_INVALID_CONFIGURATION);

        if (liquidationThreshold != 0) {
            require(
                liquidationBonus > PercentageMath.PERCENTAGE_FACTOR,
                Errors.LPC_INVALID_CONFIGURATION
            );

            require(
                liquidationThreshold.percentMul(liquidationBonus) <=
                    PercentageMath.PERCENTAGE_FACTOR,
                Errors.LPC_INVALID_CONFIGURATION
            );
        } else {
            require(liquidationBonus == 0, Errors.LPC_INVALID_CONFIGURATION);
            _checkNoLiquidity(asset);
        }

        currentConfig.setLtv(ltv);
        currentConfig.setLiquidationThreshold(liquidationThreshold);
        currentConfig.setLiquidationBonus(liquidationBonus);

        pool.setConfiguration(asset, currentConfig.data);

        emit CollateralConfigurationChanged(
            asset,
            ltv,
            liquidationThreshold,
            liquidationBonus
        );
    }

    function enableReserveStableRate(address asset) external onlyPoolAdmin {
        DataTypes.ReserveConfigurationMap memory currentConfig = pool
            .getConfiguration(asset);

        currentConfig.setStableRateBorrowingEnabled(true);

        pool.setConfiguration(asset, currentConfig.data);

        emit StableRateEnabledOnReserve(asset);
    }

    function disableReserveStableRate(address asset) external onlyPoolAdmin {
        DataTypes.ReserveConfigurationMap memory currentConfig = pool
            .getConfiguration(asset);

        currentConfig.setStableRateBorrowingEnabled(false);

        pool.setConfiguration(asset, currentConfig.data);

        emit StableRateDisabledOnReserve(asset);
    }

    function activateReserve(address asset) external onlyPoolAdmin {
        DataTypes.ReserveConfigurationMap memory currentConfig = pool
            .getConfiguration(asset);

        currentConfig.setActive(true);

        pool.setConfiguration(asset, currentConfig.data);

        emit ReserveActivated(asset);
    }

    function deactivateReserve(address asset) external onlyPoolAdmin {
        _checkNoLiquidity(asset);

        DataTypes.ReserveConfigurationMap memory currentConfig = pool
            .getConfiguration(asset);

        currentConfig.setActive(false);

        pool.setConfiguration(asset, currentConfig.data);

        emit ReserveDeactivated(asset);
    }

    function freezeReserve(address asset) external onlyPoolAdmin {
        DataTypes.ReserveConfigurationMap memory currentConfig = pool
            .getConfiguration(asset);

        currentConfig.setFrozen(true);

        pool.setConfiguration(asset, currentConfig.data);

        emit ReserveFrozen(asset);
    }

    function unfreezeReserve(address asset) external onlyPoolAdmin {
        DataTypes.ReserveConfigurationMap memory currentConfig = pool
            .getConfiguration(asset);

        currentConfig.setFrozen(false);

        pool.setConfiguration(asset, currentConfig.data);

        emit ReserveUnfrozen(asset);
    }

    function setReserveFactor(
        address asset,
        uint256 reserveFactor
    ) external onlyPoolAdmin {
        DataTypes.ReserveConfigurationMap memory currentConfig = pool
            .getConfiguration(asset);

        currentConfig.setReserveFactor(reserveFactor);

        pool.setConfiguration(asset, currentConfig.data);

        emit ReserveFactorChanged(asset, reserveFactor);
    }

    function setReserveInterestRateStrategyAddress(
        address asset,
        address rateStrategyAddress
    ) external onlyPoolAdmin {
        pool.setReserveInterestRateStrategyAddress(asset, rateStrategyAddress);
        emit ReserveInterestRateStrategyChanged(asset, rateStrategyAddress);
    }

    function setPoolPause(bool val) external onlyEmergencyAdmin {
        pool.setPause(val);
    }

    function _initTokenWithProxy(
        address implementation,
        bytes memory initParams
    ) internal returns (address) {
        InitializableImmutableAdminUpgradeabilityProxy proxy = new InitializableImmutableAdminUpgradeabilityProxy(
                address(this)
            );

        proxy.initialize(implementation, initParams);

        return address(proxy);
    }

    function _upgradeTokenImplementation(
        address proxyAddress,
        address implementation,
        bytes memory initParams
    ) internal {
        InitializableImmutableAdminUpgradeabilityProxy proxy = InitializableImmutableAdminUpgradeabilityProxy(
                payable(proxyAddress)
            );

        proxy.upgradeToAndCall(implementation, initParams);
    }

    function _checkNoLiquidity(address asset) internal view {
        DataTypes.ReserveData memory reserveData = pool.getReserveData(asset);

        uint256 availableLiquidity = IERC20Detailed(asset).balanceOf(
            reserveData.aTokenAddress
        );

        require(
            availableLiquidity == 0 && reserveData.currentLiquidityRate == 0,
            Errors.LPC_RESERVE_LIQUIDITY_NOT_0
        );
    }
}
