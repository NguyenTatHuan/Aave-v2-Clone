// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../../openzeppelin/contracts/IERC20.sol";
import "../types/DataTypes.sol";

library Helpers {
    function getUserCurrentDebt(
        address user,
        DataTypes.ReserveData storage reserve
    ) internal view returns (uint256, uint256) {
        return (
            IERC20(reserve.stableDebtTokenAddress).balanceOf(user),
            IERC20(reserve.variableDebtTokenAddress).balanceOf(user)
        );
    }

    function getUserCurrentDebtMemory(
        address user,
        DataTypes.ReserveData memory reserve
    ) internal view returns (uint256, uint256) {
        return (
            IERC20(reserve.stableDebtTokenAddress).balanceOf(user),
            IERC20(reserve.variableDebtTokenAddress).balanceOf(user)
        );
    }
}
