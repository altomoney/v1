// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {Uint128Converter} from "./libraries/Uint128Converter.sol";

import {IIrm} from "./interfaces/IIrm.sol";
import {Balance, LiquidationConfiguration} from "./interfaces/IMarket.sol";
import {IMintableERC20} from "./interfaces/IMintableERC20.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";

import {AltoBaseMarket} from "./AltoBaseMarket.sol";

/// @title Alto Mint Market
/// @author Pearl Labs
/// @custom:contact security@altofoundation.org
/// @notice An Isolated Mint Market
contract AltoMintMarket is AltoBaseMarket {
    using Uint128Converter for uint256;

    /// @notice Thrown when a function is not implemented for the mint market
    error AltoMintMarketNotImplemented();

    /// @notice Thrown when the input is invalid
    error AltoMintMarketInvalidInput();

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

    /// @notice The amount of claimable fees assets
    /// @dev This is used to store the amount of claimable fees assets used when claiming interest
    uint128 public claimableFeesAssets;

    /// @notice The borrow opening fee in MATH_PRECISION
    uint256 private _borrowOpeningFee;

    /// @notice The address of the DUSD oracle
    /// @dev This oracle returns USD price of the DUSD token
    /// @dev Unused right now but will be used in the future to calculate the borrow opening fee as per specification
    address public dusdOracle;

    /// upgrade gap
    uint256[47] private __gap_mint;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _borrowToken,
        address _collateralToken,
        address _irm,
        address _owner,
        address _oracle,
        uint256 _maxLtv,
        uint256 _debtCeiling,
        address _feeRecipient,
        uint256 _initialBorrowOpeningFee,
        LiquidationConfiguration memory _liquidationConfiguration
    ) public initializer {
        __AltoBaseMarket_init(
            _borrowToken, _collateralToken, _irm, _owner, _oracle, _maxLtv, _feeRecipient, _liquidationConfiguration
        );

        if (_initialBorrowOpeningFee > MATH_PRECISION) {
            revert AltoMintMarketInvalidInput();
        }
        if (_feeRecipient == address(0) && _initialBorrowOpeningFee > 0) {
            revert AltoMintMarketInvalidInput();
        }

        if (_feeRecipient == address(0) && irm != address(0)) {
            revert AltoMintMarketInvalidInput();
        }

        _borrowOpeningFee = _initialBorrowOpeningFee;
        emit SetBorrowOpeningFee(0, _initialBorrowOpeningFee);

        totalSupply.assets = _debtCeiling.toUint128();
        emit SetDebtCeiling(0, _debtCeiling);
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

    /// @notice Setter of the DUSD oracle
    /// @param _dusdOracle The new DUSD oracle
    function setDusdOracle(address _dusdOracle) external onlyOwner {
        if (_dusdOracle == address(0)) {
            revert AltoMintMarketInvalidInput();
        }

        emit SetDusdOracle(dusdOracle, _dusdOracle);
        dusdOracle = _dusdOracle;
    }

    /// @notice Setter of the borrow opening fee
    /// @param _newBorrowOpeningFee The new borrow opening fee
    function setBorrowOpeningFee(uint256 _newBorrowOpeningFee) external onlyOwner {
        if (_newBorrowOpeningFee > MATH_PRECISION) {
            revert AltoMintMarketInvalidInput();
        }

        if (feeRecipient == address(0) && _newBorrowOpeningFee > 0) {
            revert AltoMintMarketInvalidInput();
        }

        emit SetBorrowOpeningFee(_borrowOpeningFee, _newBorrowOpeningFee);
        _borrowOpeningFee = _newBorrowOpeningFee;
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
            revert AltoMintMarketInvalidInput();
        }

        emit SetFeeRecipient(feeRecipient, _feeRecipient);
        feeRecipient = _feeRecipient;
    }

    /// @dev Disabled on mint market
    function addSupply(uint256, uint256, address) external override returns (uint256, uint256) {
        revert AltoMintMarketNotImplemented();
    }

    /// @dev Disabled on mint market
    function removeSupply(uint256, uint256, address, address) external override returns (uint256, uint256) {
        revert AltoMintMarketNotImplemented();
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
