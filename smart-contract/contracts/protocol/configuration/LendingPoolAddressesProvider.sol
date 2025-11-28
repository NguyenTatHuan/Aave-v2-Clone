// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../openzeppelin/contracts/Ownable.sol";
import "../../interfaces/ILendingPoolAddressesProvider.sol";
import "../libraries/aave-upgradeability/InitializableImmutableAdminUpgradeabilityProxy.sol";

contract LendingPoolAddressesProvider is
    ILendingPoolAddressesProvider,
    Ownable
{
    string private _marketId;
    mapping(bytes32 => address) private _addresses;

    bytes32 private constant LENDING_POOL = "LENDING_POOL";
    bytes32 private constant LENDING_POOL_CONFIGURATOR =
        "LENDING_POOL_CONFIGURATOR";
    bytes32 private constant POOL_ADMIN = "POOL_ADMIN";
    bytes32 private constant EMERGENCY_ADMIN = "EMERGENCY_ADMIN";
    bytes32 private constant LENDING_POOL_COLLATERAL_MANAGER =
        "COLLATERAL_MANAGER";
    bytes32 private constant PRICE_ORACLE = "PRICE_ORACLE";
    bytes32 private constant LENDING_RATE_ORACLE = "LENDING_RATE_ORACLE";

    constructor(string memory marketId) {
        _setMarketId(marketId);
    }

    function getMarketId() external view override returns (string memory) {
        return _marketId;
    }

    function setMarketId(string memory marketId) external override onlyOwner {
        _setMarketId(marketId);
    }

    function setAddressAsProxy(
        bytes32 id,
        address implementationAddress
    ) external override onlyOwner {
        _updateImpl(id, implementationAddress);
        emit AddressSet(id, implementationAddress, true);
    }

    function setAddress(
        bytes32 id,
        address newAddress
    ) external override onlyOwner {
        _addresses[id] = newAddress;
        emit AddressSet(id, newAddress, false);
    }

    function getAddress(bytes32 id) public view override returns (address) {
        return _addresses[id];
    }

    function getLendingPool() external view override returns (address) {
        return getAddress(LENDING_POOL);
    }

    function setLendingPoolImpl(address pool) external override onlyOwner {
        _updateImpl(LENDING_POOL, pool);
        emit LendingPoolUpdated(pool);
    }

    function getLendingPoolConfigurator()
        external
        view
        override
        returns (address)
    {
        return getAddress(LENDING_POOL_CONFIGURATOR);
    }

    function setLendingPoolConfiguratorImpl(
        address configurator
    ) external override onlyOwner {
        _updateImpl(LENDING_POOL_CONFIGURATOR, configurator);
        emit LendingPoolConfiguratorUpdated(configurator);
    }

    function getLendingPoolCollateralManager()
        external
        view
        override
        returns (address)
    {
        return getAddress(LENDING_POOL_COLLATERAL_MANAGER);
    }

    function setLendingPoolCollateralManager(
        address manager
    ) external override onlyOwner {
        _addresses[LENDING_POOL_COLLATERAL_MANAGER] = manager;
        emit LendingPoolCollateralManagerUpdated(manager);
    }

    function getPoolAdmin() external view override returns (address) {
        return getAddress(POOL_ADMIN);
    }

    function setPoolAdmin(address admin) external override onlyOwner {
        _addresses[POOL_ADMIN] = admin;
        emit ConfigurationAdminUpdated(admin);
    }

    function getEmergencyAdmin() external view override returns (address) {
        return getAddress(EMERGENCY_ADMIN);
    }

    function setEmergencyAdmin(
        address emergencyAdmin
    ) external override onlyOwner {
        _addresses[EMERGENCY_ADMIN] = emergencyAdmin;
        emit EmergencyAdminUpdated(emergencyAdmin);
    }

    function getPriceOracle() external view override returns (address) {
        return getAddress(PRICE_ORACLE);
    }

    function setPriceOracle(address priceOracle) external override onlyOwner {
        _addresses[PRICE_ORACLE] = priceOracle;
        emit PriceOracleUpdated(priceOracle);
    }

    function getLendingRateOracle() external view override returns (address) {
        return getAddress(LENDING_RATE_ORACLE);
    }

    function setLendingRateOracle(
        address lendingRateOracle
    ) external override onlyOwner {
        _addresses[LENDING_RATE_ORACLE] = lendingRateOracle;
        emit LendingRateOracleUpdated(lendingRateOracle);
    }

    function _updateImpl(bytes32 id, address newAddress) internal {
        address payable proxyAddress = payable(_addresses[id]);

        InitializableImmutableAdminUpgradeabilityProxy proxy = InitializableImmutableAdminUpgradeabilityProxy(
                proxyAddress
            );
        bytes memory params = abi.encodeWithSignature(
            "initialize(address)",
            address(this)
        );

        if (proxyAddress == address(0)) {
            proxy = new InitializableImmutableAdminUpgradeabilityProxy(
                address(this)
            );
            proxy.initialize(newAddress, params);
            _addresses[id] = address(proxy);
            emit ProxyCreated(id, address(proxy));
        } else {
            proxy.upgradeToAndCall(newAddress, params);
        }
    }

    function _setMarketId(string memory marketId) internal {
        _marketId = marketId;
        emit MarketIdSet(marketId);
    }
}
