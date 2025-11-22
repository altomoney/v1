// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {Uint128Converter} from "./libraries/Uint128Converter.sol";

import {IIrm} from "./interfaces/IIrm.sol";
import {Balance, DaoMintMarketInitParams, LiquidationConfiguration, MarketType} from "./interfaces/IMarket.sol";
import {IMintableERC20} from "./interfaces/IMintableERC20.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";

import {AltoBaseMarket} from "./AltoBaseMarket.sol";

/// @title Alto DAO Mint Market
/// @author Pearl Labs
/// @custom:contact security@tapioca.xyz
/// @notice An Isolated Mint Market that is controlled by a DAO through authorized controllers or public access.
/// @dev This market is used to mint DUSD by supplying collateral in isolation.
contract AltoDaoMintMarket is AltoBaseMarket {
    using Uint128Converter for uint256;

    /// @notice Thrown when a function is not implemented for the mint market
    error AltoDaoMintMarketNotImplemented();

    /// @notice Thrown when the input is invalid
    error AltoDaoMintMarketInvalidInput();

    /// @notice Thrown when the caller is not authorized to call the function
    error AltoDaoMintMarketUnauthorized();

    /// @notice Emitted when the debt ceiling is set
    /// @param oldDebtCeiling The old debt ceiling
    /// @param newDebtCeiling The new debt ceiling
    event SetDebtCeiling(uint256 oldDebtCeiling, uint256 newDebtCeiling);

    /// @notice Emitted when interest is claimed by the fee recipient
    /// @param amount The amount of interest claimed
    event InterestClaimed(uint256 amount);

    /// @notice Emitted when the DUSD oracle is set
    /// @param oldDusdOracle The old DUSD oracle
    /// @param newDusdOracle The new DUSD oracle
    event SetDusdOracle(address oldDusdOracle, address newDusdOracle);

    /// @notice Emitted when the borrow opening fee is set
    /// @param oldBorrowOpeningFee The old borrow opening fee
    /// @param newBorrowOpeningFee The new borrow opening fee
    event SetBorrowOpeningFee(uint256 oldBorrowOpeningFee, uint256 newBorrowOpeningFee);

    /// @notice Emitted when an authorized controller is set
    /// @param controller The address of the authorized controller
    /// @param authorized The new authorized status
    event SetAuthorizedController(address controller, bool authorized);

    /// @notice Emitted when public access is enabled
    /// @param publicAccessEnabled The new public access status
    event SetPublicAccessEnabled(bool publicAccessEnabled);

    /// @notice The amount of claimable fees assets
    /// @dev This is used to store the amount of claimable fees assets used when claiming interest
    uint128 public claimableFeesAssets;

    /// @notice The borrow opening fee in MATH_PRECISION
    uint256 private _borrowOpeningFee;

    /// @notice Mapping of authorized controllers
    mapping(address => bool) public authorizedControllers;

    /// @notice Flag to enable public access
    bool public publicAccessEnabled;

    /// upgrade gap
    uint256[46] private __gap_mint;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    modifier validCaller(address caller) {
        // caller is valid if it is owner or authorized controller or public access is enabled
        if (caller != owner() && !authorizedControllers[caller] && !publicAccessEnabled) {
            revert AltoDaoMintMarketUnauthorized();
        }
        _;
    }

    function initialize(DaoMintMarketInitParams memory _initParams) public initializer {
        __AltoBaseMarket_init(_initParams.baseMarketInitParams, MarketType.DAO_MINT);

        if (_initParams.initialBorrowOpeningFee > MATH_PRECISION) {
            revert AltoDaoMintMarketInvalidInput();
        }
        if (_initParams.baseMarketInitParams.feeRecipient == address(0) && _initParams.initialBorrowOpeningFee > 0) {
            revert AltoDaoMintMarketInvalidInput();
        }

        if (
            _initParams.baseMarketInitParams.feeRecipient == address(0)
                && _initParams.baseMarketInitParams.irm != address(0)
        ) {
            revert AltoDaoMintMarketInvalidInput();
        }

        _borrowOpeningFee = _initParams.initialBorrowOpeningFee;
        emit SetBorrowOpeningFee(0, _initParams.initialBorrowOpeningFee);

        totalSupply.assets = _initParams.debtCeiling.toUint128();
        emit SetDebtCeiling(0, _initParams.debtCeiling);
    }

    /// @notice Sets the debt ceiling for the mint market
    /// @param _debtCeiling The new debt ceiling
    function setDebtCeiling(uint256 _debtCeiling) external onlyOwner {
        // If market is paused we don't want to accrue interest as the rest of the
        // lending protocol does
        if (!paused[PAUSE_TYPE]) {
            _accrueInterest();
        }

        if (totalBorrowed.assets > _debtCeiling) {
            revert AltoBaseMarketInsufficientMarketLiquidity();
        }

        emit SetDebtCeiling(totalSupply.assets, _debtCeiling);
        totalSupply.assets = _debtCeiling.toUint128();
    }

    /// @notice Setter of the borrow opening fee
    /// @param _newBorrowOpeningFee The new borrow opening fee
    function setBorrowOpeningFee(uint256 _newBorrowOpeningFee) external onlyOwner {
        if (_newBorrowOpeningFee > MATH_PRECISION) {
            revert AltoDaoMintMarketInvalidInput();
        }

        if (feeRecipient == address(0) && _newBorrowOpeningFee > 0) {
            revert AltoDaoMintMarketInvalidInput();
        }

        emit SetBorrowOpeningFee(_borrowOpeningFee, _newBorrowOpeningFee);
        _borrowOpeningFee = _newBorrowOpeningFee;
    }

    /// @notice Setter of the authorized controller
    /// @param _controller The address of the authorized controller
    /// @param _authorized The new authorized status
    function setAuthorizedController(address _controller, bool _authorized) external onlyOwner {
        if (_controller == address(0)) {
            revert AltoDaoMintMarketInvalidInput();
        }

        authorizedControllers[_controller] = _authorized;
        emit SetAuthorizedController(_controller, _authorized);
    }

    /// @notice Setter of the public access
    /// @param _publicAccessEnabled The new public access status
    function setPublicAccessEnabled(bool _publicAccessEnabled) external onlyOwner {
        // once public access is enabled, it cannot be disabled
        if (publicAccessEnabled) {
            revert AltoDaoMintMarketInvalidInput();
        }
        publicAccessEnabled = _publicAccessEnabled;
        emit SetPublicAccessEnabled(_publicAccessEnabled);
    }

    /// @notice Getter of the borrow opening fee
    /// @return The borrow opening fee
    /// @dev The borrow opening fee is calculated as per specification.
    /// Interaction with the DUSD oracle is not implemented yet.
    function borrowOpeningFee() public view override returns (uint256) {
        return _borrowOpeningFee;
    }

    /// @inheritdoc AltoBaseMarket
    function setFeeRecipient(address _feeRecipient) external override onlyOwner {
        if (
            _feeRecipient == address(0)
                && (_borrowOpeningFee > 0 || liquidationConfiguration.protocolFeePercentage > 0 || irm != address(0))
        ) {
            revert AltoDaoMintMarketInvalidInput();
        }

        emit SetFeeRecipient(feeRecipient, _feeRecipient);
        feeRecipient = _feeRecipient;
    }

    /// @dev Disabled on mint market
    function _addSupply(uint256, uint256, address) internal override returns (uint256, uint256) {
        revert AltoDaoMintMarketNotImplemented();
    }

    /// @dev Disabled on mint market
    function _removeSupply(uint256, uint256, address, address) internal override returns (uint256, uint256) {
        revert AltoDaoMintMarketNotImplemented();
    }

    /// @inheritdoc AltoBaseMarket
    function _addCollateral(uint256 assets, address onBehalf)
        internal
        override
        validCaller(msg.sender)
        returns (uint256)
    {
        return super._addCollateral(assets, onBehalf);
    }

    /// @inheritdoc AltoBaseMarket
    function _removeCollateral(uint256 assets, address onBehalf, address receiver, bytes calldata swapParams)
        internal
        override
        validCaller(msg.sender)
        returns (uint256)
    {
        return super._removeCollateral(assets, onBehalf, receiver, swapParams);
    }

    /// @inheritdoc AltoBaseMarket
    function _borrow(uint256 assets, uint256 shares, address onBehalf, address receiver, bytes calldata swapParams)
        internal
        override
        validCaller(msg.sender)
        returns (uint256, uint256, uint256)
    {
        return super._borrow(assets, shares, onBehalf, receiver, swapParams);
    }

    /// @inheritdoc AltoBaseMarket
    function _repay(uint256 assets, uint256 shares, address onBehalf)
        internal
        override
        validCaller(msg.sender)
        returns (uint256, uint256)
    {
        return super._repay(assets, shares, onBehalf);
    }

    /// @inheritdoc AltoBaseMarket
    function _liquidate(address borrower, bytes calldata data)
        internal
        override
        validCaller(msg.sender)
        returns (uint256, uint256, uint256)
    {
        return super._liquidate(borrower, data);
    }

    function _accrueInterest() internal override {
        if (irm == address(0)) {
            return;
        }

        (uint256 interest, uint256 borrowRate) = IIrm(irm).updateInterestRate(totalSupply.assets, totalBorrowed.assets);

        totalBorrowed.assets += interest.toUint128();
        claimableFeesAssets += interest.toUint128();

        emit AccrueInterest(borrowRate, interest, totalBorrowed.assets, totalSupply.assets);
    }

    function _applyBorrowOpeningFee(uint256 openingFeeAssets) internal override returns (uint256) {
        claimableFeesAssets += openingFeeAssets.toUint128();

        return 0;
    }

    function _applyLiquidationBadDebt(Balance memory badDebt, address borrower) internal override {
        totalBorrowed.shares -= badDebt.shares;
        totalBorrowed.assets -= badDebt.assets;

        position[borrower].borrowShares = 0;
    }

    function _sendBorrowToken(address from, address to, uint256 amount) internal override {
        if (from == address(this)) {
            IMintableERC20(borrowToken).mint(to, amount);
        } else {
            IMintableERC20(borrowToken).burn(from, amount);
        }
    }

    /// @notice Claims the interest and fees from the mint market by minting the borrow token to the fee recipient
    /// @param interest The amount of interest to claim
    /// @dev If interest is 0, it will claim all the interest and fees
    /// @return The amount of interest and fees claimed
    function claimInterest(uint256 interest) external whenNotPaused returns (uint256) {
        if (feeRecipient == address(0) || interest > claimableFeesAssets) {
            revert AltoBaseMarketInvalidInput();
        }

        if (msg.sender != owner() && msg.sender != feeRecipient) {
            revert AltoBaseMarketUnauthorized();
        }

        if (interest == 0) {
            interest = claimableFeesAssets;
        }

        IMintableERC20(borrowToken).mint(feeRecipient, interest);
        claimableFeesAssets -= interest.toUint128();

        emit InterestClaimed(interest);

        return interest;
    }
}
