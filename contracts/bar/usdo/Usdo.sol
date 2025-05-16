// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {OFT} from "@alto/utils/layerzero/OFT.sol";
import {IUsdo} from "./IUsdo.sol";
import {ICluster} from "@alto/utils/interfaces/common/ICluster.sol";

import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title USDO Stablecoin
 * @author Alto
 */
contract Usdo is Ownable, Pausable, OFT, IUsdo {
    uint256 public fees;

    address public flashLoanHelper;

    ICluster public cluster;

    mapping(address => bool) public allowedMinter;
    mapping(address => bool) public allowedBurner;

    constructor(address endpoint, address owner, address clusterAddress)
        OFT("USDO", "USDO", endpoint, owner)
        Ownable(owner)
    {
        cluster = ICluster(clusterAddress);
    }

    /// =====================
    /// View
    /// =====================
    function getCluster() public view returns (ICluster) {
        return cluster;
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
            revert Usdo_NotAuthorized();
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
            revert Usdo_NotAuthorized();
        }
        _burn(_from, _amount);
    }

    /**
     * @notice registeres flashloan fees
     * @dev can only be called by the `FlashloanHelper` contract
     * @param _fee fees amount
     */
    function addFlashloanFee(uint256 _fee) external {
        if (msg.sender != flashLoanHelper) revert Usdo_NotAuthorized();
        fees += _fee;
    }

    /// =====================
    /// Owner
    /// =====================
    /**
     * @notice Un/Pauses this contract.
     */
    function setPause(bool _pauseState) external {
        if (!cluster.hasRole(msg.sender, keccak256("PAUSABLE")) && msg.sender != owner()) {
            revert Usdo_NotAuthorized();
        }
        if (_pauseState) {
            _pause();
        } else {
            _unpause();
        }
    }

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

    /**
     * @notice Sets the cluster address.
     * @param _cluster The address of the cluster.
     */
    function setCluster(address _cluster) external onlyOwner {
        cluster = ICluster(_cluster);
    }
}
