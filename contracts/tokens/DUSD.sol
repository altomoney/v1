// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {OFT} from "@alto/utils/OFT.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";

import {Pausable, IPausable} from "@alto/utils/Pausable.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";

/// @title DUSD Token
/// @author Pearl Labs
/// @custom:contact security@tapioca.xyz
/// @notice The DUSD Token is the stablecoin of the Alto Protocol.
contract DUSD is Ownable2Step, Pausable, OFT, IDUSD {
    uint256 public fees;

    address public flashLoanHelper;

    mapping(address => bool) public allowedMinter;
    mapping(address => bool) public allowedBurner;

    constructor(address endpoint, address owner) OFT("DUSD", "DUSD", endpoint, owner) Ownable(owner) {
        _setPauser(owner, PAUSE_TYPE, true);
    }

    /// =====================
    /// External
    /// =====================
    /**
     * @notice mints DUSD
     * @param _to receiver address
     * @param _amount the amount to mint
     */
    function mint(address _to, uint256 _amount) external whenNotPaused {
        if (!allowedMinter[msg.sender]) {
            revert DUSDNotAuthorized();
        }
        _mint(_to, _amount);
    }

    /**
     * @notice burns DUSD
     * @param _from address to burn from
     * @param _amount the amount to burn
     */
    function burn(address _from, uint256 _amount) external whenNotPaused {
        if (!allowedBurner[msg.sender]) {
            revert DUSDNotAuthorized();
        }
        _burn(_from, _amount);
    }

    /**
     * @notice registeres flashloan fees
     * @dev can only be called by the `FlashloanHelper` contract
     * @param _fee fees amount
     */
    function addFlashloanFee(uint256 _fee) external {
        if (msg.sender != flashLoanHelper) revert DUSDNotAuthorized();
        fees += _fee;
    }

    /// =====================
    /// Owner
    /// =====================

    /**
     * @notice sets `FlashloanHelper` contract
     * @param _helper the contract address
     */
    function setFlashloanHelper(address _helper) external onlyOwner {
        flashLoanHelper = _helper;
    }

    /**
     * @notice transfers fees to sender
     */
    function extractFees() external onlyOwner {
        if (fees > 0) {
            uint256 balance = balanceOf(address(this));

            uint256 toExtract = balance >= fees ? fees : balance;
            fees -= toExtract;
            _transfer(address(this), msg.sender, toExtract);
        }
    }

    /**
     * @notice sets/unsets address as minter
     * @dev can only be called by the owner
     * @param _for role receiver
     * @param _status true/false
     */
    function setMinterStatus(address _for, bool _status) external onlyOwner {
        allowedMinter[_for] = _status;
        emit SetMinterStatus(_for, _status);
    }

    /**
     * @notice sets/unsets address as burner
     * @dev can only be called by the owner
     * @param _for role receiver
     * @param _status true/false
     */
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
