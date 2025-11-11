// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./Proxy.sol";
import "../contracts/Address.sol";

contract BaseUpgradeabilityProxy is Proxy {
    event Upgraded(address indexed implementation);

    bytes32 internal constant IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function _implementation() internal view override returns (address impl) {
        assembly {
            impl := sload(IMPLEMENTATION_SLOT)
        }
    }

    function _upgradeTo(address newImplementation) internal {
        _setImplementation(newImplementation);
        emit Upgraded(newImplementation);
    }

    function _setImplementation(address newImplementation) internal {
        require(
            Address.isContract(newImplementation),
            "Cannot set a proxy implementation to a non-contract address"
        );

        assembly {
            sstore(IMPLEMENTATION_SLOT, newImplementation)
        }
    }
}
