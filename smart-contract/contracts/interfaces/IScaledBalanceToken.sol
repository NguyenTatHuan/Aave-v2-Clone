// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IScaledBalanceToken {
    function scaledBalanceOf(address user) external view returns (uint256);

    function getScaledUserBalanceAndSupply(
        address user
    ) external view returns (uint256, uint256);

    function scaledTotalSupply() external view returns (uint256);
}
