// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../interfaces/ILendingPool.sol";
import "../../interfaces/IDelegationToken.sol";
import "./AToken.sol";
import "../libraries/helpers/Errors.sol";

contract DelegationAwareAToken is AToken {
    modifier onlyPoolAdmin() {
        require(
            _msgSender() ==
                ILendingPool(_pool).getAddressesProvider().getPoolAdmin(),
            Errors.CALLER_NOT_POOL_ADMIN
        );
        _;
    }

    function delegateUnderlyingTo(address delegatee) external onlyPoolAdmin {
        IDelegationToken(_underlyingAsset).delegate(delegatee);
    }
}
