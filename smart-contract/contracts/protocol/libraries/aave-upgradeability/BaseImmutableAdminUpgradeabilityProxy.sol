// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../../openzeppelin/upgradeability/BaseUpgradeabilityProxy.sol";

contract BaseImmutableAdminUpgradeabilityProxy is BaseUpgradeabilityProxy {
    address immutable ADMIN;

    constructor(address _admin) {
        ADMIN = _admin;
    }

    modifier ifAdmin() {
        if (msg.sender == ADMIN) {
            _;
        } else {
            _fallback();
        }
    }

    function admin() external ifAdmin returns (address) {
        return ADMIN;
    }

    function implementation() external ifAdmin returns (address) {
        return _implementation();
    }

    function upgradeTo(address newImplementation) external ifAdmin {
        _upgradeTo(newImplementation);
    }

    function upgradeToAndCall(
        address newImplementation,
        bytes calldata data
    ) external payable ifAdmin {
        _upgradeTo(newImplementation);
        (bool success, ) = newImplementation.delegatecall(data);
        require(success, "Upgrade call failed");
    }

    function _willFallback() internal virtual override {
        require(
            msg.sender != ADMIN,
            "Cannot call fallback function from the proxy admin"
        );
        super._willFallback();
    }

    receive() external payable {
        _fallback();
    }
}
