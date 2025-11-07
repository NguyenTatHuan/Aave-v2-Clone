// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../../openzeppelin/contracts/SafeMath.sol";
import "./WadRayMath.sol";

library MathUtils {
    using SafeMath for uint256;
    using WadRayMath for uint256;

    uint256 internal constant SECONDS_PER_YEAR = 365 days;

    function calculateLinearInterest(
        uint256 rate,
        uint40 lastUpdateTimestamp
    ) internal view returns (uint256) {
        uint256 timeDifference = block.timestamp.sub(
            uint256(lastUpdateTimestamp)
        );
        return
            (rate.mul(timeDifference) / SECONDS_PER_YEAR).add(WadRayMath.ray());
    }

    function calculateCompoundedInterest(
        uint256 rate,
        uint40 lastUpdateTimestamp,
        uint256 currentTimestamp
    ) internal pure returns (uint256) {
        uint256 exp = currentTimestamp.sub(uint256(lastUpdateTimestamp));

        if (exp == 0) {
            return WadRayMath.ray();
        }

        uint256 expMinusOne = exp - 1;

        uint256 expMinusTwo = exp > 2 ? exp - 2 : 0;

        uint256 ratePerSecond = rate / SECONDS_PER_YEAR;

        uint256 basePowerTwo = ratePerSecond.rayMul(ratePerSecond);
        uint256 basePowerThree = basePowerTwo.rayMul(ratePerSecond);

        uint256 secondTerm = exp.mul(expMinusOne).mul(basePowerTwo) / 2;
        uint256 thirdTerm = exp.mul(expMinusOne).mul(expMinusTwo).mul(
            basePowerThree
        ) / 6;

        return
            WadRayMath.ray().add(ratePerSecond.mul(exp)).add(secondTerm).add(
                thirdTerm
            );
    }

    function calculateCompoundedInterest(
        uint256 rate,
        uint40 lastUpdateTimestamp
    ) internal view returns (uint256) {
        return
            calculateCompoundedInterest(
                rate,
                lastUpdateTimestamp,
                block.timestamp
            );
    }
}
