// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../helpers/Errors.sol";

library WadRayMath {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant halfWAD = WAD / 2;

    uint256 internal constant RAY = 1e27;
    uint256 internal constant halfRAY = RAY / 2;

    uint256 internal constant WAD_RAY_RATIO = 1e9;

    function ray() internal pure returns (uint256) {
        return RAY;
    }

    function wad() internal pure returns (uint256) {
        return WAD;
    }

    function halfRay() internal pure returns (uint256) {
        return halfRAY;
    }

    function halfWad() internal pure returns (uint256) {
        return halfWAD;
    }

    function wadMul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) {
            return 0;
        }

        require(
            a <= (type(uint256).max - halfWAD) / b,
            Errors.MATH_MULTIPLICATION_OVERFLOW
        );

        return (a * b + halfWAD) / WAD;
    }

    function wadDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0, Errors.MATH_DIVISION_BY_ZERO);
        uint256 halfB = b / 2;

        require(
            a <= (type(uint256).max - halfB) / WAD,
            Errors.MATH_MULTIPLICATION_OVERFLOW
        );

        return (a * WAD + halfB) / b;
    }

    function rayMul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) {
            return 0;
        }

        require(
            a <= (type(uint256).max - halfRAY) / b,
            Errors.MATH_MULTIPLICATION_OVERFLOW
        );

        return (a * b + halfRAY) / RAY;
    }

    function rayDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0, Errors.MATH_DIVISION_BY_ZERO);
        uint256 halfB = b / 2;

        require(
            a <= (type(uint256).max - halfB) / RAY,
            Errors.MATH_MULTIPLICATION_OVERFLOW
        );

        return (a * RAY + halfB) / b;
    }

    function rayToWad(uint256 a) internal pure returns (uint256) {
        uint256 halfRatio = WAD_RAY_RATIO / 2;
        uint256 result = halfRatio + a;
        require(result >= halfRatio, Errors.MATH_ADDITION_OVERFLOW);

        return result / WAD_RAY_RATIO;
    }

    function wadToRay(uint256 a) internal pure returns (uint256) {
        uint256 result = a * WAD_RAY_RATIO;
        require(
            result / WAD_RAY_RATIO == a,
            Errors.MATH_MULTIPLICATION_OVERFLOW
        );
        return result;
    }
}
