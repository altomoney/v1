// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {AltoBaseMarket} from "../AltoBaseMarket.sol";
import {AltoConvexCreditLineLib} from "./AltoConvexCreditLineLib.sol";
import {AssetShareConversionMath} from "../libraries/AssetShareConversionMath.sol";
import {Uint128Converter} from "../libraries/Uint128Converter.sol";
import {CreditMarketInitParams, IAltoCreditMarket} from "../interfaces/IAltoCreditMarket.sol";
import {ConvexCreditLineInitParams, IAltoConvexCreditLine} from "../interfaces/IAltoConvexCreditLine.sol";
import {IIrm, IRMType} from "../interfaces/IIrm.sol";
import {BaseMarketInitParams, IMarketBase, MarketType, Position} from "../interfaces/IMarket.sol";
import {IMintableERC20} from "../interfaces/IMintableERC20.sol";
import {IConvexRewardPool} from "../interfaces/vendor/IConvexRewardPool.sol";

import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {FixedPointMath, MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";
import {ILendingOracle, LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";

/// @title Alto Convex Credit Line
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice An Isolated Convex Credit Line
/// @dev `totalSupply.assets` represents synthetic credit capacity rather than lender-supplied liquidity.
contract AltoConvexCreditLineMarket is AltoBaseMarket, IAltoConvexCreditLine {
    using FixedPointMath for uint256;
    using AssetShareConversionMath for uint256;
    using Uint128Converter for uint256;
    using SafeERC20 for IERC20;

    /// @inheritdoc IAltoCreditMarket
    address public creditAccount;

    /// @inheritdoc IAltoCreditMarket
    uint256 public foreclosureLtv;

    /// @inheritdoc IAltoCreditMarket
    uint128 public claimableFeesAssets;

    /// @notice The borrow opening fee in MATH_PRECISION
    uint256 private _borrowOpeningFee;

    /// @inheritdoc IAltoConvexCreditLine
    address public convexBooster;

    /// @inheritdoc IAltoConvexCreditLine
    uint256 public convexPoolId;

    /// @inheritdoc IAltoConvexCreditLine
    address public convexRewardPool;

    /// @inheritdoc IAltoConvexCreditLine
    address public convexDepositToken;

    /// @inheritdoc IAltoConvexCreditLine
    address public rewardRecipient;

    /// @inheritdoc IAltoConvexCreditLine
    bool public convexActive;

    /// @inheritdoc IAltoConvexCreditLine
    address[] public rewardToken;

    /// @inheritdoc IAltoConvexCreditLine
    mapping(address => bool) public isRewardToken;

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

    /// @dev Initializes the Base market and then initializes Credit state.
    function _initializeCreditMarket(CreditMarketInitParams memory _initParams) internal onlyInitializing {
        BaseMarketInitParams memory baseMarketInitParams = _initParams.baseMarketInitParams;

        _requireNonZeroAddress(_initParams.creditAccount);
        _requireNonZeroAddress(baseMarketInitParams.feeRecipient);
        if (
            _initParams.creditLimit == 0 || _initParams.initialBorrowOpeningFee > MATH_PRECISION
                || baseMarketInitParams.maxLtv >= _initParams.foreclosureLtv || _initParams.foreclosureLtv > MATH_PRECISION
                || IIrm(baseMarketInitParams.irm).IRM_TYPE() != IRMType.FIXED_RATE
        ) {
            revert AltoCreditMarketInvalidInput();
        }

        __UUPSUpgradeable_init();
        __AltoBaseMarket_init(baseMarketInitParams, MarketType.CREDIT_MINT);

        foreclosureLtv = _initParams.foreclosureLtv;
        emit SetForeclosureLtv(0, _initParams.foreclosureLtv);

        creditAccount = _initParams.creditAccount;

        totalSupply.assets = _initParams.creditLimit.toUint128();
        emit SetCreditLimit(0, _initParams.creditLimit);

        _borrowOpeningFee = _initParams.initialBorrowOpeningFee;
        emit SetBorrowOpeningFee(0, _initParams.initialBorrowOpeningFee);
    }

    /// @inheritdoc IAltoCreditMarket
    function setCreditLimit(uint256 _newCreditLimit) external nonReentrant onlyOwner {
        if (_newCreditLimit == 0) {
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

    /// @inheritdoc AltoBaseMarket
    function _setMaxLtv(uint256 _maxLtv) internal override {
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

    /// @inheritdoc AltoBaseMarket
    /// @dev Unlike `AltoBaseMarket`, only a nonzero fixed-rate IRM can be set.
    function _setIrm(address _irm, bool _skipAccrueInterest) internal override nonReentrant {
        _requireNonZeroAddress(_irm);
        if (_irm == irm || IIrm(_irm).IRM_TYPE() != IRMType.FIXED_RATE) {
            revert AltoCreditMarketInvalidInput();
        }

        super._setIrm(_irm, _skipAccrueInterest);
    }

    /// @inheritdoc AltoBaseMarket
    function _setFeeRecipient(address _feeRecipient) internal override {
        _requireNonZeroAddress(_feeRecipient);

        _updateFeeRecipient(_feeRecipient);
    }

    /// @inheritdoc IAltoCreditMarket
    function creditLimit() external view returns (uint256) {
        return totalSupply.assets;
    }

    /// @inheritdoc AltoBaseMarket
    function borrowOpeningFee() public view override(AltoBaseMarket, IMarketBase) returns (uint256) {
        return _borrowOpeningFee;
    }

    /// @inheritdoc AltoBaseMarket
    /// @dev Only `creditAccount` can receive collateral, which is deposited into Convex.
    function _addCollateral(uint256 assets, address onBehalf) internal override nonReentrant returns (uint256) {
        _requireCreditAccount(onBehalf);
        return super._addCollateral(assets, onBehalf);
    }

    /// @inheritdoc AltoBaseMarket
    /// @dev Callbacks are unsupported and collateral can be removed only while the remaining position is solvent.
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
    /// @dev Only `creditAccount` can borrow and callbacks are unsupported.
    function _borrow(uint256 assets, uint256 shares, address onBehalf, address receiver, bytes calldata swapParams)
        internal
        override
        returns (uint256, uint256, uint256)
    {
        _requireCreditAccount(onBehalf);
        if (swapParams.length != 0) {
            revert AltoCreditMarketCallbacksUnsupported();
        }

        return super._borrow(assets, shares, onBehalf, receiver, swapParams);
    }

    /// @inheritdoc AltoBaseMarket
    /// @dev Repayment is limited to `creditAccount` debt and burns the payer's borrow tokens.
    function _repay(uint256 assets, uint256 shares, address onBehalf)
        internal
        override
        nonReentrant
        returns (uint256, uint256)
    {
        if (!_onlyOneZero(assets, shares)) {
            revert AltoCreditMarketInvalidInput();
        }
        _requireCreditAccount(onBehalf);
        return super._repay(assets, shares, onBehalf);
    }

    /// @inheritdoc IAltoCreditMarket
    function claimInterest(uint256 interest) external nonReentrant whenNotPaused returns (uint256) {
        if (interest > claimableFeesAssets) {
            revert AltoCreditMarketInvalidInput();
        }
        _requireNonZeroAddress(feeRecipient);
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

    /// @inheritdoc AltoBaseMarket
    function _accrueInterest() internal override {
        (uint256 interest, uint256 borrowRate) = IIrm(irm).updateInterestRate(totalSupply.assets, totalBorrowed.assets);

        if (interest != 0) {
            totalBorrowed.assets += interest.toUint128();
            claimableFeesAssets += interest.toUint128();
        }

        emit AccrueInterest(borrowRate, interest, totalBorrowed.assets, totalSupply.assets);
    }

    /// @inheritdoc AltoBaseMarket
    function _applyBorrowOpeningFee(uint256 openingFeeAssets) internal override returns (uint256) {
        claimableFeesAssets += openingFeeAssets.toUint128();
        return 0;
    }

    /// @inheritdoc AltoBaseMarket
    function _setLiquidationEngine(address) internal pure override {
        revert AltoCreditMarketUnsupportedOperation();
    }

    /// @inheritdoc AltoBaseMarket
    function _setAuthorizedCallback(address, bool) internal pure override {
        revert AltoCreditMarketUnsupportedOperation();
    }

    /// @inheritdoc AltoBaseMarket
    function _addSupply(uint256, uint256, address) internal pure override returns (uint256, uint256) {
        revert AltoCreditMarketUnsupportedOperation();
    }

    /// @inheritdoc AltoBaseMarket
    function _removeSupply(uint256, uint256, address, address) internal pure override returns (uint256, uint256) {
        revert AltoCreditMarketUnsupportedOperation();
    }

    /// @inheritdoc AltoBaseMarket
    function _liquidate(address, bytes calldata, bytes calldata)
        internal
        pure
        override
        returns (uint256, uint256, uint256)
    {
        revert AltoCreditMarketNonLiquidatable();
    }

    /// @inheritdoc AltoBaseMarket
    /// @dev Foreclosure is available only after debt strictly exceeds the foreclosure LTV.
    function governanceLiquidate(address borrower)
        external
        override(AltoBaseMarket, IMarketBase)
        nonReentrant
        onlyOwner
        returns (uint256 collateralAmount, uint256 badDebtAmount)
    {
        _requireCreditAccount(borrower);
        _accrueInterest();

        if (!_isLiquidatable(borrower)) {
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

    /// @inheritdoc AltoBaseMarket
    function _sendBorrowToken(address from, address to, uint256 amount) internal override {
        if (from == address(this)) {
            IMintableERC20(borrowToken).mint(to, amount);
        } else {
            IMintableERC20(borrowToken).burn(from, amount);
        }
    }

    /// @inheritdoc AltoBaseMarket
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

    /// @dev Reverts when the supplied address is zero.
    function _requireNonZeroAddress(address account) internal pure {
        if (account == address(0)) {
            revert AltoCreditMarketZeroAddress();
        }
    }

    /// @inheritdoc IAltoConvexCreditLine
    function rewardTokenCount() external view returns (uint256) {
        return rewardToken.length;
    }

    /// @inheritdoc IAltoConvexCreditLine
    function stakedCollateralAssets() external view returns (uint256) {
        return IConvexRewardPool(convexRewardPool).balanceOf(address(this));
    }

    /// @inheritdoc IAltoConvexCreditLine
    function idleCollateralAssets() public view returns (uint256) {
        return IERC20(collateralToken).balanceOf(address(this));
    }

    /// @inheritdoc IAltoConvexCreditLine
    function claimRewards() external nonReentrant returns (uint256[] memory claimedAmounts) {
        return AltoConvexCreditLineLib.claimRewards(convexRewardPool, rewardRecipient, rewardToken);
    }

    /// @inheritdoc IAltoConvexCreditLine
    function setRewardRecipient(address _newRecipient) external {
        _requireCreditAccount(msg.sender);
        _requireNonZeroAddress(_newRecipient);

        emit SetRewardRecipient(rewardRecipient, _newRecipient);
        rewardRecipient = _newRecipient;
    }

    /// @inheritdoc IAltoConvexCreditLine
    function addRewardToken(address _token) external onlyOwner {
        _addRewardToken(_token);
        emit RewardTokenAdded(_token);
    }

    /// @inheritdoc IAltoConvexCreditLine
    function removeRewardToken(address _token) external onlyOwner {
        AltoConvexCreditLineLib.removeRewardToken(rewardToken, isRewardToken, convexRewardPool, _token);

        emit RewardTokenRemoved(_token);
    }

    /// @inheritdoc IAltoConvexCreditLine
    function emergencyExitConvex() external nonReentrant onlyOwner returns (uint256 assets) {
        if (!paused[PAUSE_TYPE]) {
            revert AltoConvexCreditLineMustBePaused();
        }
        if (!convexActive) {
            revert AltoConvexCreditLineStrategyInactive();
        }

        assets = AltoConvexCreditLineLib.emergencyWithdraw(collateralToken, convexRewardPool);

        convexActive = false;
        IERC20(collateralToken).forceApprove(convexBooster, 0);
        emit ConvexEmergencyExit(assets);
    }

    /// @dev Validates and stores the Convex custody and reward configuration.
    function _initializeConvex(ConvexCreditLineInitParams memory _initParams) private {
        uint256 tokenCount = _initParams.rewardTokens.length;
        (address depositToken, address rewardPool) = AltoConvexCreditLineLib.validateConvexInitialization(
            _initParams.convexBooster,
            _initParams.convexPoolId,
            collateralToken,
            _initParams.rewardRecipient,
            tokenCount
        );

        convexBooster = _initParams.convexBooster;
        convexPoolId = _initParams.convexPoolId;
        convexRewardPool = rewardPool;
        convexDepositToken = depositToken;
        rewardRecipient = _initParams.rewardRecipient;
        convexActive = true;

        for (uint256 i = 0; i < tokenCount; ++i) {
            _addRewardToken(_initParams.rewardTokens[i]);
        }

        if (!isRewardToken[IConvexRewardPool(rewardPool).rewardToken()]) {
            revert AltoCreditMarketInvalidInput();
        }

        IERC20(collateralToken).forceApprove(_initParams.convexBooster, type(uint256).max);

        emit ConvexConfigured(
            _initParams.convexBooster, _initParams.convexPoolId, rewardPool, depositToken, _initParams.rewardRecipient
        );
    }

    /// @dev Adds a validated token to the reward forwarding list.
    function _addRewardToken(address _token) private {
        AltoConvexCreditLineLib.validateRewardTokenAddition(
            rewardToken.length, isRewardToken[_token], _token, collateralToken, borrowToken, convexDepositToken
        );

        isRewardToken[_token] = true;
        rewardToken.push(_token);
    }

    /// @inheritdoc AltoBaseMarket
    function _receiveCollateral(uint256 assets) internal override {
        if (!convexActive) {
            revert AltoCreditMarketInvalidInput();
        }

        uint256 idleBefore = idleCollateralAssets();

        super._receiveCollateral(assets);
        AltoConvexCreditLineLib.depositCollateralToConvex(
            collateralToken, convexBooster, convexPoolId, convexRewardPool, assets, idleBefore
        );
    }

    /// @inheritdoc AltoBaseMarket
    function _sendCollateral(address receiver, uint256 assets) internal override {
        if (convexActive) {
            AltoConvexCreditLineLib.withdrawAndUnwrapCollateral(collateralToken, convexRewardPool, assets);
        } else if (idleCollateralAssets() < assets) {
            revert AltoConvexCreditLineUnexpectedAssetDelta();
        }

        super._sendCollateral(receiver, assets);
        emit CollateralUnstaked(receiver, assets);
    }
}
