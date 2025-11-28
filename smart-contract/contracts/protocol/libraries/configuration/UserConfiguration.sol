// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../helpers/Errors.sol";
import "../types/DataTypes.sol";

library UserConfiguration {
    uint256 internal constant BORROWING_MASK =
        0x5555555555555555555555555555555555555555555555555555555555555555;

    function setBorrowing(
        DataTypes.UserConfigurationMap storage self,
        uint256 reserveIndex,
        bool borrowing
    ) internal {
        require(reserveIndex < 128, Errors.UL_INVALID_INDEX);
        self.data =
            (self.data & ~(1 << (reserveIndex * 2))) |
            (uint256(borrowing ? 1 : 0) << (reserveIndex * 2));
    }

    function setUsingAsCollateral(
        DataTypes.UserConfigurationMap storage self,
        uint256 reserveIndex,
        bool usingAsCollateral
    ) internal {
        require(reserveIndex < 128, Errors.UL_INVALID_INDEX);
        self.data =
            (self.data & ~(1 << (reserveIndex * 2 + 1))) |
            (uint256(usingAsCollateral ? 1 : 0) << (reserveIndex * 2 + 1));
    }

    function isUsingAsCollateralOrBorrowing(
        DataTypes.UserConfigurationMap memory self,
        uint256 reserveIndex
    ) internal pure returns (bool) {
        require(reserveIndex < 128, Errors.UL_INVALID_INDEX);
        return (self.data >> (reserveIndex * 2)) & 3 != 0;
    }

    function isBorrowing(
        DataTypes.UserConfigurationMap memory self,
        uint256 reserveIndex
    ) internal pure returns (bool) {
        require(reserveIndex < 128, Errors.UL_INVALID_INDEX);
        return (self.data >> (reserveIndex * 2)) & 1 != 0;
    }

    function isUsingAsCollateral(
        DataTypes.UserConfigurationMap memory self,
        uint256 reserveIndex
    ) internal pure returns (bool) {
        require(reserveIndex < 128, Errors.UL_INVALID_INDEX);
        return (self.data >> (reserveIndex * 2 + 1)) & 1 != 0;
    }

    function isBorrowingAny(
        DataTypes.UserConfigurationMap memory self
    ) internal pure returns (bool) {
        return self.data & BORROWING_MASK != 0;
    }

    function isEmpty(
        DataTypes.UserConfigurationMap memory self
    ) internal pure returns (bool) {
        return self.data == 0;
    }
}
