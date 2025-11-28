// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../openzeppelin/contracts/SafeMath.sol";
import "../../openzeppelin/contracts/IERC20.sol";
import "../../openzeppelin/contracts/SafeERC20.sol";
import "../interfaces/IFlashLoanReceiver.sol";
import "../../interfaces/ILendingPoolAddressesProvider.sol";
import "../../interfaces/ILendingPool.sol";

abstract contract FlashLoanReceiverBase is IFlashLoanReceiver {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    ILendingPoolAddressesProvider public immutable override ADDRESSES_PROVIDER;
    ILendingPool public immutable override LENDING_POOL;

    constructor(ILendingPoolAddressesProvider provider) {
        ADDRESSES_PROVIDER = provider;
        LENDING_POOL = ILendingPool(provider.getLendingPool());
    }
}
