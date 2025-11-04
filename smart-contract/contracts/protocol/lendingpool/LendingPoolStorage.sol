// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../interfaces/ILendingPoolAddressesProvider.sol";
import "../libraries/types/DataTypes.sol";
import "../libraries/configuration/UserConfiguration.sol";
import "../libraries/configuration/ReserveConfiguration.sol";
import "../libraries/logic/ReserveLogic.sol";

contract LendingPoolStorage {
    using ReserveLogic for DataTypes.ReserveData;
    using UserConfiguration for DataTypes.UserConfigurationMap;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    ILendingPoolAddressesProvider internal _addressesProvider;

    mapping(address => DataTypes.ReserveData) internal _reserves;
    mapping(address => DataTypes.UserConfigurationMap) internal _usersConfig;
    mapping(uint256 => address) internal _reservesList;

    uint256 internal _reservesCount;
    bool internal _paused;
    uint256 internal _maxStableRateBorrowSizePercent;
    uint256 internal _flashLoanPremiumTotal;
    uint256 internal _maxNumberOfReserves;
}
