// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../weth/WETH9.sol";

contract WETH9Mocked is WETH9 {
    function mint(uint256 value) public returns (bool) {
        balanceOf[msg.sender] += value;
        emit Transfer(address(0), msg.sender, value);
        return true;
    }
}
