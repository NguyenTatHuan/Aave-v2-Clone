// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ILendingPoolCollateralManager {
    event LiquidationCall(
        address indexed collateral,
        address indexed principal,
        address indexed user,
        uint256 debtToCover,
        uint256 liquidatedCollateralAmount,
        address liquidator,
        bool receiveAToken
    );

    event ReserveUsedAsCollateralDisabled(
        address indexed reserve,
        address indexed user
    );

    event ReserveUsedAsCollateralEnabled(
        address indexed reserve,
        address indexed user
    );

    function liquidationCall(
        address collateral,
        address principal,
        address user,
        uint256 debtToCover,
        bool receiveAToken
    ) external returns (uint256, string memory);
}
