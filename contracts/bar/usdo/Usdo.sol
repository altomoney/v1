// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {OFT} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFT.sol";
import {OFTCore, IOFT} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTCore.sol";
import {
    MessagingReceipt,
    OFTReceipt,
    SendParam,
    MessagingFee
} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {IUsdo, UsdoMinter, ERC20PermitStruct} from "./IUsdo.sol";
import {ICluster} from "tap-utils/interfaces/common/ICluster.sol";

/**
 * @title USDO Stablecoin
 * @author Alto
 */
contract Usdo is OFT, Pausable, ERC20Permit, IUsdo {
    mapping(address => UsdoMinter) public minterCeiling;

    constructor(address endpoint, address owner)
        ERC20Permit("USDO Stablecoin")
        OFT("USDO Stablecoin", "USDO", endpoint, owner)
    {
        _transferOwnership(owner);
    }

    /**
     * @notice mints USDO
     * @param _to receiver address
     * @param _amount the amount to mint
     */
    function mint(address _to, uint256 _amount) external whenNotPaused {
        if (minterCeiling[msg.sender].minted + _amount > minterCeiling[msg.sender].mintCeiling) {
            revert Usdo_NotAuthorized();
        }
        minterCeiling[msg.sender].minted += _amount;
        _mint(_to, _amount);
    }

    /**
     * @notice burns USDO
     * @param _from address to burn from
     * @param _amount the amount to burn
     */
    function burn(address _from, uint256 _amount) external whenNotPaused {
        if (_amount > minterCeiling[msg.sender].minted) {
            revert Usdo_NotAuthorized();
        }
        minterCeiling[msg.sender].minted -= _amount;
        _burn(_from, _amount);
    }

    /// =====================
    /// Owner
    /// =====================
    /**
     * @notice Un/Pauses this contract.
     */
    function setPause(bool _pauseState) external onlyOwner {
        if (_pauseState) {
            _pause();
        } else {
            _unpause();
        }
    }

    /**
     * @notice sets/unsets address as minter
     * @dev can only be called by the owner
     * @param _for role receiver
     * @param _mintCeiling the mint ceiling
     */
    function setMinterCeiling(address _for, uint256 _mintCeiling) external onlyOwner {
        minterCeiling[_for].mintCeiling = _mintCeiling;
        emit SetMinterCeiling(_for, _mintCeiling);
    }
}
