// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./ILendingPool.sol";
import "./IAaveIncentivesController.sol";

interface IInitializableDebtToken {
    event Initialized(
        address indexed underlyingAsset,
        address indexed pool,
        address incentivesController,
        uint8 debtTokenDecimals,
        string debtTokenName,
        string debtTokenSymbol,
        bytes params
    );

    function initialize(
        ILendingPool pool,
        address underlyingAsset,
        IAaveIncentivesController incentivesController,
        uint8 debtTokenDecimals,
        string memory debtTokenName,
        string memory debtTokenSymbol,
        bytes calldata params
    ) external;
}
