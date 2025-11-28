// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../openzeppelin/contracts/IERC20.sol";
import "../../openzeppelin/contracts/SafeERC20.sol";
import "../../openzeppelin/contracts/Address.sol";
import "../../openzeppelin/contracts/SafeMath.sol";
import "../../interfaces/ILendingPool.sol";
import "../../interfaces/ILendingPoolAddressesProvider.sol";
import "../../interfaces/IAToken.sol";
import "../../interfaces/IVariableDebtToken.sol";
import "../../interfaces/IPriceOracleGetter.sol";
import "../../interfaces/IStableDebtToken.sol";
import "../../flashloan/interfaces/IFlashLoanReceiver.sol";
import "../libraries/configuration/ReserveConfiguration.sol";
import "../libraries/configuration/UserConfiguration.sol";
import "../libraries/math/WadRayMath.sol";
import "../libraries/math/PercentageMath.sol";
import "../libraries/aave-upgradeability/VersionedInitializable.sol";
import "../libraries/logic/ReserveLogic.sol";
import "../libraries/logic/GenericLogic.sol";
import "../libraries/logic/ValidationLogic.sol";
import "../libraries/helpers/Helpers.sol";
import "../libraries/helpers/Errors.sol";
import "../libraries/types/DataTypes.sol";
import "./LendingPoolStorage.sol";

