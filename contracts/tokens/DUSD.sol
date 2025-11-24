// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import {OFT} from "@alto/utils/OFT.sol";
import {IDUSD, MinterConfig} from "@alto/tokens/interfaces/IDUSD.sol";

import {Pausable, IPausable} from "@alto/utils/Pausable.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";

/// @title DUSD Token
/// @author Pearl Labs
/// @custom:contact security@altofoundation.org
/// @notice The DUSD Token is the stablecoin of the Alto Protocol.
contract DUSD is Ownable2Step, Pausable, OFT, IDUSD {
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
