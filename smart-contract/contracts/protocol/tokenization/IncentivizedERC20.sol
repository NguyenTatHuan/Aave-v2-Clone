// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../openzeppelin/contracts/SafeMath.sol";
import "../../openzeppelin/contracts/IERC20.sol";
import "../../openzeppelin/contracts/Context.sol";
import "../../openzeppelin/contracts/IERC20Detailed.sol";
import "../../interfaces/IAaveIncentivesController.sol";

abstract contract IncentivizedERC20 is Context, IERC20, IERC20Detailed {
    using SafeMath for uint256;

    uint256 internal _totalSupply;
    string private _name;
    string private _symbol;
    uint8 private _decimals;
    mapping(address => uint256) internal _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    constructor(
        string memory tokenName,
        string memory tokenSymbol,
        uint8 tokenDecimals
    ) {
        _name = tokenName;
        _symbol = tokenSymbol;
        _decimals = tokenDecimals;
    }

    function _setName(string memory newName) internal {
        _name = newName;
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function _setSymbol(string memory newSymbol) internal {
        _symbol = newSymbol;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function _setDecimals(uint8 newDecimals) internal {
        _decimals = newDecimals;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(
        address account
    ) public view virtual override returns (uint256) {
        return _balances[account];
    }

    function _getIncentivesController()
        internal
        view
        virtual
        returns (IAaveIncentivesController);

    function transfer(
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        emit Transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(
        address owner,
        address spender
    ) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(
        address spender,
        uint256 amount
    ) public virtual override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        require(
            _allowances[sender][_msgSender()] >= amount,
            "ERC20: transfer amount exceeds allowance"
        );

        _transfer(sender, recipient, amount);

        _approve(
            sender,
            _msgSender(),
            _allowances[sender][_msgSender()].sub(amount)
        );

        emit Transfer(sender, recipient, amount);
        return true;
    }

    function increaseAllowance(
        address spender,
        uint256 addedValue
    ) public virtual returns (bool) {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender].add(addedValue)
        );

        return true;
    }

    function decreaseAllowance(
        address spender,
        uint256 subtractedValue
    ) public virtual returns (bool) {
        require(
            _allowances[_msgSender()][spender] >= subtractedValue,
            "ERC20: decreased allowance below zero"
        );

        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender].sub(subtractedValue)
        );

        return true;
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(sender, recipient, amount);

        uint256 oldSenderBalance = _balances[sender];

        require(
            oldSenderBalance >= amount,
            "ERC20: transfer amount exceeds balance"
        );

        _balances[sender] = oldSenderBalance.sub(amount);
        uint256 oldRecipientBalance = _balances[recipient];
        _balances[recipient] = _balances[recipient].add(amount);

        if (address(_getIncentivesController()) != address(0)) {
            uint256 currentTotalSupply = _totalSupply;
            _getIncentivesController().handleAction(
                sender,
                currentTotalSupply,
                oldSenderBalance
            );
            if (sender != recipient) {
                _getIncentivesController().handleAction(
                    recipient,
                    currentTotalSupply,
                    oldRecipientBalance
                );
            }
        }
    }

    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        uint256 oldTotalSupply = _totalSupply;
        _totalSupply = oldTotalSupply.add(amount);

        uint256 oldAccountBalance = _balances[account];
        _balances[account] = oldAccountBalance.add(amount);

        if (address(_getIncentivesController()) != address(0)) {
            _getIncentivesController().handleAction(
                account,
                oldTotalSupply,
                oldAccountBalance
            );
        }
    }

    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        uint256 oldTotalSupply = _totalSupply;
        _totalSupply = oldTotalSupply.sub(amount);

        uint256 oldAccountBalance = _balances[account];

        require(
            oldAccountBalance >= amount,
            "ERC20: burn amount exceeds balance"
        );

        _balances[account] = oldAccountBalance.sub(amount);

        if (address(_getIncentivesController()) != address(0)) {
            _getIncentivesController().handleAction(
                account,
                oldTotalSupply,
                oldAccountBalance
            );
        }
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}
}
