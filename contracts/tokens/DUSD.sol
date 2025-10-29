// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {OFT} from "@alto/utils/OFT.sol";
import {IDUSD, MinterConfig, FlashFee} from "@alto/tokens/interfaces/IDUSD.sol";

import {Pausable, IPausable} from "@alto/utils/Pausable.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {ERC20FlashMint} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20FlashMint.sol";
import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import {FixedPointMath, MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";

/// @title DUSD Token
/// @author Pearl Labs
/// @custom:contact security@tapioca.xyz
/// @notice The DUSD Token is the stablecoin of the Alto Protocol.
contract DUSD is Ownable2Step, Pausable, OFT, ERC20FlashMint, IDUSD {
    using FixedPointMath for uint256;

    /// @inheritdoc IDUSD
    address public flashFeeReceiver;

    /// @inheritdoc IDUSD
    FlashFee public flashFee;

    /// @inheritdoc IDUSD
    uint256 public flashMintCap;

    /// @inheritdoc IDUSD
    mapping(address => bool) public allowedMinter;

    /// @inheritdoc IDUSD
    mapping(address => MinterConfig) public minterConfig;

    /// @inheritdoc IDUSD
    mapping(address => bool) public allowedBurner;

    /// @notice constructor
    /// @param endpoint The endpoint address
    /// @param owner The owner of the contract
    constructor(address endpoint, address owner) OFT("DUSD", "DUSD", endpoint, owner) Ownable(owner) {
        _setPauser(owner, PAUSE_TYPE, true);
    }

    /// @inheritdoc IDUSD
    function mint(address _to, uint256 _amount) external whenNotPaused {
        if (!allowedMinter[msg.sender]) {
            revert DUSDNotAuthorized();
        }
        if (minterConfig[msg.sender].minted + _amount > minterConfig[msg.sender].ceiling) {
            revert DUSDInvalidInput();
        }
        minterConfig[msg.sender].minted += _amount;
        _mint(_to, _amount);
    }

    /// @inheritdoc IDUSD
    function burn(address _from, uint256 _amount) external whenNotPaused {
        if (!allowedBurner[msg.sender]) {
            revert DUSDNotAuthorized();
        }
        if (minterConfig[msg.sender].minted < _amount) {
            revert DUSDInvalidInput();
        }
        minterConfig[msg.sender].minted -= _amount;
        _burn(_from, _amount);
    }

    /// @inheritdoc ERC20FlashMint
    function flashLoan(IERC3156FlashBorrower receiver, address token, uint256 value, bytes calldata data)
        public
        virtual
        override
        whenNotPaused
        returns (bool)
    {
        return super.flashLoan(receiver, token, value, data);
    }

    /// @inheritdoc ERC20FlashMint
    function _flashFee(address, uint256 amount) internal view virtual override returns (uint256) {
        if (amount > flashMintCap) {
            revert DUSDExceededFlashMintCap();
        }
        uint256 flashFeeToCharge;

        if (flashFee.minFlashFee == flashFee.maxFlashFee) {
            flashFeeToCharge = flashFee.minFlashFee;
        } else if (flashFee.maxFlashFee > flashFee.minFlashFee) {
            uint256 flashFeeDifference = flashFee.maxFlashFee - flashFee.minFlashFee;
            flashFeeToCharge =
                flashFee.minFlashFee + FixedPointMath.divideWithRounding(amount, flashFeeDifference, flashMintCap, true);
        } else {
            // flashFee.minFlashFee > flashFee.maxFlashFee
            uint256 flashFeeDifference = flashFee.minFlashFee - flashFee.maxFlashFee;
            flashFeeToCharge = flashFee.minFlashFee
                - FixedPointMath.divideWithRounding(amount, flashFeeDifference, flashMintCap, false);
        }

        return amount.multiplyWithPrecisionUp(flashFeeToCharge);
    }

    /// @inheritdoc ERC20FlashMint
    function _flashFeeReceiver() internal view virtual override returns (address) {
        return flashFeeReceiver;
    }

    /// @inheritdoc ERC20FlashMint
    function maxFlashLoan(address token) public view virtual override returns (uint256) {
        return token == address(this) ? flashMintCap : 0;
    }

    /// @inheritdoc IDUSD
    function setFlashFeeReceiver(address _newFlashFeeReceiver) external onlyOwner {
        emit SetFlashFeeReceiver(flashFeeReceiver, _newFlashFeeReceiver);
        flashFeeReceiver = _newFlashFeeReceiver;
    }

    /// @inheritdoc IDUSD
    function setFlashFee(FlashFee calldata _newFlashFee) external onlyOwner {
        if (_newFlashFee.minFlashFee > MATH_PRECISION || _newFlashFee.maxFlashFee > MATH_PRECISION) {
            revert DUSDInvalidInput();
        }

        emit SetFlashFee(flashFee, _newFlashFee);
        flashFee = _newFlashFee;
    }

    /// @inheritdoc IDUSD
    function setFlashMintCap(uint256 _newFlashMintCap) external onlyOwner {
        emit SetFlashMintCap(flashMintCap, _newFlashMintCap);
        flashMintCap = _newFlashMintCap;
    }

    /// @inheritdoc IDUSD
    function setMinterStatus(address _for, bool _status) external onlyOwner {
        allowedMinter[_for] = _status;
        emit SetMinterStatus(_for, _status);
    }

    /// @inheritdoc IDUSD
    function setMinterCeiling(address _for, uint256 _ceiling) external onlyOwner {
        minterConfig[_for].ceiling = _ceiling;
        emit SetMinterCeiling(_for, _ceiling);
    }

    /// @inheritdoc IDUSD
    function setBurnerStatus(address _for, bool _status) external onlyOwner {
        allowedBurner[_for] = _status;
        emit SetBurnerStatus(_for, _status);
    }

    modifier whenNotPaused() {
        if (paused[PAUSE_TYPE]) {
            revert IPausable.IsPaused(PAUSE_TYPE);
        }
        _;
    }

    /// @dev we need to override the _transferOwnership function as OFT contract uses Ownable
    function _transferOwnership(address newOwner) internal virtual override(Ownable, Ownable2Step) {
        super._transferOwnership(newOwner);
    }

    /// @dev we need to override the transferOwnership function as OFT contract uses Ownable
    function transferOwnership(address newOwner) public virtual override(Ownable, Ownable2Step) {
        super.transferOwnership(newOwner);
    }

    /// @inheritdoc IPausable
    function setPauser(address pauser, bytes32 pauseType, bool status) public override(Pausable) onlyOwner {
        _setPauser(pauser, pauseType, status);
    }
}
