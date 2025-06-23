// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {OFT} from "@alto/utils/OFT.sol";
import {IUSDO} from "@alto/tokens/interfaces/IUSDO.sol";

import {Pausable, IPausable} from "@alto/utils/Pausable.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {PAUSED_ROLE} from "@alto/utils/Constants.sol";

/// @title USDO Token
/// @author Alto Foundation
/// @custom:contact security@alto.xyz
/// @notice The USDO Token is the stablecoin of the Alto Protocol.
contract USDO is Ownable2Step, Pausable, OFT, IUSDO {
    uint256 public fees;

    address public flashLoanHelper;

    mapping(address => bool) public allowedMinter;
    mapping(address => bool) public allowedBurner;

    constructor(address endpoint, address owner) OFT("USDO", "USDO", endpoint, owner) Ownable(owner) {
        _setPauser(owner, PAUSED_ROLE, true);
    }

    /// =====================
    /// External
    /// =====================
    /**
     * @notice mints USDO
     * @param _to receiver address
     * @param _amount the amount to mint
     */
    function mint(address _to, uint256 _amount) external whenNotPaused {
        if (!allowedMinter[msg.sender]) {
            revert UsdoNotAuthorized();
        }
        _mint(_to, _amount);
    }

    /**
     * @notice burns USDO
     * @param _from address to burn from
     * @param _amount the amount to burn
     */
    function burn(address _from, uint256 _amount) external whenNotPaused {
        if (!allowedBurner[msg.sender]) {
            revert UsdoNotAuthorized();
        }
        _burn(_from, _amount);
    }

    /**
     * @notice registeres flashloan fees
     * @dev can only be called by the `FlashloanHelper` contract
     * @param _fee fees amount
     */
    function addFlashloanFee(uint256 _fee) external {
        if (msg.sender != flashLoanHelper) revert UsdoNotAuthorized();
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
        if (paused[PAUSED_ROLE]) {
            revert IPausable.IsPaused(PAUSED_ROLE);
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
