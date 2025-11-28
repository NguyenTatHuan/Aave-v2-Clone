// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ILendingRateOracle {
    function getMarketBorrowRate(address asset) external view returns (uint256);

    function setMarketBorrowRate(address asset, uint256 rate) external;
}
