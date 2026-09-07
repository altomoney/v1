// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {AltoOwnable2StepUpgradeable} from "@alto/utils/AltoOwnable2StepUpgradeable.sol";
import {AuthUpgradeable} from "@alto/utils/AuthUpgradeable.sol";
import {Pausable, IPausable} from "@alto/utils/Pausable.sol";

import {FROZEN_TYPE, PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {FixedPointMath, MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";
import {ILendingOracle, LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {AssetShareConversionMath} from "../libraries/AssetShareConversionMath.sol";
import {Uint128Converter} from "../libraries/Uint128Converter.sol";

import {CreditMarketInitParams, IAltoCreditMarket} from "../interfaces/IAltoCreditMarket.sol";
import {IIrm, IRMType} from "../interfaces/IIrm.sol";
import {Balance, IMarketBase, IMarketStaticTypes, MarketType, Position} from "../interfaces/IMarket.sol";
import {IMintableERC20} from "../interfaces/IMintableERC20.sol";

/// @title Alto Credit Market Base
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice An Isolated Credit Market
/// @dev `totalSupply.assets` represents synthetic credit capacity rather than lender-supplied liquidity.
/// Derived contracts implement collateral custody through `_receiveCollateral` and `_sendCollateral`.
abstract contract AltoCreditMarketBase is
    Initializable,
    UUPSUpgradeable,
    AltoOwnable2StepUpgradeable,
    IAltoCreditMarket,
    AuthUpgradeable,
    Pausable,
    ReentrancyGuardUpgradeable
{
    using FixedPointMath for uint256;
    using AssetShareConversionMath for uint256;
    using Uint128Converter for uint256;

    /// @inheritdoc IMarketBase
    MarketType public MARKET_TYPE;

    /// @inheritdoc IMarketBase
    address public borrowToken;

    /// @inheritdoc IMarketBase
    address public collateralToken;

    /// @inheritdoc IMarketStaticTypes
    Balance public totalSupply;

    /// @inheritdoc IMarketStaticTypes
    Balance public totalBorrowed;

    /// @inheritdoc IMarketStaticTypes
    mapping(address => Position) public position;

    /// @inheritdoc IMarketBase
    address public irm;

    /// @inheritdoc IMarketBase
    address public oracle;

    /// @inheritdoc IMarketBase
    address public feeRecipient;

    /// @inheritdoc IAltoCreditMarket
    address public creditAccount;

    /// @inheritdoc IMarketBase
    uint256 public maxLtv;

    /// @inheritdoc IAltoCreditMarket
    uint256 public foreclosureLtv;

    /// @inheritdoc IAltoCreditMarket
    uint128 public claimableFeesAssets;

    /// @notice The borrow opening fee in MATH_PRECISION
    uint256 private _borrowOpeningFee;

    /// upgrade gap
    uint256[40] private __gap_base;

    /// @notice Initializes the credit market
    /// @param _initParams The credit market initialization parameters
    /// @dev The IRM must be a fixed-rate IRM
    function __AltoCreditMarketBase_init(CreditMarketInitParams memory _initParams) internal onlyInitializing {
        if (
            _initParams.borrowToken == address(0) || _initParams.collateralToken == address(0)
                || _initParams.irm == address(0) || _initParams.owner == address(0) || _initParams.oracle == address(0)
                || _initParams.creditAccount == address(0) || _initParams.feeRecipient == address(0)
        ) {
            revert AltoCreditMarketZeroAddress();
        }
        if (
            _initParams.creditLimit == 0 || _initParams.borrowToken == _initParams.collateralToken
                || _initParams.initialBorrowOpeningFee > MATH_PRECISION || _initParams.maxLtv >= _initParams.foreclosureLtv
                || _initParams.foreclosureLtv > MATH_PRECISION || _initParams.creditLimit > type(uint128).max
                || IIrm(_initParams.irm).IRM_TYPE() != IRMType.FIXED_RATE
        ) {
            revert AltoCreditMarketInvalidInput();
        }

        __UUPSUpgradeable_init();
        __Ownable_init(_initParams.owner);
        __Auth_init();
        __ReentrancyGuard_init();

        MARKET_TYPE = MarketType.CREDIT_MINT;
        borrowToken = _initParams.borrowToken;
        collateralToken = _initParams.collateralToken;

        irm = _initParams.irm;
        emit SetIrm(address(0), _initParams.irm);

        oracle = _initParams.oracle;
        emit SetOracle(address(0), _initParams.oracle);

        maxLtv = _initParams.maxLtv;
        emit SetMaxLtv(0, _initParams.maxLtv);

        foreclosureLtv = _initParams.foreclosureLtv;
        emit SetForeclosureLtv(0, _initParams.foreclosureLtv);

        feeRecipient = _initParams.feeRecipient;
        emit SetFeeRecipient(address(0), _initParams.feeRecipient);

        creditAccount = _initParams.creditAccount;

        totalSupply.assets = _initParams.creditLimit.toUint128();
        emit SetCreditLimit(0, _initParams.creditLimit);

        _borrowOpeningFee = _initParams.initialBorrowOpeningFee;
        emit SetBorrowOpeningFee(0, _initParams.initialBorrowOpeningFee);

        IIrm(_initParams.irm).setMarket(address(this));

        _setPauser(_initParams.owner, PAUSE_TYPE, true);
        _setPauser(_initParams.owner, FROZEN_TYPE, true);
    }

    /// @inheritdoc IAltoCreditMarket
    function setCreditLimit(uint256 _newCreditLimit) external nonReentrant onlyOwner {
        if (_newCreditLimit == 0 || _newCreditLimit > type(uint128).max) {
            revert AltoCreditMarketInvalidInput();
        }

        if (!paused[PAUSE_TYPE]) {
            _accrueInterest();
        }
        if (_newCreditLimit < totalBorrowed.assets) {
            revert AltoCreditMarketInvalidInput();
        }

        uint256 oldCreditLimit = totalSupply.assets;
        totalSupply.assets = _newCreditLimit.toUint128();
        emit SetCreditLimit(oldCreditLimit, _newCreditLimit);
    }

    /// @inheritdoc IMarketBase
    function setOracle(address _oracle) external onlyOwner {
        if (_oracle == address(0)) {
            revert AltoCreditMarketZeroAddress();
        }

        emit SetOracle(oracle, _oracle);
        oracle = _oracle;
    }

    /// @inheritdoc IMarketBase
    function setMaxLtv(uint256 _maxLtv) external onlyOwner {
        if (_maxLtv >= foreclosureLtv) {
            revert AltoCreditMarketInvalidInput();
        }

        emit SetMaxLtv(maxLtv, _maxLtv);
        maxLtv = _maxLtv;
    }

    /// @inheritdoc IAltoCreditMarket
    function setForeclosureLtv(uint256 _newForeclosureLtv) external onlyOwner {
        if (_newForeclosureLtv <= maxLtv || _newForeclosureLtv > MATH_PRECISION) {
            revert AltoCreditMarketInvalidInput();
        }

        emit SetForeclosureLtv(foreclosureLtv, _newForeclosureLtv);
        foreclosureLtv = _newForeclosureLtv;
    }

    /// @inheritdoc IAltoCreditMarket
    function setBorrowOpeningFee(uint256 _newBorrowOpeningFee) external onlyOwner {
        if (_newBorrowOpeningFee > MATH_PRECISION) {
            revert AltoCreditMarketInvalidInput();
        }

        emit SetBorrowOpeningFee(_borrowOpeningFee, _newBorrowOpeningFee);
        _borrowOpeningFee = _newBorrowOpeningFee;
    }

    /// @inheritdoc IMarketBase
    /// @dev Unlike `AltoBaseMarket`, only a nonzero fixed-rate IRM can be set.
    function setIrm(address _irm, bool _skipAccrueInterest) external nonReentrant onlyOwner {
        if (_irm == address(0)) {
            revert AltoCreditMarketZeroAddress();
        }
        if (_irm == irm || IIrm(_irm).IRM_TYPE() != IRMType.FIXED_RATE) {
            revert AltoCreditMarketInvalidInput();
        }

        if (!paused[PAUSE_TYPE] && !_skipAccrueInterest) {
            _accrueInterest();
        }

        emit SetIrm(irm, _irm);
        irm = _irm;
        IIrm(_irm).setMarket(address(this));
    }

    /// @inheritdoc IMarketBase
    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        if (_feeRecipient == address(0)) {
            revert AltoCreditMarketZeroAddress();
        }

        emit SetFeeRecipient(feeRecipient, _feeRecipient);
        feeRecipient = _feeRecipient;
    }

    /// @inheritdoc IPausable
    function setPauser(address pauser, bytes32 pauseType, bool status)
        external
        override(IPausable, Pausable)
        onlyOwner
    {
        if (pauser == address(0)) {
            revert AltoCreditMarketZeroAddress();
        }
        if (pauseType != PAUSE_TYPE && pauseType != FROZEN_TYPE) {
            revert AltoCreditMarketInvalidInput();
        }
        _setPauser(pauser, pauseType, status);
    }

    /// @inheritdoc IAltoCreditMarket
    function creditLimit() public view returns (uint256) {
        return totalSupply.assets;
    }

    /// @inheritdoc IMarketBase
    function borrowOpeningFee() public view returns (uint256) {
        return _borrowOpeningFee;
    }

    /// @inheritdoc IMarketBase
    /// @dev Only `creditAccount` can receive collateral, which is placed into derived-contract custody.
    function addCollateral(uint256 assets, address onBehalf)
        external
        nonReentrant
        whenNotPaused
        whenNotFrozen
        returns (uint256)
    {
        if (assets == 0) {
            revert AltoCreditMarketInvalidInput();
        }
        if (onBehalf != creditAccount) {
            revert AltoCreditMarketUnauthorizedAccount();
        }

        position[onBehalf].collateralAssets += assets.toUint128();
        _receiveCollateral(assets);

        emit AddCollateral(msg.sender, onBehalf, assets);
        return assets;
    }

    /// @inheritdoc IMarketBase
    /// @dev Callbacks are unsupported and collateral can be removed only after `creditAccount` repays all debt.
    function removeCollateral(uint256 assets, address onBehalf, address receiver, bytes calldata swapParams)
        external
        nonReentrant
        whenNotPaused
        returns (uint256)
    {
        if (assets == 0) {
            revert AltoCreditMarketInvalidInput();
        }
        if (receiver == address(0)) {
            revert AltoCreditMarketZeroAddress();
        }

        if (swapParams.length != 0) {
            revert AltoCreditMarketCallbacksUnsupported();
        }

        if (onBehalf != creditAccount || !_isSenderAuthorized(onBehalf)) {
            revert AltoCreditMarketUnauthorizedAccount();
        }

        _accrueInterest();
        if (position[onBehalf].borrowShares != 0) {
            revert AltoCreditMarketOutstandingDebt();
        }

        position[onBehalf].collateralAssets -= assets.toUint128();
        _sendCollateral(receiver, assets);

        emit RemoveCollateral(msg.sender, onBehalf, receiver, assets);
        return assets;
    }

    /// @inheritdoc IMarketBase
    /// @dev Only `creditAccount` can borrow; tokens are minted subject to the credit limit and callbacks are unsupported.
    function borrow(uint256 assets, uint256 shares, address onBehalf, address receiver, bytes calldata swapParams)
        external
        nonReentrant
        whenNotPaused
        whenNotFrozen
        returns (uint256, uint256, uint256)
    {
        if (!_onlyOneZero(assets, shares)) {
            revert AltoCreditMarketInvalidInput();
        }
        if (receiver == address(0)) {
            revert AltoCreditMarketZeroAddress();
        }
        if (onBehalf != creditAccount) {
            revert AltoCreditMarketUnauthorizedAccount();
        }

        if (!_isSenderAuthorized(onBehalf)) {
            revert AltoCreditMarketUnauthorizedAccount();
        }

        if (swapParams.length != 0) {
            revert AltoCreditMarketCallbacksUnsupported();
        }

        _accrueInterest();

        uint256 openingFeeAssets;

        if (assets == 0) {
            // calculate opening fee from shares
            uint256 openingFeeShares = shares.multiplyWithPrecisionUp(_borrowOpeningFee);
            openingFeeAssets = openingFeeShares.convertToAssetsUp(totalBorrowed.assets, totalBorrowed.shares);
            shares += openingFeeShares;

            assets = shares.convertToAssetsDown(totalBorrowed.assets, totalBorrowed.shares);
        } else {
            // calculate opening fee from assets
            openingFeeAssets = assets.multiplyWithPrecisionUp(_borrowOpeningFee);
            assets += openingFeeAssets;

            shares = assets.convertToSharesUp(totalBorrowed.assets, totalBorrowed.shares);
        }

        totalBorrowed.assets += assets.toUint128();
        totalBorrowed.shares += shares.toUint128();

        if (totalBorrowed.assets > totalSupply.assets) {
            revert AltoCreditMarketCreditLimitExceeded();
        }

        position[onBehalf].borrowShares += shares.toUint128();

        if (openingFeeAssets != 0) {
            claimableFeesAssets += openingFeeAssets.toUint128();
        }

        if (!_isSolvent(onBehalf)) {
            revert AltoCreditMarketBorrowingTooMuch();
        }

        uint256 assetsToSend = assets - openingFeeAssets;
        _sendBorrowToken(address(this), receiver, assetsToSend);

        emit Borrow(msg.sender, onBehalf, receiver, assetsToSend, shares, openingFeeAssets, 0);
        return (assets, shares, openingFeeAssets);
    }

    /// @inheritdoc IMarketBase
    /// @dev Repayment is limited to `creditAccount` debt and burns the payer's borrow tokens.
    function repay(uint256 assets, uint256 shares, address onBehalf)
        external
        nonReentrant
        whenNotPaused
        returns (uint256, uint256)
    {
        if (!_onlyOneZero(assets, shares)) {
            revert AltoCreditMarketInvalidInput();
        }
        if (onBehalf != creditAccount) {
            revert AltoCreditMarketUnauthorizedAccount();
        }
        _accrueInterest();

        if (assets == 0) {
            assets = shares.convertToAssetsUp(totalBorrowed.assets, totalBorrowed.shares);
        } else {
            shares = assets.convertToSharesDown(totalBorrowed.assets, totalBorrowed.shares);
        }

        totalBorrowed.assets -= assets.toUint128();
        totalBorrowed.shares -= shares.toUint128();
        position[onBehalf].borrowShares -= shares.toUint128();

        _sendBorrowToken(msg.sender, address(this), assets);
        emit Repay(msg.sender, onBehalf, assets, shares);
        return (assets, shares);
    }

    /// @inheritdoc IMarketBase
    function accrueInterest() external nonReentrant whenNotPaused {
        _accrueInterest();
    }

    /// @inheritdoc IAltoCreditMarket
    function claimInterest(uint256 interest) external nonReentrant whenNotPaused returns (uint256) {
        if (interest > claimableFeesAssets) {
            revert AltoCreditMarketInvalidInput();
        }
        if (feeRecipient == address(0)) {
            revert AltoCreditMarketZeroAddress();
        }

        if (msg.sender != owner() && msg.sender != feeRecipient) {
            revert AltoCreditMarketUnauthorizedAccount();
        }

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

    /// @dev Accrues interest and adds it to the claimable fees.
    function _accrueInterest() internal {
        (uint256 interest, uint256 borrowRate) = IIrm(irm).updateInterestRate(totalSupply.assets, totalBorrowed.assets);

        if (interest != 0) {
            totalBorrowed.assets += interest.toUint128();
            claimableFeesAssets += interest.toUint128();
        }

        emit AccrueInterest(borrowRate, interest, totalBorrowed.assets, totalSupply.assets);
    }

    /// @inheritdoc IMarketBase
    /// @dev Callbacks are categorically unsupported by this market.
    function authorizedCallbacks(address) external pure returns (bool) {
        return false;
    }

    /// @inheritdoc IMarketBase
    /// @dev This market has no liquidation engine because public liquidation is
    /// unsupported.
    function liquidationEngine() external pure returns (address) {
        return address(0);
    }

    /// @inheritdoc IMarketBase
    /// @dev Always reverts because this market has no liquidation engine.
    function setLiquidationEngine(address) external pure {
        revert AltoCreditMarketUnsupportedOperation();
    }

    /// @inheritdoc IMarketBase
    /// @dev Always reverts because callback execution is unsupported.
    function setAuthorizedCallback(address, bool) external pure {
        revert AltoCreditMarketUnsupportedOperation();
    }

    /// @inheritdoc IMarketBase
    /// @dev Always reverts because the facility has synthetic capacity rather
    /// than lender supply.
    function addSupply(uint256, uint256, address) external pure returns (uint256, uint256) {
        revert AltoCreditMarketUnsupportedOperation();
    }

    /// @inheritdoc IMarketBase
    /// @dev Always reverts because the facility has no lender supply positions.
    function removeSupply(uint256, uint256, address, address) external pure returns (uint256, uint256) {
        revert AltoCreditMarketUnsupportedOperation();
    }

    /// @inheritdoc IMarketBase
    /// @dev Public liquidation is disabled; this market uses only owner-triggered foreclosure.
    function liquidate(address, bytes calldata, bytes calldata)
        external
        pure
        override
        returns (uint256, uint256, uint256)
    {
        revert AltoCreditMarketNonLiquidatable();
    }

    /// @inheritdoc IMarketBase
    /// @dev Foreclosure is available only after debt strictly exceeds the foreclosure LTV.
    function governanceLiquidate(address borrower)
        external
        nonReentrant
        onlyOwner
        returns (uint256 collateralAmount, uint256 badDebtAmount)
    {
        if (borrower != creditAccount) {
            revert AltoCreditMarketUnauthorizedAccount();
        }
        _accrueInterest();

        if (!_isForeclosable(borrower)) {
            revert AltoCreditMarketPositionNotForeclosable();
        }

        Position storage borrowerPosition = position[borrower];
        collateralAmount = borrowerPosition.collateralAssets;
        uint128 badDebtShares = borrowerPosition.borrowShares;
        badDebtAmount = totalBorrowed.assets;

        totalBorrowed.assets = 0;
        totalBorrowed.shares = 0;
        borrowerPosition.borrowShares = 0;
        borrowerPosition.collateralAssets = 0;

        if (collateralAmount != 0) {
            _sendCollateral(msg.sender, collateralAmount);
        }

        emit GovernanceLiquidation(borrower, msg.sender, collateralAmount, badDebtAmount, badDebtShares);
    }

    /// @dev Receives and places newly accounted collateral into derived-contract custody.
    function _receiveCollateral(uint256 assets) internal virtual;

    /// @dev Releases collateral from derived-contract custody and transfers it to a receiver.
    function _sendCollateral(address receiver, uint256 assets) internal virtual;

    /// @dev Sends the borrow token from one address to another.
    function _sendBorrowToken(address from, address to, uint256 amount) internal virtual {
        if (from == address(this)) {
            IMintableERC20(borrowToken).mint(to, amount);
        } else {
            IMintableERC20(borrowToken).burn(from, amount);
        }
    }

    /// @dev Checks if one of the inputs is zero and the other is not.
    function _onlyOneZero(uint256 x, uint256 y) internal pure returns (bool) {
        return (x == 0 && y != 0) || (x != 0 && y == 0);
    }

    /// @dev Returns true if the user's position is solvent.
    function _isSolvent(address _user) internal view returns (bool) {
        uint256 collateralValue = _collateralValue(_user);
        uint256 maxBorrowValue = collateralValue.multiplyWithPrecision(maxLtv);
        return maxBorrowValue >= _borrowValue(_user);
    }

    /// @dev Returns true if the user's position has breached the foreclosure LTV.
    function _isForeclosable(address _user) internal view returns (bool) {
        uint256 collateralValue = _collateralValue(_user);
        uint256 foreclosureBorrowValue = collateralValue.multiplyWithPrecision(foreclosureLtv);
        return _borrowValue(_user) > foreclosureBorrowValue;
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

    function _onPause(bytes32 pauseType, bool _paused) internal override {
        if (pauseType != PAUSE_TYPE) {
            return;
        }

        if (_paused) {
            _accrueInterest();
            IIrm(irm).onMarketPause(true);
        } else {
            IIrm(irm).onMarketPause(false);
        }
    }

    /// @dev Modifier to check if the market is not paused.
    modifier whenNotPaused() {
        if (paused[PAUSE_TYPE]) {
            revert IPausable.IsPaused(PAUSE_TYPE);
        }
        _;
    }

    /// @dev Modifier to check if the market is not frozen.
    modifier whenNotFrozen() {
        if (paused[FROZEN_TYPE]) {
            revert IPausable.IsPaused(FROZEN_TYPE);
        }
        _;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
