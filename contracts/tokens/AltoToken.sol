// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {OFT} from "@alto/utils/OFT.sol";
import {OFTCore} from "@layerzerolabs/oft-evm/contracts/OFTCore.sol";

// External
import {ERC20Permit, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Pausable, IPausable} from "@alto/utils/Pausable.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IAltoToken} from "@alto/tokens/interfaces/IAltoToken.sol";
import {PAUSED_ROLE} from "@alto/utils/Constants.sol";

/// @title Alto Token
/// @author Alto Foundation
/// @custom:contact security@alto.xyz
/// @notice The Alto Token is the native token of the Alto Protocol.
contract AltoToken is Pausable, OFT, IAltoToken {
    mapping(address => bool) public allowedMinter;
    mapping(address => bool) public allowedBurner;

    constructor(address endpoint, address owner) OFT("ALTO", "ALTO", endpoint, owner) Ownable(owner) {
        _mint(owner, 100_000_000 ether);
    }

    /**
     * @notice mints token
     * @param _to receiver address
     * @param _amount the amount to mint
     */
    function mint(address _to, uint256 _amount) external whenNotPaused {
        if (!allowedMinter[msg.sender]) {
            revert AltoTokenNotAuthorized();
        }
        _mint(_to, _amount);
    }

    /**
     * @notice burns token
     * @param _from address to burn from
     * @param _amount the amount to burn
     */
    function burn(address _from, uint256 _amount) external whenNotPaused {
        if (!allowedBurner[msg.sender]) {
            revert AltoTokenNotAuthorized();
        }
        _burn(_from, _amount);
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
}
