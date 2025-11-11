// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./BaseImmutableAdminUpgradeabilityProxy.sol";

contract InitializableImmutableAdminUpgradeabilityProxy is
    BaseImmutableAdminUpgradeabilityProxy
{
    constructor(address admin) BaseImmutableAdminUpgradeabilityProxy(admin) {}

    function initialize(address _logic, bytes memory _data) public payable {
        require(_implementation() == address(0));
        assert(
            IMPLEMENTATION_SLOT ==
                bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1)
        );
        _setImplementation(_logic);
        if (_data.length > 0) {
            (bool success, ) = _logic.delegatecall(_data);
            require(success);
        }
    }

    function _willFallback() internal override {
        super._willFallback();
    }
}
