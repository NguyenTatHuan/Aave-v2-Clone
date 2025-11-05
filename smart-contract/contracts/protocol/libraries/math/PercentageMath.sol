// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../helpers/AaveErrors.sol";

library PercentageMath {
    uint256 constant PERCENTAGE_FACTOR = 1e4;
    uint256 constant HALF_PERCENT = PERCENTAGE_FACTOR / 2;

    function percentMul(
        uint256 value,
        uint256 percentage
    ) internal pure returns (uint256) {
        if (value == 0 || percentage == 0) {
            return 0;
        }

        require(
            value <= (type(uint256).max - HALF_PERCENT) / percentage,
            AaveErrors.MATH_MULTIPLICATION_OVERFLOW
        );

        return (value * percentage + HALF_PERCENT) / PERCENTAGE_FACTOR;
    }

    function percentDiv(
        uint256 value,
        uint256 percentage
    ) internal pure returns (uint256) {
        require(percentage != 0, AaveErrors.MATH_DIVISION_BY_ZERO);
        uint256 halfPercentage = percentage / 2;

        require(
            value <= (type(uint256).max - halfPercentage) / PERCENTAGE_FACTOR,
            AaveErrors.MATH_MULTIPLICATION_OVERFLOW
        );

        return (value * PERCENTAGE_FACTOR + halfPercentage) / percentage;
    }
}