contract LendingPool is
    VersionedInitializable,
    ILendingPool,
    LendingPoolStorage
{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using UserConfiguration for DataTypes.UserConfigurationMap;
    using ReserveLogic for DataTypes.ReserveData;

    uint256 public constant LENDING_REVISION = 0x2;

    modifier whenNotPaused() {
        require(!_paused, Errors.LP_IS_PAUSED);
        _;
    }

    modifier onlyLendingPoolConfigurator() {
        require(
            _addressesProvider.getLendingPoolConfigurator() == msg.sender,
            Errors.LP_CALLER_NOT_LENDING_POOL_CONFIGURATOR
        );
        _;
    }

    function getRevision() internal pure override returns (uint256) {
        return LENDING_REVISION;
    }

    function initialize(
        ILendingPoolAddressesProvider provider
    ) public initializer {
        _addressesProvider = provider;
        _maxStableRateBorrowSizePercent = 2500;
        _flashLoanPremiumTotal = 9;
        _maxNumberOfReserves = 128;
    }

    function deposit(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external override whenNotPaused {
        DataTypes.ReserveData storage reserve = _reserves[asset];

        ValidationLogic.validateDeposit(reserve, amount);

        address aToken = reserve.aTokenAddress;

        reserve.updateState();
        reserve.updateInterestRates(asset, aToken, amount, 0);

        IERC20(asset).safeTransferFrom(msg.sender, aToken, amount);

        bool isFirstDeposit = IAToken(aToken).mint(
            onBehalfOf,
            amount,
            reserve.liquidityIndex
        );

        if (isFirstDeposit) {
            _usersConfig[onBehalfOf].setUsingAsCollateral(reserve.id, true);
            emit ReserveUsedAsCollateralEnabled(asset, onBehalfOf);
        }

        emit Deposit(asset, msg.sender, onBehalfOf, amount, referralCode);
    }

    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external override whenNotPaused returns (uint256) {
        DataTypes.ReserveData storage reserve = _reserves[asset];

        address aToken = reserve.aTokenAddress;

        uint256 userBalance = IAToken(aToken).balanceOf(msg.sender);
        uint256 amountToWithdraw = amount;

        if (amount == type(uint256).max) {
            amountToWithdraw = userBalance;
        }

        ValidationLogic.validateWithdraw(
            asset,
            amountToWithdraw,
            userBalance,
            _reserves,
            _usersConfig[msg.sender],
            _reservesList,
            _reservesCount,
            _addressesProvider.getPriceOracle()
        );

        reserve.updateState();
        reserve.updateInterestRates(asset, aToken, 0, amountToWithdraw);

        if (amountToWithdraw == userBalance) {
            _usersConfig[msg.sender].setUsingAsCollateral(reserve.id, false);
            emit ReserveUsedAsCollateralDisabled(asset, msg.sender);
        }

        IAToken(aToken).burn(
            msg.sender,
            to,
            amountToWithdraw,
            reserve.liquidityIndex
        );

        emit Withdraw(asset, msg.sender, to, amountToWithdraw);
        return amountToWithdraw;
    }

    function borrow(
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        uint16 referralCode,
        address onBehalfOf
    ) external override whenNotPaused {
        DataTypes.ReserveData storage reserve = _reserves[asset];

        _executeBorrow(
            ExecuteBorrowParams(
                asset,
                msg.sender,
                onBehalfOf,
                amount,
                interestRateMode,
                reserve.aTokenAddress,
                referralCode,
                true
            )
        );
    }

    function repay(
        address asset,
        uint256 amount,
        uint256 rateMode,
        address onBehalfOf
    ) external override whenNotPaused returns (uint256) {
        DataTypes.ReserveData storage reserve = _reserves[asset];

        (uint256 stableDebt, uint256 variableDebt) = Helpers.getUserCurrentDebt(
            onBehalfOf,
            reserve
        );

        DataTypes.InterestRateMode interestRateMode = DataTypes
            .InterestRateMode(rateMode);

        ValidationLogic.validateRepay(
            reserve,
            amount,
            interestRateMode,
            onBehalfOf,
            stableDebt,
            variableDebt
        );

        uint256 paybackAmount = interestRateMode ==
            DataTypes.InterestRateMode.STABLE
            ? stableDebt
            : variableDebt;

        if (paybackAmount > amount) {
            paybackAmount = amount;
        }

        reserve.updateState();

        if (interestRateMode == DataTypes.InterestRateMode.STABLE) {
            IStableDebtToken(reserve.stableDebtTokenAddress).burn(
                onBehalfOf,
                paybackAmount
            );
        } else {
            IVariableDebtToken(reserve.variableDebtTokenAddress).burn(
                onBehalfOf,
                paybackAmount,
                reserve.variableBorrowIndex
            );
        }

        address aToken = reserve.aTokenAddress;

        reserve.updateInterestRates(asset, aToken, paybackAmount, 0);

        if (stableDebt.add(variableDebt).sub(paybackAmount) == 0) {
            _usersConfig[onBehalfOf].setUsingAsCollateral(reserve.id, false);
        }

        IERC20(asset).safeTransferFrom(msg.sender, aToken, paybackAmount);
        IAToken(aToken).handleRepayment(msg.sender, paybackAmount);
        emit Repay(asset, onBehalfOf, msg.sender, paybackAmount);
        return paybackAmount;
    }

    function swapBorrowRateMode(
        address asset,
        uint256 rateMode
    ) external override whenNotPaused {
        DataTypes.ReserveData storage reserve = _reserves[asset];

        (uint256 stableDebt, uint256 variableDebt) = Helpers.getUserCurrentDebt(
            msg.sender,
            reserve
        );

        DataTypes.InterestRateMode interestRateMode = DataTypes
            .InterestRateMode(rateMode);

        ValidationLogic.validateSwapRateMode(
            reserve,
            _usersConfig[msg.sender],
            stableDebt,
            variableDebt,
            interestRateMode
        );

        reserve.updateState();

        if (interestRateMode == DataTypes.InterestRateMode.STABLE) {
            IStableDebtToken(reserve.stableDebtTokenAddress).burn(
                msg.sender,
                stableDebt
            );

            IVariableDebtToken(reserve.variableDebtTokenAddress).mint(
                msg.sender,
                msg.sender,
                stableDebt,
                reserve.variableBorrowIndex
            );
        } else {
            IVariableDebtToken(reserve.variableDebtTokenAddress).burn(
                msg.sender,
                variableDebt,
                reserve.variableBorrowIndex
            );

            IStableDebtToken(reserve.stableDebtTokenAddress).mint(
                msg.sender,
                msg.sender,
                variableDebt,
                reserve.currentStableBorrowRate
            );
        }

        reserve.updateInterestRates(asset, reserve.aTokenAddress, 0, 0);

        emit Swap(asset, msg.sender, rateMode);
    }

    function rebalanceStableBorrowRate(
        address asset,
        address user
    ) external override whenNotPaused {
        DataTypes.ReserveData storage reserve = _reserves[asset];

        IERC20 stableDebtToken = IERC20(reserve.stableDebtTokenAddress);
        IERC20 variableDebtToken = IERC20(reserve.variableDebtTokenAddress);
        address aTokenAddress = reserve.aTokenAddress;

        uint256 stableDebt = IERC20(stableDebtToken).balanceOf(user);

        ValidationLogic.validateRebalanceStableBorrowRate(
            reserve,
            asset,
            stableDebtToken,
            variableDebtToken,
            aTokenAddress
        );

        reserve.updateState();

        IStableDebtToken(address(stableDebtToken)).burn(user, stableDebt);
        IStableDebtToken(address(stableDebtToken)).mint(
            user,
            user,
            stableDebt,
            reserve.currentStableBorrowRate
        );

        reserve.updateInterestRates(asset, aTokenAddress, 0, 0);

        emit RebalanceStableBorrowRate(asset, user);
    }

    function setUserUseReserveAsCollateral(
        address asset,
        bool useAsCollateral
    ) external override whenNotPaused {
        DataTypes.ReserveData storage reserve = _reserves[asset];

        ValidationLogic.validateSetUseReserveAsCollateral(
            reserve,
            asset,
            useAsCollateral,
            _reserves,
            _usersConfig[msg.sender],
            _reservesList,
            _reservesCount,
            _addressesProvider.getPriceOracle()
        );

        _usersConfig[msg.sender].setUsingAsCollateral(
            reserve.id,
            useAsCollateral
        );

        if (useAsCollateral) {
            emit ReserveUsedAsCollateralEnabled(asset, msg.sender);
        } else {
            emit ReserveUsedAsCollateralDisabled(asset, msg.sender);
        }
    }

    function liquidationCall(
        address collateralAsset,
        address debtAsset,
        address user,
        uint256 debtToCover,
        bool receiveAToken
    ) external override whenNotPaused {
        address collateralManager = _addressesProvider
            .getLendingPoolCollateralManager();

        (bool success, bytes memory result) = collateralManager.delegatecall(
            abi.encodeWithSignature(
                "liquidationCall(address,address,address,uint256,bool)",
                collateralAsset,
                debtAsset,
                user,
                debtToCover,
                receiveAToken
            )
        );

        require(success, Errors.LP_LIQUIDATION_CALL_FAILED);

        (uint256 returnCode, string memory returnMessage) = abi.decode(
            result,
            (uint256, string)
        );

        require(returnCode == 0, string(abi.encodePacked(returnMessage)));
    }

    struct FlashLoanLocalVars {
        IFlashLoanReceiver receiver;
        address oracle;
        uint256 i;
        address currentAsset;
        address currentATokenAddress;
        uint256 currentAmount;
        uint256 currentPremium;
        uint256 currentAmountPlusPremium;
        address debtToken;
    }

    function flashLoan(
        address receiverAddress,
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata modes,
        address onBehalfOf,
        bytes calldata params,
        uint16 referralCode
    ) external override whenNotPaused {
        FlashLoanLocalVars memory vars;

        ValidationLogic.validateFlashloan(assets, amounts);

        address[] memory aTokenAddresses = new address[](assets.length);
        uint256[] memory premiums = new uint256[](assets.length);

        vars.receiver = IFlashLoanReceiver(receiverAddress);

        for (vars.i = 0; vars.i < assets.length; vars.i++) {
            aTokenAddresses[vars.i] = _reserves[assets[vars.i]].aTokenAddress;

            premiums[vars.i] = amounts[vars.i].mul(_flashLoanPremiumTotal).div(
                10000
            );

            IAToken(aTokenAddresses[vars.i]).transferUnderlyingTo(
                receiverAddress,
                amounts[vars.i]
            );
        }

        require(
            vars.receiver.executeOperation(
                assets,
                amounts,
                premiums,
                msg.sender,
                params
            ),
            Errors.LP_INVALID_FLASH_LOAN_EXECUTOR_RETURN
        );

        for (vars.i = 0; vars.i < assets.length; vars.i++) {
            vars.currentAsset = assets[vars.i];
            vars.currentAmount = amounts[vars.i];
            vars.currentPremium = premiums[vars.i];
            vars.currentATokenAddress = aTokenAddresses[vars.i];
            vars.currentAmountPlusPremium = vars.currentAmount.add(
                vars.currentPremium
            );

            if (
                DataTypes.InterestRateMode(modes[vars.i]) ==
                DataTypes.InterestRateMode.NONE
            ) {
                _reserves[vars.currentAsset].updateState();
                _reserves[vars.currentAsset].cumulateToLiquidityIndex(
                    IERC20(vars.currentATokenAddress).totalSupply(),
                    vars.currentPremium
                );

                _reserves[vars.currentAsset].updateInterestRates(
                    vars.currentAsset,
                    vars.currentATokenAddress,
                    vars.currentAmountPlusPremium,
                    0
                );

                IERC20(vars.currentAsset).safeTransferFrom(
                    receiverAddress,
                    vars.currentATokenAddress,
                    vars.currentAmountPlusPremium
                );
            } else {
                _executeBorrow(
                    ExecuteBorrowParams(
                        vars.currentAsset,
                        msg.sender,
                        onBehalfOf,
                        vars.currentAmount,
                        modes[vars.i],
                        vars.currentATokenAddress,
                        referralCode,
                        false
                    )
                );
            }
            emit FlashLoan(
                receiverAddress,
                msg.sender,
                vars.currentAsset,
                vars.currentAmount,
                vars.currentPremium,
                referralCode
            );
        }
    }

    function getReserveData(
        address asset
    ) external view override returns (DataTypes.ReserveData memory) {
        return _reserves[asset];
    }

    function getUserAccountData(
        address user
    )
        external
        view
        override
        returns (
            uint256 totalCollateralETH,
            uint256 totalDebtETH,
            uint256 availableBorrowsETH,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        )
    {
        (
            totalCollateralETH,
            totalDebtETH,
            ltv,
            currentLiquidationThreshold,
            healthFactor
        ) = GenericLogic.calculateUserAccountData(
                user,
                _reserves,
                _usersConfig[user],
                _reservesList,
                _reservesCount,
                _addressesProvider.getPriceOracle()
            );

        availableBorrowsETH = GenericLogic.calculateAvailableBorrowsETH(
            totalCollateralETH,
            totalDebtETH,
            ltv
        );
    }

    function getConfiguration(
        address asset
    )
        external
        view
        override
        returns (DataTypes.ReserveConfigurationMap memory)
    {
        return _reserves[asset].configuration;
    }

    function getUserConfiguration(
        address user
    ) external view override returns (DataTypes.UserConfigurationMap memory) {
        return _usersConfig[user];
    }

    function getReserveNormalizedIncome(
        address asset
    ) external view virtual override returns (uint256) {
        return _reserves[asset].getNormalizedIncome();
    }

    function getReserveNormalizedVariableDebt(
        address asset
    ) external view override returns (uint256) {
        return _reserves[asset].getNormalizedDebt();
    }

    function paused() external view override returns (bool) {
        return _paused;
    }

    function getReservesList()
        external
        view
        override
        returns (address[] memory)
    {
        address[] memory _activeReserves = new address[](_reservesCount);

        for (uint256 i = 0; i < _reservesCount; i++) {
            _activeReserves[i] = _reservesList[i];
        }
        return _activeReserves;
    }

    function getAddressesProvider()
        external
        view
        override
        returns (ILendingPoolAddressesProvider)
    {
        return _addressesProvider;
    }

    function MAX_STABLE_RATE_BORROW_SIZE_PERCENT()
        public
        view
        returns (uint256)
    {
        return _maxStableRateBorrowSizePercent;
    }

    function FLASHLOAN_PREMIUM_TOTAL() public view returns (uint256) {
        return _flashLoanPremiumTotal;
    }

    function MAX_NUMBER_RESERVES() public view returns (uint256) {
        return _maxNumberOfReserves;
    }

    function finalizeTransfer(
        address asset,
        address from,
        address to,
        uint256 amount,
        uint256 balanceFromBefore,
        uint256 balanceToBefore
    ) external override whenNotPaused {
        require(
            msg.sender == _reserves[asset].aTokenAddress,
            Errors.LP_CALLER_MUST_BE_AN_ATOKEN
        );

        ValidationLogic.validateTransfer(
            from,
            _reserves,
            _usersConfig[from],
            _reservesList,
            _reservesCount,
            _addressesProvider.getPriceOracle()
        );

        uint256 reserveId = _reserves[asset].id;

        if (from != to) {
            if (balanceFromBefore.sub(amount) == 0) {
                DataTypes.UserConfigurationMap
                    storage fromConfig = _usersConfig[from];

                fromConfig.setUsingAsCollateral(reserveId, false);

                emit ReserveUsedAsCollateralDisabled(asset, from);
            }

            if (balanceToBefore == 0 && amount != 0) {
                DataTypes.UserConfigurationMap storage toConfig = _usersConfig[
                    to
                ];

                toConfig.setUsingAsCollateral(reserveId, true);

                emit ReserveUsedAsCollateralEnabled(asset, to);
            }
        }
    }

    function initReserve(
        address asset,
        address aTokenAddress,
        address stableDebtAddress,
        address variableDebtAddress,
        address interestRateStrategyAddress
    ) external override onlyLendingPoolConfigurator {
        require(Address.isContract(asset), Errors.LP_NOT_CONTRACT);
        _reserves[asset].init(
            aTokenAddress,
            stableDebtAddress,
            variableDebtAddress,
            interestRateStrategyAddress
        );
        _addReserveToList(asset);
    }

    function setReserveInterestRateStrategyAddress(
        address asset,
        address rateStrategyAddress
    ) external override onlyLendingPoolConfigurator {
        _reserves[asset].interestRateStrategyAddress = rateStrategyAddress;
    }

    function setConfiguration(
        address asset,
        uint256 configuration
    ) external override onlyLendingPoolConfigurator {
        _reserves[asset].configuration.data = configuration;
    }

    function setPause(bool val) external override onlyLendingPoolConfigurator {
        _paused = val;
        if (_paused) {
            emit Paused();
        } else {
            emit Unpaused();
        }
    }

    struct ExecuteBorrowParams {
        address asset;
        address user;
        address onBehalfOf;
        uint256 amount;
        uint256 interestRateMode;
        address aTokenAddress;
        uint16 referralCode;
        bool releaseUnderlying;
    }

    function _executeBorrow(ExecuteBorrowParams memory vars) internal {
        DataTypes.ReserveData storage reserve = _reserves[vars.asset];
        DataTypes.UserConfigurationMap storage userConfig = _usersConfig[
            vars.onBehalfOf
        ];

        address oracle = _addressesProvider.getPriceOracle();

        uint256 amountInETH = IPriceOracleGetter(oracle)
            .getAssetPrice(vars.asset)
            .mul(vars.amount)
            .div(10 ** reserve.configuration.getDecimals());

        ValidationLogic.validateBorrow(
            vars.asset,
            reserve,
            vars.onBehalfOf,
            vars.amount,
            amountInETH,
            vars.interestRateMode,
            _maxStableRateBorrowSizePercent,
            _reserves,
            userConfig,
            _reservesList,
            _reservesCount,
            oracle
        );

        reserve.updateState();

        uint256 currentStableRate = 0;

        bool isFirstBorrowing = false;
        if (
            DataTypes.InterestRateMode(vars.interestRateMode) ==
            DataTypes.InterestRateMode.STABLE
        ) {
            currentStableRate = reserve.currentStableBorrowRate;

            isFirstBorrowing = IStableDebtToken(reserve.stableDebtTokenAddress)
                .mint(
                    vars.user,
                    vars.onBehalfOf,
                    vars.amount,
                    currentStableRate
                );
        } else {
            isFirstBorrowing = IVariableDebtToken(
                reserve.variableDebtTokenAddress
            ).mint(
                    vars.user,
                    vars.onBehalfOf,
                    vars.amount,
                    reserve.variableBorrowIndex
                );
        }

        if (isFirstBorrowing) {
            userConfig.setBorrowing(reserve.id, true);
        }

        reserve.updateInterestRates(
            vars.asset,
            vars.aTokenAddress,
            0,
            vars.releaseUnderlying ? vars.amount : 0
        );

        if (vars.releaseUnderlying) {
            IAToken(vars.aTokenAddress).transferUnderlyingTo(
                vars.user,
                vars.amount
            );
        }

        emit Borrow(
            vars.asset,
            vars.user,
            vars.onBehalfOf,
            vars.amount,
            vars.interestRateMode,
            DataTypes.InterestRateMode(vars.interestRateMode) ==
                DataTypes.InterestRateMode.STABLE
                ? currentStableRate
                : reserve.currentVariableBorrowRate,
            vars.referralCode
        );
    }

    function _addReserveToList(address asset) internal {
        uint256 reservesCount = _reservesCount;

        require(
            reservesCount < _maxNumberOfReserves,
            Errors.LP_NO_MORE_RESERVES_ALLOWED
        );

        bool reserveAlreadyAdded = _reserves[asset].id != 0 ||
            _reservesList[0] == asset;

        if (!reserveAlreadyAdded) {
            _reserves[asset].id = uint8(reservesCount);
            _reservesList[reservesCount] = asset;

            _reservesCount = reservesCount + 1;
        }
    }
}
