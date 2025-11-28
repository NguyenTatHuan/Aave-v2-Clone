// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./BaseParaSwapAdapter.sol";
import "../protocol/libraries/math/PercentageMath.sol";
import "../interfaces/IParaSwapAugustus.sol";
import "../interfaces/IParaSwapAugustusRegistry.sol";
import "../interfaces/ILendingPoolAddressesProvider.sol";
import "../openzeppelin/contracts/SafeMath.sol";
import "../openzeppelin/contracts/IERC20.sol";
import "../openzeppelin/contracts/SafeERC20.sol";

abstract contract BaseParaSwapSellAdapter is BaseParaSwapAdapter {
    using PercentageMath for uint256;
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IParaSwapAugustusRegistry public immutable AUGUSTUS_REGISTRY;

    constructor(
        ILendingPoolAddressesProvider addressesProvider,
        IParaSwapAugustusRegistry augustusRegistry
    ) BaseParaSwapAdapter(addressesProvider) {
        require(!augustusRegistry.isValidAugustus(address(0)));
        AUGUSTUS_REGISTRY = augustusRegistry;
    }

    function _sellOnParaSwap(
        uint256 fromAmountOffset,
        bytes memory swapCalldata,
        IParaSwapAugustus augustus,
        IERC20Detailed assetToSwapFrom,
        IERC20Detailed assetToSwapTo,
        uint256 amountToSwap,
        uint256 minAmountToReceive
    ) internal returns (uint256 amountReceived) {
        require(
            AUGUSTUS_REGISTRY.isValidAugustus(address(augustus)),
            "INVALID_AUGUSTUS"
        );

        {
            uint256 fromAssetDecimals = _getDecimals(assetToSwapFrom);
            uint256 toAssetDecimals = _getDecimals(assetToSwapTo);

            uint256 fromAssetPrice = _getPrice(address(assetToSwapFrom));
            uint256 toAssetPrice = _getPrice(address(assetToSwapTo));

            uint256 expectedMinAmountOut = amountToSwap
                .mul(fromAssetPrice.mul(10 ** toAssetDecimals))
                .div(toAssetPrice.mul(10 ** fromAssetDecimals))
                .percentMul(
                    PercentageMath.PERCENTAGE_FACTOR - MAX_SLIPPAGE_PERCENT
                );

            require(
                expectedMinAmountOut <= minAmountToReceive,
                "MIN_AMOUNT_EXCEEDS_MAX_SLIPPAGE"
            );
        }

        uint256 balanceBeforeAssetFrom = assetToSwapFrom.balanceOf(
            address(this)
        );

        require(
            balanceBeforeAssetFrom >= amountToSwap,
            "INSUFFICIENT_BALANCE_BEFORE_SWAP"
        );

        uint256 balanceBeforeAssetTo = assetToSwapTo.balanceOf(address(this));

        address tokenTransferProxy = augustus.getTokenTransferProxy();
        IERC20(address(assetToSwapFrom)).safeApprove(tokenTransferProxy, 0);
        IERC20(address(assetToSwapFrom)).safeApprove(
            tokenTransferProxy,
            amountToSwap
        );

        if (fromAmountOffset != 0) {
            require(
                fromAmountOffset >= 4 &&
                    fromAmountOffset <= swapCalldata.length.sub(32),
                "FROM_AMOUNT_OFFSET_OUT_OF_RANGE"
            );

            assembly {
                mstore(
                    add(swapCalldata, add(fromAmountOffset, 32)),
                    amountToSwap
                )
            }
        }

        (bool success, ) = address(augustus).call(swapCalldata);
        if (!success) {
            assembly {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
        }

        require(
            assetToSwapFrom.balanceOf(address(this)) ==
                balanceBeforeAssetFrom - amountToSwap,
            "WRONG_BALANCE_AFTER_SWAP"
        );

        amountReceived = assetToSwapTo.balanceOf(address(this)).sub(
            balanceBeforeAssetTo
        );

        require(
            amountReceived >= minAmountToReceive,
            "INSUFFICIENT_AMOUNT_RECEIVED"
        );

        emit Swapped(
            address(assetToSwapFrom),
            address(assetToSwapTo),
            amountToSwap,
            amountReceived
        );
    }
}
