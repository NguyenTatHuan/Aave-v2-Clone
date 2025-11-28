// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./BaseUniswapAdapter.sol";
import "../openzeppelin/contracts/IERC20.sol";
import "../openzeppelin/contracts/SafeMath.sol";
import "../openzeppelin/contracts/SafeERC20.sol";

contract UniswapLiquiditySwapAdapter is BaseUniswapAdapter {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct PermitParams {
        uint256[] amount;
        uint256[] deadline;
        uint8[] v;
        bytes32[] r;
        bytes32[] s;
    }

    struct SwapParams {
        address[] assetToSwapToList;
        uint256[] minAmountsToReceive;
        bool[] swapAllBalance;
        PermitParams permitParams;
        bool[] useEthPath;
    }

    constructor(
        ILendingPoolAddressesProvider addressesProvider,
        IUniswapV2Router02 uniswapRouter,
        address wethAddress
    ) BaseUniswapAdapter(addressesProvider, uniswapRouter, wethAddress) {}

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        require(
            msg.sender == address(LENDING_POOL),
            "CALLER_MUST_BE_LENDING_POOL"
        );

        SwapParams memory decodedParams = _decodeParams(params);

        require(
            assets.length == decodedParams.assetToSwapToList.length &&
                assets.length == decodedParams.minAmountsToReceive.length &&
                assets.length == decodedParams.swapAllBalance.length &&
                assets.length == decodedParams.permitParams.amount.length &&
                assets.length == decodedParams.permitParams.deadline.length &&
                assets.length == decodedParams.permitParams.v.length &&
                assets.length == decodedParams.permitParams.r.length &&
                assets.length == decodedParams.permitParams.s.length &&
                assets.length == decodedParams.useEthPath.length,
            "INCONSISTENT_PARAMS"
        );

        for (uint256 i = 0; i < assets.length; i++) {
            _swapLiquidity(
                assets[i],
                decodedParams.assetToSwapToList[i],
                amounts[i],
                premiums[i],
                initiator,
                decodedParams.minAmountsToReceive[i],
                decodedParams.swapAllBalance[i],
                PermitSignature(
                    decodedParams.permitParams.amount[i],
                    decodedParams.permitParams.deadline[i],
                    decodedParams.permitParams.v[i],
                    decodedParams.permitParams.r[i],
                    decodedParams.permitParams.s[i]
                ),
                decodedParams.useEthPath[i]
            );
        }

        return true;
    }

    struct SwapAndDepositLocalVars {
        uint256 i;
        uint256 aTokenInitiatorBalance;
        uint256 amountToSwap;
        uint256 receivedAmount;
        address aToken;
    }

    function swapAndDeposit(
        address[] calldata assetToSwapFromList,
        address[] calldata assetToSwapToList,
        uint256[] calldata amountToSwapList,
        uint256[] calldata minAmountsToReceive,
        PermitSignature[] calldata permitParams,
        bool[] calldata useEthPath
    ) external {
        require(
            assetToSwapFromList.length == assetToSwapToList.length &&
                assetToSwapFromList.length == amountToSwapList.length &&
                assetToSwapFromList.length == minAmountsToReceive.length &&
                assetToSwapFromList.length == permitParams.length,
            "INCONSISTENT_PARAMS"
        );

        SwapAndDepositLocalVars memory vars;

        for (vars.i = 0; vars.i < assetToSwapFromList.length; vars.i++) {
            vars.aToken = _getReserveData(assetToSwapFromList[vars.i])
                .aTokenAddress;

            vars.aTokenInitiatorBalance = IERC20(vars.aToken).balanceOf(
                msg.sender
            );
            
            vars.amountToSwap = amountToSwapList[vars.i] >
                vars.aTokenInitiatorBalance
                ? vars.aTokenInitiatorBalance
                : amountToSwapList[vars.i];

            _pullAToken(
                assetToSwapFromList[vars.i],
                vars.aToken,
                msg.sender,
                vars.amountToSwap,
                permitParams[vars.i]
            );

            vars.receivedAmount = _swapExactTokensForTokens(
                assetToSwapFromList[vars.i],
                assetToSwapToList[vars.i],
                vars.amountToSwap,
                minAmountsToReceive[vars.i],
                useEthPath[vars.i]
            );

            IERC20(assetToSwapToList[vars.i]).safeApprove(
                address(LENDING_POOL),
                0
            );

            IERC20(assetToSwapToList[vars.i]).safeApprove(
                address(LENDING_POOL),
                vars.receivedAmount
            );

            LENDING_POOL.deposit(
                assetToSwapToList[vars.i],
                vars.receivedAmount,
                msg.sender,
                0
            );
        }
    }

    struct SwapLiquidityLocalVars {
        address aToken;
        uint256 aTokenInitiatorBalance;
        uint256 amountToSwap;
        uint256 receivedAmount;
        uint256 flashLoanDebt;
        uint256 amountToPull;
    }

    function _swapLiquidity(
        address assetFrom,
        address assetTo,
        uint256 amount,
        uint256 premium,
        address initiator,
        uint256 minAmountToReceive,
        bool swapAllBalance,
        PermitSignature memory permitSignature,
        bool useEthPath
    ) internal {
        SwapLiquidityLocalVars memory vars;

        vars.aToken = _getReserveData(assetFrom).aTokenAddress;

        vars.aTokenInitiatorBalance = IERC20(vars.aToken).balanceOf(initiator);
        vars.amountToSwap = swapAllBalance &&
            vars.aTokenInitiatorBalance.sub(premium) <= amount
            ? vars.aTokenInitiatorBalance.sub(premium)
            : amount;

        vars.receivedAmount = _swapExactTokensForTokens(
            assetFrom,
            assetTo,
            vars.amountToSwap,
            minAmountToReceive,
            useEthPath
        );

        IERC20(assetTo).safeApprove(address(LENDING_POOL), 0);
        IERC20(assetTo).safeApprove(address(LENDING_POOL), vars.receivedAmount);
        LENDING_POOL.deposit(assetTo, vars.receivedAmount, initiator, 0);

        vars.flashLoanDebt = amount.add(premium);
        vars.amountToPull = vars.amountToSwap.add(premium);

        _pullAToken(
            assetFrom,
            vars.aToken,
            initiator,
            vars.amountToPull,
            permitSignature
        );

        IERC20(assetFrom).safeApprove(address(LENDING_POOL), 0);
        IERC20(assetFrom).safeApprove(
            address(LENDING_POOL),
            vars.flashLoanDebt
        );
    }

    function _decodeParams(
        bytes memory params
    ) internal pure returns (SwapParams memory) {
        (
            address[] memory assetToSwapToList,
            uint256[] memory minAmountsToReceive,
            bool[] memory swapAllBalance,
            uint256[] memory permitAmount,
            uint256[] memory deadline,
            uint8[] memory v,
            bytes32[] memory r,
            bytes32[] memory s,
            bool[] memory useEthPath
        ) = abi.decode(
                params,
                (
                    address[],
                    uint256[],
                    bool[],
                    uint256[],
                    uint256[],
                    uint8[],
                    bytes32[],
                    bytes32[],
                    bool[]
                )
            );
        return
            SwapParams(
                assetToSwapToList,
                minAmountsToReceive,
                swapAllBalance,
                PermitParams(permitAmount, deadline, v, r, s),
                useEthPath
            );
    }
}
