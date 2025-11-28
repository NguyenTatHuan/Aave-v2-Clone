// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../interfaces/ICreditDelegationToken.sol";
import "../../interfaces/ILendingPool.sol";
import "../../openzeppelin/contracts/SafeMath.sol";
import "./IncentivizedERC20.sol";
import "../libraries/aave-upgradeability/VersionedInitializable.sol";
import "../libraries/helpers/Errors.sol";

abstract contract DebtTokenBase is
    ICreditDelegationToken,
    IncentivizedERC20("DEBTTOKEN_IMPL", "DEBTTOKEN_IMPL", 0),
    VersionedInitializable
{
    using SafeMath for uint256;

    mapping(address => mapping(address => uint256)) internal _borrowAllowances;

    modifier onlyLendingPool() {
        require(
            _msgSender() == address(_getLendingPool()),
            Errors.CT_CALLER_MUST_BE_LENDING_POOL
        );
        _;
    }

    function approveDelegation(
        address delegatee,
        uint256 amount
    ) external override {
        _borrowAllowances[_msgSender()][delegatee] = amount;
        emit BorrowAllowanceDelegated(
            _msgSender(),
            delegatee,
            _getUnderlyingAssetAddress(),
            amount
        );
    }

    function borrowAllowance(
        address fromUser,
        address toUser
    ) external view override returns (uint256) {
        return _borrowAllowances[fromUser][toUser];
    }

    function transfer(
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        recipient;
        amount;
        revert("TRANSFER_NOT_SUPPORTED");
    }

    function allowance(
        address owner,
        address spender
    ) public view virtual override returns (uint256) {
        owner;
        spender;
        revert("ALLOWANCE_NOT_SUPPORTED");
    }

    function approve(
        address spender,
        uint256 amount
    ) public virtual override returns (bool) {
        spender;
        amount;
        revert("APPROVAL_NOT_SUPPORTED");
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        sender;
        recipient;
        amount;
        revert("TRANSFER_NOT_SUPPORTED");
    }

    function increaseAllowance(
        address spender,
        uint256 addedValue
    ) public virtual override returns (bool) {
        spender;
        addedValue;
        revert("ALLOWANCE_NOT_SUPPORTED");
    }

    function decreaseAllowance(
        address spender,
        uint256 subtractedValue
    ) public virtual override returns (bool) {
        spender;
        subtractedValue;
        revert("ALLOWANCE_NOT_SUPPORTED");
    }

    function _decreaseBorrowAllowance(
        address delegator,
        address delegatee,
        uint256 amount
    ) internal {
        require(
            _borrowAllowances[delegator][delegatee] > amount,
            Errors.BORROW_ALLOWANCE_NOT_ENOUGH
        );

        uint256 newAllowance = _borrowAllowances[delegator][delegatee].sub(
            amount
        );

        _borrowAllowances[delegator][delegatee] = newAllowance;

        emit BorrowAllowanceDelegated(
            delegator,
            delegatee,
            _getUnderlyingAssetAddress(),
            newAllowance
        );
    }

    function _getUnderlyingAssetAddress()
        internal
        view
        virtual
        returns (address);

    function _getLendingPool() internal view virtual returns (ILendingPool);
}
