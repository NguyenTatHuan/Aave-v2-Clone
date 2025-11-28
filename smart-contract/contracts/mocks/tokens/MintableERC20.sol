// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../openzeppelin/contracts/ERC20.sol";

contract MintableERC20 is ERC20 {
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals
    ) ERC20(name, symbol) {
        _setupDecimals(decimals);
    }

    function mint(uint256 value) public returns (bool) {
        _mint(_msgSender(), value);
        return true;
    }
}
