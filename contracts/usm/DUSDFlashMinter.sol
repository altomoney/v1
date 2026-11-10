// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AltoOwnable2Step, Ownable} from "@alto/utils/AltoOwnable2Step.sol";
import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import {IERC3156FlashLender} from "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";
import {IStableTokenFacilitator} from "@alto/usm/interfaces/IStableTokenFacilitator.sol";
import {IDUSDFlashMinter, FlashFee} from "@alto/usm/interfaces/IDUSDFlashMinter.sol";
import {FixedPointMath, MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";

/// @title DUSDFlashMinter
/// @notice Contract that enables FlashMinting of DUSD.
/// @author Adapted from Aave (https://github.com/aave/gho-core/)
/// @notice Contract that enables FlashMinting of DUSD.
/// @dev Based heavily on the EIP3156 reference implementation
contract DUSDFlashMinter is AltoOwnable2Step, IDUSDFlashMinter {
    using FixedPointMath for uint256;

    // @inheritdoc IDUSDFlashMinter
    bytes32 public constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    // @inheritdoc IDUSDFlashMinter
    IDUSD public immutable DUSD;

    // @inheritdoc IDUSDFlashMinter
    FlashFee public flashMintFee;

    // The DUSD treasury, the recipient of fee distributions
    address private _dusdFeeRecipient;

    /// @notice constructor
    /// @param _dusd The address of the DUSD token contract
    /// @param _feeRecipient The address of the DUSD fee recipient
    /// @param _flashMintFee The flash mint fee struct
    /// @param _owner The owner of the contract
    constructor(address _dusd, address _feeRecipient, FlashFee memory _flashMintFee, address _owner) Ownable(_owner) {
        require(_owner != address(0), "AltoDUSDFlashMinter: Owner cannot be zero address");
        DUSD = IDUSD(_dusd);
        _updateDusdFeeRecipient(_feeRecipient);
        _updateFlashMintFee(_flashMintFee);
    }

    /// @inheritdoc IERC3156FlashLender
    function flashLoan(IERC3156FlashBorrower receiver, address token, uint256 amount, bytes calldata data)
        external
        override
        returns (bool)
    {
        require(token == address(DUSD), "FlashMinter: Unsupported currency");

        uint256 fee = _flashFee(amount);
        DUSD.mint(address(receiver), amount);

        require(
            receiver.onFlashLoan(msg.sender, address(DUSD), amount, fee, data) == CALLBACK_SUCCESS,
            "FlashMinter: Callback failed"
        );

        DUSD.transferFrom(address(receiver), address(this), amount + fee);
        DUSD.burn(address(this), amount);

        emit FlashMint(address(receiver), msg.sender, address(DUSD), amount, fee);

        return true;
    }

    /// @inheritdoc IStableTokenFacilitator
    function distributeFeesToFeeRecipient() external override {
        uint256 balance = DUSD.balanceOf(address(this));
        if (balance > 0 && _dusdFeeRecipient != address(0)) {
            DUSD.transfer(_dusdFeeRecipient, balance);
            emit FeesDistributedToFeeRecipient(_dusdFeeRecipient, address(DUSD), balance);
        }
    }

    // @inheritdoc IDUSDFlashMinter
    function updateFlashMintFee(FlashFee memory _newFlashMintFee) external onlyOwner {
        _updateFlashMintFee(_newFlashMintFee);
    }

    /// @inheritdoc IStableTokenFacilitator
    function updateFeeRecipient(address newDusdFeeRecipient) external onlyOwner {
        _updateDusdFeeRecipient(newDusdFeeRecipient);
    }

    /// @inheritdoc IERC3156FlashLender
    function maxFlashLoan(address token) public view override returns (uint256) {
        if (token != address(DUSD)) {
            return 0;
        } else {
            (uint256 minted, uint256 ceiling) = DUSD.minterConfig(address(this));
            return ceiling > minted ? ceiling - minted : 0;
        }
    }

    /// @inheritdoc IERC3156FlashLender
    function flashFee(address token, uint256 amount) external view override returns (uint256) {
        require(token == address(DUSD), "FlashMinter: Unsupported currency");
        return _flashFee(amount);
    }

    /// @inheritdoc IDUSDFlashMinter
    function getFlashMintFee() external view returns (FlashFee memory) {
        return flashMintFee;
    }

    /// @inheritdoc IStableTokenFacilitator
    function getFeeRecipient() external view returns (address) {
        return _dusdFeeRecipient;
    }

    /// @notice returns the flash fee to charge for a given flashloan
    /// @param amount The amount of tokens to be borrowed
    /// @return The amount of `token` to be charged for the flashloan, on top of the returned principal
    function _flashFee(uint256 amount) internal view returns (uint256) {
        (, uint256 flashMintCap) = DUSD.minterConfig(address(this));
        require(amount <= flashMintCap, "FlashMinter: Amount exceeds flash mint cap");

        if (amount == 0) {
            return 0;
        }

        uint256 flashFeeToCharge;

        uint256 minFee = flashMintFee.minFlashFee;
        uint256 maxFee = flashMintFee.maxFlashFee;

        if (minFee == maxFee) {
            flashFeeToCharge = minFee;
        } else {
            bool increasing = maxFee > minFee;
            uint256 diff = increasing ? (maxFee - minFee) : (minFee - maxFee);
            uint256 step = FixedPointMath.divideWithRounding(amount, diff, flashMintCap, increasing);
            flashFeeToCharge = increasing ? (minFee + step) : (minFee - step);
        }

        return amount.multiplyWithPrecisionUp(flashFeeToCharge);
    }

    function _updateFlashMintFee(FlashFee memory _newFlashMintFee) internal {
        require(_newFlashMintFee.minFlashFee <= MATH_PRECISION, "FlashMinter: Min flash fee exceeds MATH_PRECISION");
        require(_newFlashMintFee.maxFlashFee <= MATH_PRECISION, "FlashMinter: Max flash fee exceeds MATH_PRECISION");

        if (_newFlashMintFee.minFlashFee > 0 || _newFlashMintFee.maxFlashFee > 0) {
            require(_dusdFeeRecipient != address(0), "FlashMinter: DUSD fee recipient must be set as fees are enabled");
        }

        emit SetFlashMintFee(flashMintFee, _newFlashMintFee);
        flashMintFee = _newFlashMintFee;
    }

    function _updateDusdFeeRecipient(address newDusdFeeRecipient) internal {
        if (newDusdFeeRecipient == address(0)) {
            require(
                flashMintFee.minFlashFee == 0 && flashMintFee.maxFlashFee == 0,
                "FlashMinter: Fees are enabled but fee recipient is not set"
            );
        }
        address oldDusdFeeRecipient = _dusdFeeRecipient;
        _dusdFeeRecipient = newDusdFeeRecipient;
        emit StableTokenFeeRecipientUpdated(oldDusdFeeRecipient, newDusdFeeRecipient);
    }
}

