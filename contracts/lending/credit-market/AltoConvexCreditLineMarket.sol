// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {AltoBaseMarket} from "@alto/lending/AltoBaseMarket.sol";
import {AltoConvexCreditLineLib} from "./AltoConvexCreditLineLib.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";
import {Uint128Converter} from "@alto/lending/libraries/Uint128Converter.sol";
import {
    CreditMarketInitParams,
    IAltoConvexCreditLineMarketBase,
    ConvexCreditLineInitParams,
    IAltoConvexCreditLineMarketStaticTypes
} from "@alto/lending/interfaces/IAltoConvexCreditLineMarket.sol";
import {IIrm} from "@alto/lending/interfaces/IIrm.sol";
import {BaseMarketInitParams, IMarketBase, MarketType, Position} from "@alto/lending/interfaces/IMarket.sol";
import {IMintableERC20} from "@alto/lending/interfaces/IMintableERC20.sol";
import {IConvexRewardPool} from "@alto/lending/interfaces/vendor/IConvexRewardPool.sol";

import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {FixedPointMath, MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";
import {ILendingOracle, LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";

/// @title Alto Convex Credit Line Market
/// @custom:contact security@altofoundation.org
/// @notice A single-account revolving DUSD credit line backed by Curve LP staked through Convex
/// @dev `totalSupply.assets` is the credit capacity shared by active debt and unsettled bad debt.
/// Supply shares stay zero. Interest and opening fees accrue to `claimableFeesAssets`.
/// DUSD is intentionally unsupported as a reward token. This integration must not use DUSD reward incentives.
/// Any DUSD rewards received remain in the market, which exposes no DUSD reward-forwarding or sweep function.
contract AltoConvexCreditLineMarket is AltoBaseMarket, IAltoConvexCreditLineMarketStaticTypes {
    using FixedPointMath for uint256;
    using AssetShareConversionMath for uint256;
    using Uint128Converter for uint256;

    /// @inheritdoc IAltoConvexCreditLineMarketBase
    address public creditAccount;

    /// @inheritdoc IAltoConvexCreditLineMarketBase
    uint256 public foreclosureLtv;

    /// @inheritdoc IAltoConvexCreditLineMarketBase
    uint128 public claimableFeesAssets;

    /// @notice The borrow opening fee in MATH_PRECISION
    uint256 private _borrowOpeningFee;

    /// @inheritdoc IAltoConvexCreditLineMarketBase
    address public convexBooster;

    /// @inheritdoc IAltoConvexCreditLineMarketBase
    uint256 public convexPoolId;

    /// @inheritdoc IAltoConvexCreditLineMarketBase
    address public convexRewardPool;

    /// @inheritdoc IAltoConvexCreditLineMarketBase
    address public rewardRecipient;

    /// @inheritdoc IAltoConvexCreditLineMarketBase
    bool public convexActive;

    /// @inheritdoc IAltoConvexCreditLineMarketBase
    address[] public rewardToken;

    /// @inheritdoc IAltoConvexCreditLineMarketBase
    mapping(address => bool) public isRewardToken;

    /// @inheritdoc IAltoConvexCreditLineMarketBase
    uint256 public badDebtAssets;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the credit market and Convex pool
    /// @param _initParams The credit market and Convex initialization parameters
    function initialize(ConvexCreditLineInitParams memory _initParams) external initializer {
        _initializeCreditMarket(_initParams.creditMarketInitParams);
        _initializeConvex(_initParams);
    }

    /// @inheritdoc AltoBaseMarket
    function borrowOpeningFee() public view override(AltoBaseMarket, IMarketBase) returns (uint256) {
        return _borrowOpeningFee;
    }

    /// @inheritdoc IAltoConvexCreditLineMarketBase
    function setCreditAccount(address _newCreditAccount) external onlyOwner {
        _requireNonZeroAddress(_newCreditAccount);

        Position storage creditPosition = position[creditAccount];
        if (creditPosition.borrowShares != 0 || creditPosition.collateralAssets != 0) {
            revert AltoCreditMarketPositionNotEmpty();
        }

        emit SetCreditAccount(creditAccount, _newCreditAccount);
        creditAccount = _newCreditAccount;
    }

    /// @inheritdoc IAltoConvexCreditLineMarketBase
    function setCreditLimit(uint256 _newCreditLimit) external onlyOwner {
        if (!paused[PAUSE_TYPE]) {
            _accrueInterest();
        }
        if (uint256(totalBorrowed.assets) + badDebtAssets > _newCreditLimit) {
            revert AltoBaseMarketInsufficientMarketLiquidity();
        }

        uint256 oldCreditLimit = totalSupply.assets;
        totalSupply.assets = _newCreditLimit.toUint128();
        emit SetCreditLimit(oldCreditLimit, _newCreditLimit);
    }

    /// @inheritdoc IAltoConvexCreditLineMarketBase
    function setForeclosureLtv(uint256 _newForeclosureLtv) external onlyOwner {
        if (_newForeclosureLtv <= maxLtv || _newForeclosureLtv > MATH_PRECISION) {
            revert AltoCreditMarketInvalidInput();
        }

        emit SetForeclosureLtv(foreclosureLtv, _newForeclosureLtv);
        foreclosureLtv = _newForeclosureLtv;
    }

    /// @inheritdoc IAltoConvexCreditLineMarketBase
    function setBorrowOpeningFee(uint256 _newBorrowOpeningFee) external onlyOwner {
        if (_newBorrowOpeningFee > MATH_PRECISION) {
            revert AltoCreditMarketInvalidInput();
        }

        emit SetBorrowOpeningFee(_borrowOpeningFee, _newBorrowOpeningFee);
        _borrowOpeningFee = _newBorrowOpeningFee;
    }

    /// @inheritdoc IMarketBase
    function setFeeRecipient(address _feeRecipient) external override onlyOwner {
        _requireNonZeroAddress(_feeRecipient);

        emit SetFeeRecipient(feeRecipient, _feeRecipient);
        feeRecipient = _feeRecipient;
    }

    /// @inheritdoc IAltoConvexCreditLineMarketBase
    function claimInterest(uint256 interest) external whenNotPaused returns (uint256) {
        _requireNonZeroAddress(feeRecipient);
        if (interest > claimableFeesAssets) {
            revert AltoCreditMarketInvalidInput();
        }

        return _claimInterest(interest);
    }

    /// @inheritdoc IAltoConvexCreditLineMarketBase
    function settleBadDebt(uint256 assets) external onlyOwner {
        if (assets == 0) {
            revert AltoCreditMarketInvalidInput();
        }

        badDebtAssets -= assets;
        _sendBorrowToken(msg.sender, address(this), assets);

        emit BadDebtSettled(assets);
    }

    /// @inheritdoc AltoBaseMarket
    /// @dev Foreclosure is available only after debt strictly exceeds the foreclosure LTV.
    /// All active debt becomes bad debt and all recorded collateral goes to the owner. Claimable fees remain
    /// unchanged. Collateral withdrawal does not claim rewards, which remain payable to `rewardRecipient`.
    /// LP recovery and swaps happen separately. `settleBadDebt` burns recovered DUSD through this market.
    function governanceLiquidate(address borrower, bool skipAccrueInterest)
        external
        override(AltoBaseMarket, IMarketBase)
        nonReentrant
        onlyOwner
        returns (uint256 collateralAmount, uint256 badDebtAmount)
    {
        _requireCreditAccount(borrower);
        if (!paused[PAUSE_TYPE] && !skipAccrueInterest) {
            _accrueInterest();
        }

        if (!_isLiquidatable(borrower)) {
            revert AltoCreditMarketPositionNotForeclosable();
        }

        Position storage borrowerPosition = position[borrower];
        collateralAmount = borrowerPosition.collateralAssets;
        uint128 badDebtShares = borrowerPosition.borrowShares;
        badDebtAmount = totalBorrowed.assets;

        totalBorrowed.assets = 0;
        totalBorrowed.shares = 0;

        badDebtAssets += badDebtAmount;
        emit BadDebtAccrued(badDebtAmount);

        borrowerPosition.borrowShares = 0;
        borrowerPosition.collateralAssets = 0;

        if (collateralAmount != 0) {
            _sendCollateral(msg.sender, collateralAmount);
        }

        emit GovernanceLiquidation(borrower, msg.sender, collateralAmount, badDebtAmount, badDebtShares);
    }

    /// @inheritdoc IAltoConvexCreditLineMarketBase
    function claimRewards() external nonReentrant returns (uint256[] memory claimedAmounts) {
        return AltoConvexCreditLineLib.claimRewards(convexRewardPool, rewardRecipient, rewardToken);
    }

    /// @inheritdoc IAltoConvexCreditLineMarketBase
    function setRewardRecipient(address _newRecipient) external {
        _requireCreditAccount(msg.sender);
        _requireNonZeroAddress(_newRecipient);

        emit SetRewardRecipient(rewardRecipient, _newRecipient);
        rewardRecipient = _newRecipient;
    }

    /// @inheritdoc IAltoConvexCreditLineMarketBase
    function addRewardToken(address _token) external onlyOwner {
        _addRewardToken(_token);
    }

    /// @inheritdoc IAltoConvexCreditLineMarketBase
    function removeRewardToken(address _token) external onlyOwner {
        AltoConvexCreditLineLib.removeRewardToken(rewardToken, isRewardToken, convexRewardPool, _token);

        emit RewardTokenRemoved(_token);
    }

    /// @inheritdoc IAltoConvexCreditLineMarketBase
    function emergencyExitConvex() external onlyOwner returns (uint256 assets) {
        if (!paused[PAUSE_TYPE]) {
            revert AltoConvexCreditLineMustBePaused();
        }
        if (!convexActive) {
            revert AltoConvexCreditLineStrategyInactive();
        }

        convexActive = false;
        assets = AltoConvexCreditLineLib.emergencyWithdraw(convexRewardPool);

        emit ConvexEmergencyExit(assets);
    }

    /// @dev Initializes the Base market and then initializes Credit state.
    function _initializeCreditMarket(CreditMarketInitParams memory _initParams) internal onlyInitializing {
        BaseMarketInitParams memory baseMarketInitParams = _initParams.baseMarketInitParams;

        _requireNonZeroAddress(_initParams.creditAccount);
        _requireNonZeroAddress(baseMarketInitParams.feeRecipient);
        _requireNonZeroAddress(baseMarketInitParams.irm);
        if (
            _initParams.creditLimit == 0 || _initParams.initialBorrowOpeningFee > MATH_PRECISION
                || baseMarketInitParams.maxLtv >= _initParams.foreclosureLtv
                || _initParams.foreclosureLtv > MATH_PRECISION
        ) {
            revert AltoCreditMarketInvalidInput();
        }

        __UUPSUpgradeable_init();
        __AltoBaseMarket_init(baseMarketInitParams, MarketType.CREDIT_MINT);

        foreclosureLtv = _initParams.foreclosureLtv;
        emit SetForeclosureLtv(0, _initParams.foreclosureLtv);

        creditAccount = _initParams.creditAccount;
        emit SetCreditAccount(address(0), _initParams.creditAccount);

        totalSupply.assets = _initParams.creditLimit.toUint128();
        emit SetCreditLimit(0, _initParams.creditLimit);

        _borrowOpeningFee = _initParams.initialBorrowOpeningFee;
        emit SetBorrowOpeningFee(0, _initParams.initialBorrowOpeningFee);
    }

    /// @inheritdoc AltoBaseMarket
    /// @dev Unlike `AltoBaseMarket`, the IRM must be nonzero.
    function _setIrm(address _irm, bool _skipAccrueInterest) internal override {
        _requireNonZeroAddress(_irm);
        if (_irm == irm) {
            revert AltoCreditMarketInvalidInput();
        }

        super._setIrm(_irm, _skipAccrueInterest);
    }

    /// @inheritdoc AltoBaseMarket
    function _setMaxLtv(uint256 _maxLtv) internal override {
        if (_maxLtv >= foreclosureLtv) {
            revert AltoCreditMarketInvalidInput();
        }

        emit SetMaxLtv(maxLtv, _maxLtv);
        maxLtv = _maxLtv;
    }

    /// @dev Disabled because this market does not support a liquidation engine.
    function _setLiquidationEngine(address) internal pure override {
        revert AltoCreditMarketUnsupportedOperation();
    }

    /// @dev Disabled because this market does not support a liquidation periphery.
    function _setAuthorizedLiquidationPeriphery(address, bool) internal pure override {
        revert AltoCreditMarketUnsupportedOperation();
    }

    /// @dev Disabled because borrow and collateral-removal callbacks are unsupported.
    function _setAuthorizedCallback(address, bool) internal pure override {
        revert AltoCreditMarketUnsupportedOperation();
    }

    /// @dev Disabled because this market does not support lender supply.
    function _addSupply(uint256, uint256, address) internal pure override returns (uint256, uint256) {
        revert AltoCreditMarketUnsupportedOperation();
    }

    /// @dev Disabled because this market does not support lender supply.
    function _removeSupply(uint256, uint256, address, address) internal pure override returns (uint256, uint256) {
        revert AltoCreditMarketUnsupportedOperation();
    }

    /// @inheritdoc AltoBaseMarket
    /// @dev Only the exact `creditAccount` may call and receive collateral. Authorized delegates cannot add collateral.
    /// The collateral is deposited into Convex.
    function _addCollateral(uint256 assets, address onBehalf) internal override nonReentrant returns (uint256) {
        _requireCreditAccount(msg.sender);
        _requireCreditAccount(onBehalf);
        return super._addCollateral(assets, onBehalf);
    }

    /// @inheritdoc AltoBaseMarket
    function _receiveCollateral(uint256 assets) internal override {
        if (!convexActive) {
            revert AltoCreditMarketInvalidInput();
        }

        super._receiveCollateral(assets);
        AltoConvexCreditLineLib.depositCollateralToConvex(collateralToken, convexBooster, convexPoolId, assets);
    }

    /// @inheritdoc AltoBaseMarket
    /// @dev Callbacks are unsupported. Active collateral is unwrapped from Convex, while collateral recovered by an
    /// emergency exit is transferred from idle custody. The remaining position must be solvent.
    function _removeCollateral(uint256 assets, address onBehalf, address receiver, bytes calldata swapParams)
        internal
        override
        returns (uint256)
    {
        _requireNonZeroAddress(receiver);
        if (swapParams.length != 0) {
            revert AltoCreditMarketCallbacksUnsupported();
        }
        _requireCreditAccount(onBehalf);

        return super._removeCollateral(assets, onBehalf, receiver, swapParams);
    }

    /// @inheritdoc AltoBaseMarket
    function _sendCollateral(address receiver, uint256 assets) internal override {
        if (convexActive) {
            AltoConvexCreditLineLib.withdrawAndUnwrapCollateral(convexRewardPool, assets);
            emit CollateralUnstaked(receiver, assets);
        }

        super._sendCollateral(receiver, assets);
    }

    /// @inheritdoc AltoBaseMarket
    /// @dev Debt may only be assigned to `creditAccount`; it or an authorized delegate may call. Callbacks are unsupported.
    function _borrow(uint256 assets, uint256 shares, address onBehalf, address receiver, bytes calldata swapParams)
        internal
        override
        returns (uint256, uint256, uint256)
    {
        _requireCreditAccount(onBehalf);
        if (swapParams.length != 0) {
            revert AltoCreditMarketCallbacksUnsupported();
        }

        uint256 openingFeeAssets;
        (assets, shares, openingFeeAssets) = super._borrow(assets, shares, onBehalf, receiver, swapParams);

        if (uint256(totalBorrowed.assets) + badDebtAssets > totalSupply.assets) {
            revert AltoBaseMarketInsufficientMarketLiquidity();
        }

        return (assets, shares, openingFeeAssets);
    }

    /// @dev Adds the opening fee to `claimableFeesAssets` without creating fee-recipient supply shares.
    /// @param openingFeeAssets The opening fee added to the claimable balance.
    /// @return Always zero because this market has no lender supply shares.
    function _applyBorrowOpeningFee(uint256 openingFeeAssets) internal override returns (uint256) {
        claimableFeesAssets += openingFeeAssets.toUint128();

        return 0;
    }

    /// @inheritdoc AltoBaseMarket
    /// @dev Only the exact `creditAccount` may repay its own debt. Authorized delegates and third parties cannot repay.
    /// Borrow tokens are burned from `creditAccount`.
    function _repay(uint256 assets, uint256 shares, address onBehalf) internal override returns (uint256, uint256) {
        _requireCreditAccount(msg.sender);
        _requireCreditAccount(onBehalf);

        _accrueInterest();

        if (claimableFeesAssets > 0) {
            _claimInterest(0);
        }

        return super._repay(assets, shares, onBehalf);
    }

    /// @dev Claims interest and fees by minting borrow tokens to the fee recipient.
    function _claimInterest(uint256 interest) internal returns (uint256) {
        if (interest == 0) {
            interest = claimableFeesAssets;
        }

        claimableFeesAssets -= interest.toUint128();
        if (interest != 0) {
            _sendBorrowToken(address(this), feeRecipient, interest);
        }

        emit InterestClaimed(feeRecipient, interest);

        return interest;
    }

    /// @dev Accrues interest into active debt and `claimableFeesAssets` without changing the credit limit.
    function _accrueInterest() internal override {
        (uint256 interest, uint256 borrowRate) = IIrm(irm).updateInterestRate(totalSupply.assets, totalBorrowed.assets);

        if (interest != 0) {
            totalBorrowed.assets += interest.toUint128();
            claimableFeesAssets += interest.toUint128();
            emit AccrueInterest(borrowRate, interest, totalBorrowed.assets, totalSupply.assets);
        }
    }

    /// @inheritdoc AltoBaseMarket
    /// @dev Full share repayment can leave virtual-share rounding dust in global borrowed assets. The account's
    /// solvency follows its borrow shares, so that residual does not lock a debt-free account's collateral.
    function _isSolvent(address _user) internal view override returns (bool) {
        if (position[_user].borrowShares == 0) {
            return true;
        }

        uint256 collateralValue = _collateralValue(_user);
        uint256 maxBorrowValue = collateralValue.multiplyWithPrecision(maxLtv);
        return maxBorrowValue >= _borrowValue(_user);
    }

    /// @dev Returns true if the user's position has breached the foreclosure LTV.
    function _isLiquidatable(address _user) internal view returns (bool) {
        uint256 collateralValue = _collateralValue(_user);
        uint256 foreclosureBorrowValue = collateralValue.multiplyWithPrecision(foreclosureLtv);
        return _borrowValue(_user) > foreclosureBorrowValue;
    }

    /// @dev Disabled because this market supports governance foreclosure instead of public liquidation.
    function _liquidate(address, bytes calldata, bytes memory)
        internal
        pure
        override
        returns (uint256, uint256, uint256)
    {
        revert AltoCreditMarketNonLiquidatable();
    }

    /// @inheritdoc AltoBaseMarket
    function _sendBorrowToken(address from, address to, uint256 amount) internal override {
        if (from == address(this)) {
            IMintableERC20(borrowToken).mint(to, amount);
        } else {
            IMintableERC20(borrowToken).burn(from, amount);
        }
    }

    /// @dev Reverts when the supplied address is zero.
    function _requireNonZeroAddress(address account) internal pure {
        if (account == address(0)) {
            revert AltoCreditMarketZeroAddress();
        }
    }

    /// @dev Validates and stores the Convex custody and reward configuration.
    function _initializeConvex(ConvexCreditLineInitParams memory _initParams) private {
        uint256 tokenCount = _initParams.rewardTokens.length;
        (address depositToken, address rewardPool) = AltoConvexCreditLineLib.validateConvexInitialization(
            _initParams.convexBooster, _initParams.convexPoolId, collateralToken, _initParams.rewardRecipient
        );

        convexBooster = _initParams.convexBooster;
        convexPoolId = _initParams.convexPoolId;
        convexRewardPool = rewardPool;
        rewardRecipient = _initParams.rewardRecipient;
        convexActive = true;

        for (uint256 i = 0; i < tokenCount; ++i) {
            _addRewardToken(_initParams.rewardTokens[i]);
        }

        if (!isRewardToken[IConvexRewardPool(rewardPool).rewardToken()]) {
            revert AltoCreditMarketInvalidInput();
        }

        emit ConvexConfigured(
            _initParams.convexBooster, _initParams.convexPoolId, rewardPool, depositToken, _initParams.rewardRecipient
        );
    }

    /// @dev Adds a validated token to the reward forwarding list.
    function _addRewardToken(address _token) private {
        AltoConvexCreditLineLib.validateRewardTokenAddition(
            rewardToken.length, isRewardToken[_token], _token, collateralToken, borrowToken, convexRewardPool
        );

        isRewardToken[_token] = true;
        rewardToken.push(_token);
        emit RewardTokenAdded(_token);
    }

    /// @dev Returns the user's collateral value in borrow-token asset units.
    function _collateralValue(address _user) private view returns (uint256) {
        uint256 collateralPrice = ILendingOracle(oracle).getPrice();
        if (collateralPrice == 0) {
            revert AltoCreditMarketInvalidOraclePrice();
        }

        uint256 collateralAssets = uint256(position[_user].collateralAssets);
        return collateralAssets.divideWithRounding(collateralPrice, LENDING_ORACLE_PRICE_PRECISION, false);
    }

    /// @dev Returns the user's borrow value in borrow-token asset units.
    function _borrowValue(address _user) private view returns (uint256) {
        uint256 borrowShares = uint256(position[_user].borrowShares);
        return borrowShares.convertToAssetsUp(totalBorrowed.assets, totalBorrowed.shares);
    }

    /// @dev Reverts unless the account is the configured credit account.
    function _requireCreditAccount(address account) private view {
        if (account != creditAccount) {
            revert AltoCreditMarketUnauthorizedAccount();
        }
    }
}
