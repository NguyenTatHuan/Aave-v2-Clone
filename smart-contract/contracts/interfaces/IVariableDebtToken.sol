// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./IScaledBalanceToken.sol";
import "./IInitializableDebtToken.sol";
import "./IAaveIncentivesController.sol";

interface IVariableDebtToken is IScaledBalanceToken, IInitializableDebtToken {
    event Mint(
        address indexed from,
        address indexed onBehalfOf,
        uint256 value,
        uint256 index
    );

    function mint(
        address user,
        address onBehalfOf,
        uint256 amount,
        uint256 index
    ) external returns (bool);

    event Burn(address indexed user, uint256 amount, uint256 index);

    function burn(address user, uint256 amount, uint256 index) external;

    function getIncentivesController()
        external
        view
        returns (IAaveIncentivesController);
}
