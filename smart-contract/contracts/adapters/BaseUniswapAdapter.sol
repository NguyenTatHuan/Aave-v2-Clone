// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./IBaseUniswapAdapter.sol";
import "../openzeppelin/contracts/Ownable.sol";
import "../openzeppelin/contracts/SafeMath.sol";
import "../openzeppelin/contracts/SafeERC20.sol";
import "../openzeppelin/contracts/IERC20.sol";
import "../openzeppelin/contracts/IERC20Detailed.sol";
import "../protocol/libraries/math/PercentageMath.sol";
import "../interfaces/IPriceOracleGetter.sol";
import "../interfaces/IUniswapV2Router02.sol";
import "../interfaces/IERC20WithPermit.sol";
import "../flashloan/base/FlashLoanReceiverBase.sol";

abstract contract BaseUniswapAdapter is
    FlashLoanReceiverBase,
    IBaseUniswapAdapter,
    Ownable
{
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using PercentageMath for uint256;

    uint256 public constant override MAX_SLIPPAGE_PERCENT = 3000; // 30%
    uint256 public constant override FLASHLOAN_PREMIUM_TOTAL = 9;
    address public constant override USD_ADDRESS =
        0x10F7Fc1F91Ba351f9C629c5947AD69bD03C05b96;

    address public immutable override WETH_ADDRESS;
    IPriceOracleGetter public immutable override ORACLE;
    IUniswapV2Router02 public immutable override UNISWAP_ROUTER;

    constructor(
        ILendingPoolAddressesProvider addressesProvider,
        IUniswapV2Router02 uniswapRouter,
        address wethAddress
    ) FlashLoanReceiverBase(addressesProvider) {
        ORACLE = IPriceOracleGetter(addressesProvider.getPriceOracle());
        UNISWAP_ROUTER = uniswapRouter;
        WETH_ADDRESS = wethAddress;
    }

    function getAmountsOut(
        uint256 amountIn,
        address reserveIn,
        address reserveOut
    )
        external
        view
        override
        returns (uint256, uint256, uint256, uint256, address[] memory)
    {
        AmountCalc memory results = _getAmountsOutData(
            reserveIn,
            reserveOut,
            amountIn
        );

        return (
            results.calculatedAmount,
            results.relativePrice,
            results.amountInUsd,
            results.amountOutUsd,
            results.path
        );
    }

    function getAmountsIn(
        uint256 amountOut,
        address reserveIn,
        address reserveOut
    )
        external
        view
        override
        returns (uint256, uint256, uint256, uint256, address[] memory)
    {
        AmountCalc memory results = _getAmountsInData(
            reserveIn,
            reserveOut,
            amountOut
        );

        return (
            results.calculatedAmount,
            results.relativePrice,
            results.amountInUsd,
            results.amountOutUsd,
            results.path
        );
    }

    function _swapExactTokensForTokens(
        address assetToSwapFrom,
        address assetToSwapTo,
        uint256 amountToSwap,
        uint256 minAmountOut,
        bool useEthPath
    ) internal returns (uint256) {
        uint256 fromAssetDecimals = _getDecimals(assetToSwapFrom);
        uint256 toAssetDecimals = _getDecimals(assetToSwapTo);

        uint256 fromAssetPrice = _getPrice(assetToSwapFrom);
        uint256 toAssetPrice = _getPrice(assetToSwapTo);

        uint256 expectedMinAmountOut = amountToSwap
            .mul(fromAssetPrice.mul(10 ** toAssetDecimals))
            .div(toAssetPrice.mul(10 ** fromAssetDecimals))
            .percentMul(
                PercentageMath.PERCENTAGE_FACTOR.sub(MAX_SLIPPAGE_PERCENT)
            );

        require(
            expectedMinAmountOut < minAmountOut,
            "minAmountOut exceed max slippage"
        );

        IERC20(assetToSwapFrom).safeApprove(address(UNISWAP_ROUTER), 0);
        IERC20(assetToSwapFrom).safeApprove(
            address(UNISWAP_ROUTER),
            amountToSwap
        );

        address[] memory path;
        if (useEthPath) {
            path = new address[](3);
            path[0] = assetToSwapFrom;
            path[1] = WETH_ADDRESS;
            path[2] = assetToSwapTo;
        } else {
            path = new address[](2);
            path[0] = assetToSwapFrom;
            path[1] = assetToSwapTo;
        }

        uint256[] memory amounts = UNISWAP_ROUTER.swapExactTokensForTokens(
            amountToSwap,
            minAmountOut,
            path,
            address(this),
            block.timestamp
        );

        emit Swapped(
            assetToSwapFrom,
            assetToSwapTo,
            amounts[0],
            amounts[amounts.length - 1]
        );

        return amounts[amounts.length - 1];
    }

    function _swapTokensForExactTokens(
        address assetToSwapFrom,
        address assetToSwapTo,
        uint256 maxAmountToSwap,
        uint256 amountToReceive,
        bool useEthPath
    ) internal returns (uint256) {
        uint256 fromAssetDecimals = _getDecimals(assetToSwapFrom);
        uint256 toAssetDecimals = _getDecimals(assetToSwapTo);

        uint256 fromAssetPrice = _getPrice(assetToSwapFrom);
        uint256 toAssetPrice = _getPrice(assetToSwapTo);

        uint256 expectedMaxAmountToSwap = amountToReceive
            .mul(toAssetPrice.mul(10 ** fromAssetDecimals))
            .div(fromAssetPrice.mul(10 ** toAssetDecimals))
            .percentMul(
                PercentageMath.PERCENTAGE_FACTOR.add(MAX_SLIPPAGE_PERCENT)
            );

        require(
            maxAmountToSwap < expectedMaxAmountToSwap,
            "maxAmountToSwap exceed max slippage"
        );

        IERC20(assetToSwapFrom).safeApprove(address(UNISWAP_ROUTER), 0);
        IERC20(assetToSwapFrom).safeApprove(
            address(UNISWAP_ROUTER),
            maxAmountToSwap
        );

        address[] memory path;
        if (useEthPath) {
            path = new address[](3);
            path[0] = assetToSwapFrom;
            path[1] = WETH_ADDRESS;
            path[2] = assetToSwapTo;
        } else {
            path = new address[](2);
            path[0] = assetToSwapFrom;
            path[1] = assetToSwapTo;
        }

        uint256[] memory amounts = UNISWAP_ROUTER.swapTokensForExactTokens(
            amountToReceive,
            maxAmountToSwap,
            path,
            address(this),
            block.timestamp
        );

        emit Swapped(
            assetToSwapFrom,
            assetToSwapTo,
            amounts[0],
            amounts[amounts.length - 1]
        );

        return amounts[0];
    }

    function _getAmountsOutData(
        address reserveIn,
        address reserveOut,
        uint256 amountIn
    ) internal view returns (AmountCalc memory) {
        uint256 finalAmountIn = amountIn.sub(
            amountIn.mul(FLASHLOAN_PREMIUM_TOTAL).div(10000)
        );

        if (reserveIn == reserveOut) {
            uint256 reserveDecimals = _getDecimals(reserveIn);
            address[] memory path = new address[](1);
            path[0] = reserveIn;

            return
                AmountCalc(
                    finalAmountIn,
                    finalAmountIn.mul(10 ** 18).div(amountIn),
                    _calcUsdValue(reserveIn, amountIn, reserveDecimals),
                    _calcUsdValue(reserveIn, finalAmountIn, reserveDecimals),
                    path
                );
        }

        address[] memory simplePath = new address[](2);
        simplePath[0] = reserveIn;
        simplePath[1] = reserveOut;

        uint256[] memory amountsWithoutWeth;
        uint256[] memory amountsWithWeth;
        address[] memory pathWithWeth = new address[](3);

        if (reserveIn != WETH_ADDRESS && reserveOut != WETH_ADDRESS) {
            pathWithWeth[0] = reserveIn;
            pathWithWeth[1] = WETH_ADDRESS;
            pathWithWeth[2] = reserveOut;

            try
                UNISWAP_ROUTER.getAmountsOut(finalAmountIn, pathWithWeth)
            returns (uint256[] memory resultsWithWeth) {
                amountsWithWeth = resultsWithWeth;
            } catch {
                amountsWithWeth = new uint256[](3);
            }
        } else {
            amountsWithWeth = new uint256[](3);
        }

        uint256 bestAmountOut;
        try UNISWAP_ROUTER.getAmountsOut(finalAmountIn, simplePath) returns (
            uint256[] memory resultAmounts
        ) {
            amountsWithoutWeth = resultAmounts;

            bestAmountOut = (amountsWithWeth[2] > amountsWithoutWeth[1])
                ? amountsWithWeth[2]
                : amountsWithoutWeth[1];
        } catch {
            amountsWithoutWeth = new uint256[](2);
            bestAmountOut = amountsWithWeth[2];
        }
        uint256 reserveInDecimals = _getDecimals(reserveIn);
        uint256 reserveOutDecimals = _getDecimals(reserveOut);

        uint256 outPerInPrice = finalAmountIn
            .mul(10 ** 18)
            .mul(10 ** reserveOutDecimals)
            .div(bestAmountOut.mul(10 ** reserveInDecimals));

        return
            AmountCalc(
                bestAmountOut,
                outPerInPrice,
                _calcUsdValue(reserveIn, amountIn, reserveInDecimals),
                _calcUsdValue(reserveOut, bestAmountOut, reserveOutDecimals),
                (bestAmountOut == 0)
                    ? new address[](2)
                    : (bestAmountOut == amountsWithoutWeth[1])
                        ? simplePath
                        : pathWithWeth
            );
    }

    function _getAmountsInData(
        address reserveIn,
        address reserveOut,
        uint256 amountOut
    ) internal view returns (AmountCalc memory) {
        if (reserveIn == reserveOut) {
            uint256 amountIn = amountOut.add(
                amountOut.mul(FLASHLOAN_PREMIUM_TOTAL).div(10000)
            );

            uint256 reserveDecimals = _getDecimals(reserveIn);
            address[] memory singlePath = new address[](1);
            singlePath[0] = reserveIn;

            return
                AmountCalc(
                    amountIn,
                    amountOut.mul(10 ** 18).div(amountIn),
                    _calcUsdValue(reserveIn, amountIn, reserveDecimals),
                    _calcUsdValue(reserveIn, amountOut, reserveDecimals),
                    singlePath
                );
        }

        (
            uint256[] memory amounts,
            address[] memory path
        ) = _getAmountsInAndPath(reserveIn, reserveOut, amountOut);

        uint256 finalAmountIn = amounts[0].add(
            amounts[0].mul(FLASHLOAN_PREMIUM_TOTAL).div(10000)
        );

        uint256 reserveInDecimals = _getDecimals(reserveIn);
        uint256 reserveOutDecimals = _getDecimals(reserveOut);

        uint256 inPerOutPrice = amountOut
            .mul(10 ** 18)
            .mul(10 ** reserveInDecimals)
            .div(finalAmountIn.mul(10 ** reserveOutDecimals));

        return
            AmountCalc(
                finalAmountIn,
                inPerOutPrice,
                _calcUsdValue(reserveIn, finalAmountIn, reserveInDecimals),
                _calcUsdValue(reserveOut, amountOut, reserveOutDecimals),
                path
            );
    }

    function _getAmountsInAndPath(
        address reserveIn,
        address reserveOut,
        uint256 amountOut
    ) internal view returns (uint256[] memory, address[] memory) {
        address[] memory simplePath = new address[](2);
        simplePath[0] = reserveIn;
        simplePath[1] = reserveOut;

        uint256[] memory amountsWithoutWeth;
        uint256[] memory amountsWithWeth;
        address[] memory pathWithWeth = new address[](3);

        if (reserveIn != WETH_ADDRESS && reserveOut != WETH_ADDRESS) {
            pathWithWeth[0] = reserveIn;
            pathWithWeth[1] = WETH_ADDRESS;
            pathWithWeth[2] = reserveOut;

            try UNISWAP_ROUTER.getAmountsIn(amountOut, pathWithWeth) returns (
                uint256[] memory resultsWithWeth
            ) {
                amountsWithWeth = resultsWithWeth;
            } catch {
                amountsWithWeth = new uint256[](3);
            }
        } else {
            amountsWithWeth = new uint256[](3);
        }

        try UNISWAP_ROUTER.getAmountsIn(amountOut, simplePath) returns (
            uint256[] memory resultAmounts
        ) {
            amountsWithoutWeth = resultAmounts;

            return
                (amountsWithWeth[0] < amountsWithoutWeth[0] &&
                    amountsWithWeth[0] != 0)
                    ? (amountsWithWeth, pathWithWeth)
                    : (amountsWithoutWeth, simplePath);
        } catch {
            return (amountsWithWeth, pathWithWeth);
        }
    }

    function _getPrice(address asset) internal view returns (uint256) {
        return ORACLE.getAssetPrice(asset);
    }

    function _getDecimals(address asset) internal view returns (uint256) {
        return IERC20Detailed(asset).decimals();
    }

    function _getReserveData(
        address asset
    ) internal view returns (DataTypes.ReserveData memory) {
        return LENDING_POOL.getReserveData(asset);
    }

    function _pullAToken(
        address reserve,
        address reserveAToken,
        address user,
        uint256 amount,
        PermitSignature memory permitSignature
    ) internal {
        if (_usePermit(permitSignature)) {
            IERC20WithPermit(reserveAToken).permit(
                user,
                address(this),
                permitSignature.amount,
                permitSignature.deadline,
                permitSignature.v,
                permitSignature.r,
                permitSignature.s
            );
        }

        IERC20(reserveAToken).safeTransferFrom(user, address(this), amount);

        LENDING_POOL.withdraw(reserve, amount, address(this));
    }

    function _usePermit(
        PermitSignature memory signature
    ) internal pure returns (bool) {
        return
            !(uint256(signature.deadline) == uint256(signature.v) &&
                uint256(signature.deadline) == 0);
    }

    function _calcUsdValue(
        address reserve,
        uint256 amount,
        uint256 decimals
    ) internal view returns (uint256) {
        uint256 ethUsdPrice = _getPrice(USD_ADDRESS);
        uint256 reservePrice = _getPrice(reserve);

        return
            amount.mul(reservePrice).div(10 ** decimals).mul(ethUsdPrice).div(
                10 ** 18
            );
    }

    function rescueTokens(IERC20 token) external onlyOwner {
        token.transfer(owner(), token.balanceOf(address(this)));
    }
}
