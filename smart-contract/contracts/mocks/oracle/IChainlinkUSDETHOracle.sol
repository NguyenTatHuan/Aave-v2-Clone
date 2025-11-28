// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IChainlinkUSDETHOracle {
    event AnswerUpdated(int256 indexed current, uint256 indexed answerId);
}
