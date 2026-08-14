// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {AltoOwnable2StepUpgradeable} from "@alto/utils/AltoOwnable2StepUpgradeable.sol";
import {AuthUpgradeable} from "@alto/utils/AuthUpgradeable.sol";
import {Pausable, IPausable} from "@alto/utils/Pausable.sol";

import {FROZEN_TYPE, PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {FixedPointMath, MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";
import {ILendingOracle, LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";
import {Uint128Converter} from "@alto/lending/libraries/Uint128Converter.sol";

import {CreditMarketInitParams, IAltoCreditMarket} from "@alto/lending/interfaces/IAltoCreditMarket.sol";
import {IIrm, IRMType} from "@alto/lending/interfaces/IIrm.sol";
import {Balance, IMarketBase, IMarketStaticTypes, MarketType, Position} from "@alto/lending/interfaces/IMarket.sol";
import {IMintableERC20} from "@alto/lending/interfaces/IMintableERC20.sol";

/// @title Alto Credit Market Base
///
/// @author Alto
///
/// @custom:contact security@altofoundation.org
///
/// @notice Accounting base for a single-account mint credit facility with
/// oracle-based borrowing limits and permissioned full foreclosure.
///
/// @dev `totalSupply.assets` is synthetic credit capacity, not lender-supplied
/// liquidity.
///
/// @dev The facility deposit is a draw condition and remains locked while
/// debt shares exist. Public liquidation remains unsupported; governance may
/// seize the full deposit and close the debt only after the foreclosure LTV is
/// breached.
///
/// @dev Derived contracts implement custody through `_receiveCollateral` and
/// `_sendCollateral`.
abstract contract AltoCreditMarketBase is
    Initializable,
    UUPSUpgradeable,
    AltoOwnable2StepUpgradeable,
    AuthUpgradeable,
    Pausable,
    ReentrancyGuardUpgradeable,
    IAltoCreditMarket
{
    // ========================================================================
    // Type Declarations
    // ========================================================================

    using FixedPointMath for uint256;
    using AssetShareConversionMath for uint256;
    using Uint128Converter for uint256;

    // ========================================================================
    // State
    // ========================================================================

    /// @dev Static market discriminator exposed through `MARKET_TYPE()`.
    MarketType private s_marketType;

    /// @dev Token minted on draws and burned on repayments.
    address private s_borrowToken;

    /// @dev Token used as the facility deposit.
    address private s_collateralToken;

    /// @dev Synthetic supply balance whose asset component stores the credit
    /// limit.
    Balance private s_totalSupply;

    /// @dev Aggregate debt balance shared by the sole credit account.
    Balance private s_totalBorrowed;

    /// @dev Standard market position storage; only the configured credit
    /// account may hold a position.
    mapping(address => Position) private s_position;

    /// @dev Fixed-rate interest rate model bound to this market.
    address private s_irm;

    /// @dev Oracle used to value collateral in borrow-token units.
    address private s_oracle;

    /// @dev Recipient of claimed opening fees and accrued interest.
    address private s_feeRecipient;

    /// @dev Sole account permitted to own collateral and borrow shares.
    address private s_creditAccount;

    /// @dev Maximum permitted post-draw LTV, expressed with 1e18 precision.
    uint256 private s_maxLtv;

    /// @dev LTV above which governance may fully foreclose, expressed with 1e18
    /// precision.
    uint256 private s_foreclosureLtv;

    /// @dev Opening fees and accrued interest not yet minted to the fee recipient.
    uint128 private s_claimableFeesAssets;

    /// @dev Fee added to each draw, expressed with 1e18 precision.
    uint256 private s_borrowOpeningFee;

    /// @dev Reserved storage for upgrades to the credit accounting base.
    uint256[40] private __gap_credit_base;

    // ========================================================================
    // Initialization
    // ========================================================================

    /// @notice Initializes credit accounting, risk parameters, ownership, and
    /// pause authority.
    ///
    /// @param _params Credit-market initialization parameters.
    ///
    /// @dev May only be called during initialization of a derived upgradeable
    /// contract.
    ///
    /// @dev The IRM must report `IRMType.FIXED_RATE` and is bound to the proxy
    /// through `setMarket`.
    function __AltoCreditMarketBase_init(CreditMarketInitParams memory _params) internal onlyInitializing {
        _assertNonZero(_params.borrowToken);
        _assertNonZero(_params.collateralToken);
        _assertNonZero(_params.irm);
        _assertNonZero(_params.owner);
        _assertNonZero(_params.oracle);
        _assertNonZero(_params.creditAccount);
        _assertNonZero(_params.feeRecipient);

        _assertNonZero(_params.creditLimit);

        _assert(_params.borrowToken != _params.collateralToken);
        _assert(_params.initialBorrowOpeningFee <= MATH_PRECISION);
        _assert(_params.maxLtv < _params.foreclosureLtv);
        _assert(_params.foreclosureLtv <= MATH_PRECISION);

        _assert(_params.creditLimit <= type(uint128).max);
        _assert(IIrm(_params.irm).IRM_TYPE() == IRMType.FIXED_RATE);

        __UUPSUpgradeable_init();
        __Ownable_init(_params.owner);
        __Auth_init();
        __ReentrancyGuard_init();

        s_marketType = MarketType.CREDIT_MINT;
        s_borrowToken = _params.borrowToken;
        s_collateralToken = _params.collateralToken;
        s_oracle = _params.oracle;
        s_irm = _params.irm;
        s_feeRecipient = _params.feeRecipient;
        s_creditAccount = _params.creditAccount;
        s_maxLtv = _params.maxLtv;
        s_foreclosureLtv = _params.foreclosureLtv;
        s_borrowOpeningFee = _params.initialBorrowOpeningFee;
        s_totalSupply.assets = _params.creditLimit.toUint128();

        IIrm(_params.irm).setMarket(address(this));

        _setPauser(_params.owner, PAUSE_TYPE, true);
        _setPauser(_params.owner, FROZEN_TYPE, true);

        emit SetIrm(address(0), _params.irm);
        emit SetOracle(address(0), _params.oracle);
        emit SetMaxLtv(0, _params.maxLtv);
        emit SetForeclosureLtv(0, _params.foreclosureLtv);
        emit SetFeeRecipient(address(0), _params.feeRecipient);
        emit SetCreditLimit(0, _params.creditLimit);
        emit SetBorrowOpeningFee(0, _params.initialBorrowOpeningFee);
    }

    // ========================================================================
    // Functions - Market State
    // ========================================================================

    /// @inheritdoc IMarketBase
    function MARKET_TYPE() public view returns (MarketType) {
        return s_marketType;
    }

    /// @inheritdoc IMarketBase
    function borrowToken() public view returns (address) {
        return s_borrowToken;
    }

    /// @inheritdoc IMarketBase
    function collateralToken() public view returns (address) {
        return s_collateralToken;
    }

    /// @inheritdoc IMarketStaticTypes
    function totalSupply() public view returns (uint128 assets, uint128 shares) {
        return (s_totalSupply.assets, s_totalSupply.shares);
    }

    /// @inheritdoc IMarketStaticTypes
    function totalBorrowed() public view returns (uint128 assets, uint128 shares) {
        return (s_totalBorrowed.assets, s_totalBorrowed.shares);
    }

    /// @inheritdoc IMarketStaticTypes
    ///
    /// @dev Only the configured credit account may have nonzero borrow shares
    /// or collateral assets. Supply shares are always zero because supplying
    /// borrow tokens is unsupported.
    function position(address _account)
        public
        view
        returns (uint128 supplyShares, uint128 borrowShares, uint128 collateralAssets)
    {
        Position storage accountPosition = s_position[_account];
        return (accountPosition.supplyShares, accountPosition.borrowShares, accountPosition.collateralAssets);
    }

    /// @inheritdoc IMarketBase
    function irm() public view returns (address) {
        return s_irm;
    }

    /// @inheritdoc IMarketBase
    function oracle() public view returns (address) {
        return s_oracle;
    }

    /// @inheritdoc IMarketBase
    function maxLtv() public view returns (uint256) {
        return s_maxLtv;
    }

    /// @inheritdoc IMarketBase
    function feeRecipient() public view returns (address) {
        return s_feeRecipient;
    }

    /// @inheritdoc IAltoCreditMarket
    function creditAccount() public view returns (address) {
        return s_creditAccount;
    }

    /// @inheritdoc IAltoCreditMarket
    function foreclosureLtv() public view returns (uint256) {
        return s_foreclosureLtv;
    }

    /// @inheritdoc IAltoCreditMarket
    function claimableFeesAssets() public view returns (uint128) {
        return s_claimableFeesAssets;
    }

    // ========================================================================
    // Functions - Credit Configuration
    // ========================================================================

    /// @inheritdoc IAltoCreditMarket
    function setCreditLimit(uint256 _newCreditLimit) external nonReentrant onlyOwner {
        _assertNonZero(_newCreditLimit);
        _assert(_newCreditLimit <= type(uint128).max);

        if (!paused[PAUSE_TYPE]) _accrueInterest();
        _assert(_newCreditLimit >= s_totalBorrowed.assets);

        uint256 oldCreditLimit = s_totalSupply.assets;
        s_totalSupply.assets = _newCreditLimit.toUint128();
        emit SetCreditLimit(oldCreditLimit, _newCreditLimit);
    }

    /// @inheritdoc IMarketBase
    function setOracle(address _newOracle) external onlyOwner {
        _assertNonZero(_newOracle);

        emit SetOracle(s_oracle, _newOracle);
        s_oracle = _newOracle;
    }

    /// @inheritdoc IMarketBase
    function setMaxLtv(uint256 _newMaxLtv) external onlyOwner {
        _assert(_newMaxLtv < s_foreclosureLtv);

        emit SetMaxLtv(s_maxLtv, _newMaxLtv);
        s_maxLtv = _newMaxLtv;
    }

    /// @inheritdoc IAltoCreditMarket
    function setForeclosureLtv(uint256 _newForeclosureLtv) external onlyOwner {
        _assert(_newForeclosureLtv > s_maxLtv);
        _assert(_newForeclosureLtv <= MATH_PRECISION);

        emit SetForeclosureLtv(s_foreclosureLtv, _newForeclosureLtv);
        s_foreclosureLtv = _newForeclosureLtv;
    }

    /// @inheritdoc IAltoCreditMarket
    function setBorrowOpeningFee(uint256 _newBorrowOpeningFee) external onlyOwner {
        _assert(_newBorrowOpeningFee <= MATH_PRECISION);

        emit SetBorrowOpeningFee(s_borrowOpeningFee, _newBorrowOpeningFee);
        s_borrowOpeningFee = _newBorrowOpeningFee;
    }

    /// @inheritdoc IMarketBase
    function setIrm(address _newIrm, bool _skipAccrueInterest) external nonReentrant onlyOwner {
        _assertNonZero(_newIrm);
        _assert(_newIrm != s_irm);
        _assert(IIrm(_newIrm).IRM_TYPE() == IRMType.FIXED_RATE);

        if (!paused[PAUSE_TYPE] && !_skipAccrueInterest) _accrueInterest();

        emit SetIrm(s_irm, _newIrm);
        s_irm = _newIrm;
        IIrm(_newIrm).setMarket(address(this));
    }

    /// @inheritdoc IMarketBase
    function setFeeRecipient(address _newFeeRecipient) external onlyOwner {
        _assertNonZero(_newFeeRecipient);

        emit SetFeeRecipient(s_feeRecipient, _newFeeRecipient);
        s_feeRecipient = _newFeeRecipient;
    }

    /// @inheritdoc IPausable
    function setPauser(address _pauser, bytes32 _pauseType, bool _status)
        external
        override(IPausable, Pausable)
        onlyOwner
    {
        _assertNonZero(_pauser);
        _assert(_pauseType == PAUSE_TYPE || _pauseType == FROZEN_TYPE);
        _setPauser(_pauser, _pauseType, _status);
    }

    /// @inheritdoc IAltoCreditMarket
    function creditLimit() public view returns (uint256) {
        return s_totalSupply.assets;
    }

    /// @inheritdoc IMarketBase
    function borrowOpeningFee() public view returns (uint256) {
        return s_borrowOpeningFee;
    }

    // ========================================================================
    // Functions - Facility Collateral
    // ========================================================================

    /// @inheritdoc IMarketBase
    function addCollateral(uint256 _assets, address _onBehalf)
        external
        nonReentrant
        whenNotPaused
        whenNotFrozen
        returns (uint256)
    {
        _assertNonZero(_assets);
        _assertCreditAccount(_onBehalf);

        s_position[_onBehalf].collateralAssets += _assets.toUint128();
        _receiveCollateral(_assets);

        emit AddCollateral(msg.sender, _onBehalf, _assets);
        return _assets;
    }

    /// @inheritdoc IMarketBase
    function removeCollateral(uint256 _assets, address _onBehalf, address _receiver, bytes calldata _swapParams)
        external
        nonReentrant
        whenNotPaused
        returns (uint256)
    {
        _assertNonZero(_assets);
        _assertNonZero(_receiver);

        if (_swapParams.length != 0) {
            revert AltoCreditMarket__CallbacksUnsupported();
        }

        _assertCreditAccount(_onBehalf);
        if (!_isSenderAuthorized(_onBehalf)) {
            revert AltoCreditMarket__UnauthorizedAccount();
        }

        _accrueInterest();
        if (s_position[_onBehalf].borrowShares != 0) {
            revert AltoCreditMarket__OutstandingDebt();
        }

        s_position[_onBehalf].collateralAssets -= _assets.toUint128();
        _sendCollateral(_receiver, _assets);

        emit RemoveCollateral(msg.sender, _onBehalf, _receiver, _assets);
        return _assets;
    }

    // ========================================================================
    // Functions - Borrowing and Repayment
    // ========================================================================

    /// @inheritdoc IMarketBase
    function borrow(uint256 _assets, uint256 _shares, address _onBehalf, address _receiver, bytes calldata _swapParams)
        external
        nonReentrant
        whenNotPaused
        whenNotFrozen
        returns (uint256, uint256, uint256)
    {
        _assert(_onlyOneZero(_assets, _shares));
        _assertNonZero(_receiver);
        _assertCreditAccount(_onBehalf);

        if (!_isSenderAuthorized(_onBehalf)) {
            revert AltoCreditMarket__UnauthorizedAccount();
        }

        if (_swapParams.length != 0) {
            revert AltoCreditMarket__CallbacksUnsupported();
        }

        _accrueInterest();

        uint256 openingFeeAssets;

        if (_assets == 0) {
            // calculate opening fee from shares
            uint256 openingFeeShares = _shares.multiplyWithPrecisionUp(s_borrowOpeningFee);
            openingFeeAssets = openingFeeShares.convertToAssetsUp(s_totalBorrowed.assets, s_totalBorrowed.shares);
            _shares += openingFeeShares;

            _assets = _shares.convertToAssetsDown(s_totalBorrowed.assets, s_totalBorrowed.shares);
        } else {
            // calculate opening fee from assets
            openingFeeAssets = _assets.multiplyWithPrecisionUp(s_borrowOpeningFee);
            _assets += openingFeeAssets;

            _shares = _assets.convertToSharesUp(s_totalBorrowed.assets, s_totalBorrowed.shares);
        }

        s_totalBorrowed.assets += _assets.toUint128();
        s_totalBorrowed.shares += _shares.toUint128();

        if (s_totalBorrowed.assets > s_totalSupply.assets) {
            revert AltoCreditMarket__CreditLimitExceeded();
        }

        s_position[_onBehalf].borrowShares += _shares.toUint128();

        if (openingFeeAssets != 0) {
            s_claimableFeesAssets += openingFeeAssets.toUint128();
        }

        if (!_isSolvent(_onBehalf)) {
            revert AltoCreditMarket__BorrowingTooMuch();
        }

        uint256 assetsToSend = _assets - openingFeeAssets;
        IMintableERC20(s_borrowToken).mint(_receiver, assetsToSend);

        emit Borrow(msg.sender, _onBehalf, _receiver, assetsToSend, _shares, openingFeeAssets, 0);
        return (_assets, _shares, openingFeeAssets);
    }

    /// @inheritdoc IMarketBase
    function repay(uint256 _assets, uint256 _shares, address _onBehalf)
        external
        nonReentrant
        whenNotPaused
        returns (uint256, uint256)
    {
        _assert(_onlyOneZero(_assets, _shares));
        _assertCreditAccount(_onBehalf);
        _accrueInterest();

        if (_assets == 0) {
            _assets = _shares.convertToAssetsUp(s_totalBorrowed.assets, s_totalBorrowed.shares);
        } else {
            _shares = _assets.convertToSharesDown(s_totalBorrowed.assets, s_totalBorrowed.shares);
        }

        s_totalBorrowed.assets -= _assets.toUint128();
        s_totalBorrowed.shares -= _shares.toUint128();
        s_position[_onBehalf].borrowShares -= _shares.toUint128();

        IMintableERC20(s_borrowToken).burn(msg.sender, _assets);
        emit Repay(msg.sender, _onBehalf, _assets, _shares);
        return (_assets, _shares);
    }

    // ========================================================================
    // Functions - Interest Management
    // ========================================================================

    /// @inheritdoc IMarketBase
    function accrueInterest() external nonReentrant whenNotPaused {
        _accrueInterest();
    }

    /// @inheritdoc IAltoCreditMarket
    function claimInterest(uint256 _interest) external nonReentrant whenNotPaused returns (uint256) {
        _assert(_interest <= s_claimableFeesAssets);
        _assertNonZero(s_feeRecipient);

        if (msg.sender != owner() && msg.sender != s_feeRecipient) {
            revert AltoCreditMarket__UnauthorizedAccount();
        }

        if (_interest == 0) {
            _interest = s_claimableFeesAssets;
        }

        s_claimableFeesAssets -= _interest.toUint128();
        if (_interest != 0) {
            IMintableERC20(s_borrowToken).mint(s_feeRecipient, _interest);
        }

        emit InterestClaimed(s_feeRecipient, _interest);
        return _interest;
    }

    /// @notice Checkpoints the fixed-rate IRM and adds newly accrued interest to
    /// debt and claimable protocol fees.
    function _accrueInterest() internal {
        (uint256 interest, uint256 borrowRate) =
            IIrm(s_irm).updateInterestRate(s_totalSupply.assets, s_totalBorrowed.assets);

        if (interest != 0) {
            s_totalBorrowed.assets += interest.toUint128();
            s_claimableFeesAssets += interest.toUint128();
        }

        emit AccrueInterest(borrowRate, interest, s_totalBorrowed.assets, s_totalSupply.assets);
    }

    // ========================================================================
    // Functions - Unsupported Operations
    // ========================================================================

    /// @inheritdoc IMarketBase
    ///
    /// @dev Callbacks are categorically unsupported by this market.
    function authorizedCallbacks(address) external pure returns (bool) {
        return false;
    }

    /// @inheritdoc IMarketBase
    ///
    /// @dev This market has no liquidation engine because public liquidation is
    /// unsupported.
    function liquidationEngine() external pure returns (address) {
        return address(0);
    }

    /// @inheritdoc IMarketBase
    ///
    /// @dev Always reverts because this market has no liquidation engine.
    function setLiquidationEngine(address) external pure {
        revert AltoCreditMarket__UnsupportedOperation();
    }

    /// @inheritdoc IMarketBase
    ///
    /// @dev Always reverts because callback execution is unsupported.
    function setAuthorizedCallback(address, bool) external pure {
        revert AltoCreditMarket__UnsupportedOperation();
    }

    /// @inheritdoc IMarketBase
    ///
    /// @dev Always reverts because the facility has synthetic capacity rather
    /// than lender supply.
    function addSupply(uint256, uint256, address) external pure returns (uint256, uint256) {
        revert AltoCreditMarket__UnsupportedOperation();
    }

    /// @inheritdoc IMarketBase
    ///
    /// @dev Always reverts because the facility has no lender supply positions.
    function removeSupply(uint256, uint256, address, address) external pure returns (uint256, uint256) {
        revert AltoCreditMarket__UnsupportedOperation();
    }

    /// @inheritdoc IMarketBase
    ///
    /// @dev Always reverts. This market uses only owner-triggered full
    /// foreclosure through `governanceLiquidate`.
    function liquidate(address, bytes calldata, bytes calldata)
        external
        pure
        override
        returns (uint256, uint256, uint256)
    {
        revert AltoCreditMarket__NonLiquidatable();
    }

    /// @inheritdoc IMarketBase
    ///
    /// @dev Foreclosure is available only for the configured credit account
    /// after debt strictly exceeds the foreclosure LTV. It clears all market
    /// debt and accounted collateral, then sends the entire facility deposit to
    // the owner. Previously accrued claimable fees remain claimable.
    function governanceLiquidate(address _borrower)
        external
        nonReentrant
        onlyOwner
        returns (uint256 collateralAmount, uint256 badDebtAmount)
    {
        _assertCreditAccount(_borrower);
        _accrueInterest();

        if (!_isForeclosable(_borrower)) {
            revert AltoCreditMarket__PositionNotForeclosable();
        }

        Position storage borrowerPosition = s_position[_borrower];
        collateralAmount = borrowerPosition.collateralAssets;
        uint128 badDebtShares = borrowerPosition.borrowShares;
        badDebtAmount = s_totalBorrowed.assets;

        s_totalBorrowed.assets = 0;
        s_totalBorrowed.shares = 0;
        borrowerPosition.borrowShares = 0;
        borrowerPosition.collateralAssets = 0;

        if (collateralAmount != 0) {
            _sendCollateral(msg.sender, collateralAmount);
        }

        emit GovernanceLiquidation(_borrower, msg.sender, collateralAmount, badDebtAmount, badDebtShares);
    }

    // ========================================================================
    // Functions - Internal Hooks
    // ========================================================================

    /// @notice Receives and places newly accounted collateral into
    /// derived-contract custody.
    ///
    /// @param _assets Amount of collateral to receive in collateral-token units.
    function _receiveCollateral(uint256 _assets) internal virtual;

    /// @notice Releases collateral from derived-contract custody and transfers
    /// it to a receiver.
    ///
    /// @param _receiver    Account that must receive the collateral.
    /// @param _assets      Amount of collateral to release in collateral-token units.
    function _sendCollateral(address _receiver, uint256 _assets) internal virtual;

    // ========================================================================
    // Functions - Private and Internal Helpers
    // ========================================================================

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address) internal override onlyOwner {}

    /// @notice Checks that exactly one of an asset amount and a share amount is
    /// nonzero.
    ///
    /// @param x First amount to test.
    /// @param y Second amount to test.
    ///
    /// @return True when exactly one input is zero.
    function _onlyOneZero(uint256 x, uint256 y) internal pure returns (bool) {
        return (x == 0 && y != 0) || (x != 0 && y == 0);
    }

    /// @notice Tests whether an account's conservatively valued debt is within
    /// the maximum LTV.
    ///
    /// @param _account Account whose position is tested.
    ///
    /// @return True when debt value does not exceed collateral value multiplied
    /// by `maxLtv`.
    function _isSolvent(address _account) internal view returns (bool) {
        uint256 collateralValue = _collateralValue(_account);
        uint256 maxBorrowValue = collateralValue.multiplyWithPrecision(s_maxLtv);
        return maxBorrowValue >= _borrowValue(_account);
    }

    /// @notice Tests whether an account has strictly breached the governance
    /// foreclosure threshold.
    ///
    /// @param _account Account whose position is tested.
    ///
    /// @return True when debt value is greater than collateral value multiplied
    /// by `foreclosureLtv`.
    function _isForeclosable(address _account) internal view returns (bool) {
        uint256 collateralValue = _collateralValue(_account);
        uint256 foreclosureBorrowValue = collateralValue.multiplyWithPrecision(s_foreclosureLtv);
        return _borrowValue(_account) > foreclosureBorrowValue;
    }

    /// @notice Values an account's collateral in borrow-token asset units.
    ///
    /// @param _account Account whose collateral is valued.
    ///
    /// @return Collateral value denominated in borrow-token asset units.
    ///
    /// @dev Uses Alto's 1e36 lending-oracle convention and rounds down so
    /// collateral is not overstated.
    function _collateralValue(address _account) private view returns (uint256) {
        uint256 collateralPrice = ILendingOracle(s_oracle).getPrice();
        if (collateralPrice == 0) revert AltoCreditMarket__InvalidOraclePrice();

        uint256 collateralAssets = uint256(s_position[_account].collateralAssets);
        return collateralAssets.divideWithRounding(collateralPrice, LENDING_ORACLE_PRICE_PRECISION, false);
    }

    /// @notice Converts an account's borrow shares into current debt assets.
    ///
    /// @param _account Account whose debt is valued.
    ///
    /// @return Debt denominated in borrow-token asset units.
    ///
    /// @dev Rounds up so debt is never understated during solvency and
    /// foreclosure checks.
    function _borrowValue(address _account) private view returns (uint256) {
        uint256 borrowShares = uint256(s_position[_account].borrowShares);
        return borrowShares.convertToAssetsUp(s_totalBorrowed.assets, s_totalBorrowed.shares);
    }

    /// @notice Synchronizes interest accounting and the IRM when the full-pause
    /// state changes.
    ///
    /// @param _pauseType   Pause domain being changed.
    /// @param _paused      New pause status.
    ///
    /// @dev Freeze-state changes do not notify the IRM.
    function _onPause(bytes32 _pauseType, bool _paused) internal override {
        if (_pauseType != PAUSE_TYPE) return;

        if (_paused) {
            _accrueInterest();
            IIrm(s_irm).onMarketPause(true);
        } else {
            IIrm(s_irm).onMarketPause(false);
        }
    }

    /// @notice Restricts an operation to periods when the market is not paused.
    modifier whenNotPaused() {
        _assertNotPaused();
        _;
    }

    /// @notice Restricts an operation to periods when the market is not frozen.
    modifier whenNotFrozen() {
        _assertNotFrozen();
        _;
    }

    /// @dev Reverts when the market's full-pause type is active.
    function _assertNotPaused() private view {
        if (paused[PAUSE_TYPE]) revert IPausable.IsPaused(PAUSE_TYPE);
    }

    /// @dev Reverts when the market's freeze type is active.
    function _assertNotFrozen() private view {
        if (paused[FROZEN_TYPE]) revert IPausable.IsPaused(FROZEN_TYPE);
    }

    /// @dev Reverts when `x` is the zero address.
    ///
    /// @param x Address to validate.
    function _assertNonZero(address x) internal pure {
        if (x == address(0)) revert AltoCreditMarket__ZeroAddress();
    }

    /// @dev Reverts when `x` is zero.
    ///
    /// @param x Numeric configuration value to validate.
    function _assertNonZero(uint256 x) internal pure {
        if (x == 0) revert AltoCreditMarket__InvalidInput();
    }

    /// @dev Reverts unless `x` is the exact configured credit account.
    ///
    /// @param x Account to validate.
    function _assertCreditAccount(address x) internal view {
        if (x != s_creditAccount) revert AltoCreditMarket__UnauthorizedAccount();
    }

    /// @dev Reverts with the market's generic invalid-input error when `predicate`
    /// is false.
    ///
    /// @param predicate Condition that must hold.
    function _assert(bool predicate) internal pure {
        if (!predicate) revert AltoCreditMarket__InvalidInput();
    }
}
