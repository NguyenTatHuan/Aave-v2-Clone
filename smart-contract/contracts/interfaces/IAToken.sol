// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../openzeppelin/contracts/IERC20.sol";
import "./IScaledBalanceToken.sol";
import "./IInitializableAToken.sol";
import "./IAaveIncentivesController.sol";

interface IAToken is IERC20, IScaledBalanceToken, IInitializableAToken {
    event Mint(address indexed from, uint256 value, uint256 index);

    function mint(
        address user,
        uint256 amount,
        uint256 index
    ) external returns (bool);

    event Burn(
        address indexed from,
        address indexed target,
        uint256 value,
        uint256 index
    );

    event BalanceTransfer(
        address indexed from,
        address indexed to,
        uint256 value,
        uint256 index
    );

    function burn(
        address user,
        address receiverOfUnderlying,
        uint256 amount,
        uint256 index
    ) external;

    function mintToTreasury(uint256 amount, uint256 index) external;

    function transferOnLiquidation(
        address from,
        address to,
        uint256 value
    ) external;

    function transferUnderlyingTo(
        address user,
        uint256 amount
    ) external returns (uint256);

    function handleRepayment(address user, uint256 amount) external;

    function getIncentivesController()
        external
        view
        returns (IAaveIncentivesController);

    function UNDERLYING_ASSET_ADDRESS() external view returns (address);
}
