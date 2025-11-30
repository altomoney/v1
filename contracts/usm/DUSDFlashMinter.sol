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
/// @author Pearl Labs
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
    address private _dusdTreasury;

    /// @notice constructor
    /// @param _dusd The address of the DUSD token contract
    /// @param _treasury The address of the DUSD treasury
    /// @param _flashMintFee The flash mint fee struct
    /// @param _owner The owner of the contract
    constructor(address _dusd, address _treasury, FlashFee memory _flashMintFee, address _owner) Ownable(_owner) {
        require(_owner != address(0), "AltoDUSDFlashMinter: Owner cannot be zero address");
        DUSD = IDUSD(_dusd);
        _updateDusdTreasury(_treasury);
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
    function distributeFeesToTreasury() external override {
        uint256 balance = DUSD.balanceOf(address(this));
        DUSD.transfer(_dusdTreasury, balance);
        emit FeesDistributedToTreasury(_dusdTreasury, address(DUSD), balance);
    }

    // @inheritdoc IDUSDFlashMinter
    function updateFlashMintFee(FlashFee memory _newFlashMintFee) external onlyOwner {
        _updateFlashMintFee(_newFlashMintFee);
    }

    /// @inheritdoc IStableTokenFacilitator
    function updateStableTokenTreasury(address newDusdTreasury) external onlyOwner {
        _updateDusdTreasury(newDusdTreasury);
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
    function getStableTokenTreasury() external view returns (address) {
        return _dusdTreasury;
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

        emit SetFlashMintFee(flashMintFee, _newFlashMintFee);
        flashMintFee = _newFlashMintFee;
    }

    function _updateDusdTreasury(address newDusdTreasury) internal {
        address oldDusdTreasury = _dusdTreasury;
        _dusdTreasury = newDusdTreasury;
        emit StableTokenTreasuryUpdated(oldDusdTreasury, newDusdTreasury);
    }
}

