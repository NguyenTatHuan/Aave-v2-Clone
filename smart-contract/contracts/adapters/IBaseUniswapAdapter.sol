// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../interfaces/IPriceOracleGetter.sol";
import "../interfaces/IUniswapV2Router02.sol";

interface IBaseUniswapAdapter {
    event Swapped(
        address fromAsset,
        address toAsset,
        uint256 fromAmount,
        uint256 receivedAmount
    );

    struct PermitSignature {
        uint256 amount;
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    struct AmountCalc {
        uint256 calculatedAmount;
        uint256 relativePrice;
        uint256 amountInUsd;
        uint256 amountOutUsd;
        address[] path;
    }

    function WETH_ADDRESS() external returns (address);

    function MAX_SLIPPAGE_PERCENT() external returns (uint256);

    function FLASHLOAN_PREMIUM_TOTAL() external returns (uint256);

    function USD_ADDRESS() external returns (address);

    function ORACLE() external returns (IPriceOracleGetter);

    function UNISWAP_ROUTER() external returns (IUniswapV2Router02);

    function getAmountsOut(
        uint256 amountIn,
        address reserveIn,
        address reserveOut
    )
        external
        view
        returns (uint256, uint256, uint256, uint256, address[] memory);

    function getAmountsIn(
        uint256 amountOut,
        address reserveIn,
        address reserveOut
    )
        external
        view
        returns (uint256, uint256, uint256, uint256, address[] memory);
}
