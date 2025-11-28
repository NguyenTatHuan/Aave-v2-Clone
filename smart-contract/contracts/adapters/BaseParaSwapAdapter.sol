// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../openzeppelin/contracts/Ownable.sol";
import "../openzeppelin/contracts/SafeMath.sol";
import "../openzeppelin/contracts/SafeERC20.sol";
import "../openzeppelin/contracts/IERC20.sol";
import "../openzeppelin/contracts/IERC20Detailed.sol";
import "../interfaces/IERC20WithPermit.sol";
import "../interfaces/IPriceOracleGetter.sol";
import "../interfaces/ILendingPoolAddressesProvider.sol";
import "../flashloan/base/FlashLoanReceiverBase.sol";

abstract contract BaseParaSwapAdapter is FlashLoanReceiverBase, Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC20Detailed;
    using SafeERC20 for IERC20WithPermit;

    struct PermitSignature {
        uint256 amount;
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    uint256 public constant MAX_SLIPPAGE_PERCENT = 3000; // 30%

    IPriceOracleGetter public immutable ORACLE;

    event Swapped(
        address indexed fromAsset,
        address indexed toAsset,
        uint256 fromAmount,
        uint256 receivedAmount
    );

    constructor(
        ILendingPoolAddressesProvider addressesProvider
    ) FlashLoanReceiverBase(addressesProvider) {
        ORACLE = IPriceOracleGetter(addressesProvider.getPriceOracle());
    }

    function _getPrice(address asset) internal view returns (uint256) {
        return ORACLE.getAssetPrice(asset);
    }

    function _getDecimals(IERC20Detailed asset) internal view returns (uint8) {
        uint8 decimals = asset.decimals();
        require(decimals <= 77, "TOO_MANY_DECIMALS_ON_TOKEN");
        return decimals;
    }

    function _getReserveData(
        address asset
    ) internal view returns (DataTypes.ReserveData memory) {
        return LENDING_POOL.getReserveData(asset);
    }

    function _pullATokenAndWithdraw(
        address reserve,
        IERC20WithPermit reserveAToken,
        address user,
        uint256 amount,
        PermitSignature memory permitSignature
    ) internal {
        if (permitSignature.deadline != 0) {
            reserveAToken.permit(
                user,
                address(this),
                permitSignature.amount,
                permitSignature.deadline,
                permitSignature.v,
                permitSignature.r,
                permitSignature.s
            );
        }

        reserveAToken.safeTransferFrom(user, address(this), amount);

        require(
            LENDING_POOL.withdraw(reserve, amount, address(this)) == amount,
            "UNEXPECTED_AMOUNT_WITHDRAWN"
        );
    }

    function rescueTokens(IERC20 token) external onlyOwner {
        token.safeTransfer(owner(), token.balanceOf(address(this)));
    }
}
