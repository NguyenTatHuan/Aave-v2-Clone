// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../openzeppelin/contracts/ERC20.sol";

contract MintableDelegationERC20 is ERC20 {
    address public delegatee;

    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals
    ) ERC20(name, symbol) {
        _setupDecimals(decimals);
    }

    function mint(uint256 value) public returns (bool) {
        _mint(msg.sender, value);
        return true;
    }

    function delegate(address delegateeAddress) external {
        delegatee = delegateeAddress;
    }
}
