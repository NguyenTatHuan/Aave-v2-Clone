// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../interfaces/ILendingPoolAddressesProviderRegistry.sol";
import "../../openzeppelin/contracts/Ownable.sol";
import "../libraries/helpers/Errors.sol";

contract LendingPoolAddressesProviderRegistry is
    ILendingPoolAddressesProviderRegistry,
    Ownable
{
    mapping(address => uint256) private _addressesProviders;
    address[] private _addressesProvidersList;

    function getAddressesProvidersList()
        external
        view
        override
        returns (address[] memory)
    {
        address[] memory addressesProvidersList = _addressesProvidersList;
        uint256 maxLength = addressesProvidersList.length;
        address[] memory activeProviders = new address[](maxLength);

        for (uint256 i = 0; i < maxLength; i++) {
            if (_addressesProviders[addressesProvidersList[i]] > 0) {
                activeProviders[i] = addressesProvidersList[i];
            }
        }

        return activeProviders;
    }

    function registerAddressesProvider(
        address provider,
        uint256 id
    ) external override onlyOwner {
        require(id != 0, Errors.LPAPR_INVALID_ADDRESSES_PROVIDER_ID);
        _addressesProviders[provider] = id;
        _addToAddressesProvidersList(provider);
        emit AddressesProviderRegistered(provider);
    }

    function unregisterAddressesProvider(
        address provider
    ) external override onlyOwner {
        require(
            _addressesProviders[provider] > 0,
            Errors.LPAPR_PROVIDER_NOT_REGISTERED
        );
        
        _addressesProviders[provider] = 0;
        emit AddressesProviderUnregistered(provider);
    }

    function getAddressesProviderIdByAddress(
        address addressesProvider
    ) external view override returns (uint256) {
        return _addressesProviders[addressesProvider];
    }

    function _addToAddressesProvidersList(address provider) internal {
        uint256 providersCount = _addressesProvidersList.length;

        for (uint256 i = 0; i < providersCount; i++) {
            if (_addressesProvidersList[i] == provider) {
                return;
            }
        }

        _addressesProvidersList.push(provider);
    }
}
