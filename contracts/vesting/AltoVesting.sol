// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {MerkleRootManager} from "@alto/utils/MerkleRootManager.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Auth} from "@alto/utils/Auth.sol";
import {Pausable} from "@alto/utils/Pausable.sol";
import {IAltoVesting, VestingInfo} from "@alto/vesting/interfaces/IAltoVesting.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";

/// @title Alto Vesting Contract
/// @author Pearl Labs
/// @custom:contact security@altofoundation.org
/// @notice A contract for vesting tokens to users determined by a merkle tree.
contract AltoVesting is IAltoVesting, MerkleRootManager, Ownable2Step, Auth, Pausable {
    using SafeERC20 for IERC20;

    /// @inheritdoc IAltoVesting
    mapping(address user => uint256 amount) public claimed;

    /// @inheritdoc IAltoVesting
    bool public immutable IS_VESTING_UPDATABLE;

    /// @inheritdoc IAltoVesting
    address public immutable VESTING_TOKEN;

    /// @notice Initializes the contract.
    /// @param _owner The initial owner of the contract.
    /// @param initialTimelock The initial timelock of the contract.
    /// @param _isVestingUpdatable The flag that indicates whether the vesting terms can be updated.
    /// @param _vestingToken The address of the vesting token.
    constructor(
        address _owner,
        uint256 initialTimelock,
        bool _isVestingUpdatable,
        address _vestingToken,
        bytes32 _merkleRoot,
        bytes32 _ipfsHash
    ) Ownable(_owner) {
        if (_vestingToken == address(0)) {
            revert AltoVestingInvalidInput();
        }

        VESTING_TOKEN = _vestingToken;
        IS_VESTING_UPDATABLE = _isVestingUpdatable;

        // set the timelock if the vesting is updatable, otherwise accept the merkle root
        // timelock is not needed for non-updatable vesting
        if (_isVestingUpdatable) {
            // first set the timelock and then submit the new pending root
            _setMerkleRootTimelock(initialTimelock);
            MerkleRootManager._submitNewPendingRoot(_merkleRoot, _ipfsHash);
        } else {
            MerkleRootManager._submitNewPendingRoot(_merkleRoot, _ipfsHash);
            _acceptPendingRoot(_merkleRoot);
        }
    }

    /// @inheritdoc IAltoVesting
    function claim(address onBehalf, VestingInfo calldata vestingInfo, bytes32[] calldata proof)
        external
        whenNot(PAUSE_TYPE)
        returns (uint256 amount)
    {
        if (!_isSenderAuthorized(onBehalf)) {
            revert AltoVestingUnauthorized();
        }

        // verify that the vesting duration is not zero and vesting has started
        if (vestingInfo.vestingDuration == 0 || block.timestamp <= vestingInfo.startAt) {
            revert AltoVestingInvalidInput();
        }

        // verify whether the claim is valid based on address and vesting info
        if (!_verifyProof(proof, keccak256(bytes.concat(keccak256(abi.encode(onBehalf, vestingInfo)))))) {
            revert AltoVestingInvalidInput();
        }

        // calculate the amount vested for the given vesting info
        uint256 vestedAmount = _calculateAmountVested(vestingInfo);

        // check if the user has already claimed the vested amount
        if (claimed[onBehalf] >= vestedAmount) {
            revert AltoVestingNotEnoughVestedAmount();
        }

        // calculate the amount to be claimed
        amount = vestedAmount - claimed[onBehalf];

        claimed[onBehalf] = vestedAmount;

        IERC20(VESTING_TOKEN).safeTransfer(onBehalf, amount);

        emit ClaimVesting(msg.sender, onBehalf, amount);
    }

    /// @dev Calculates the amount vested for the given vesting info.
    function _calculateAmountVested(VestingInfo calldata vestingInfo) internal view returns (uint256) {
        if (block.timestamp >= vestingInfo.startAt + vestingInfo.vestingDuration) {
            return vestingInfo.totalVestingAmount;
        }

        return (vestingInfo.totalVestingAmount * (block.timestamp - vestingInfo.startAt)) / vestingInfo.vestingDuration;
    }

    /// @inheritdoc MerkleRootManager
    function _submitNewPendingRoot(bytes32 newMerkleRoot, bytes32 newIpfsHash) internal override {
        if (IS_VESTING_UPDATABLE) {
            MerkleRootManager._submitNewPendingRoot(newMerkleRoot, newIpfsHash);
        } else {
            revert AltoVestingNotUpdatable();
        }
    }

    /// @inheritdoc MerkleRootManager
    function _getOwner() internal view override returns (address) {
        return owner();
    }

    /// @inheritdoc Pausable
    function setPauser(address pauser, bytes32 pauseType, bool status) external override(Pausable) onlyOwner {
        _setPauser(pauser, pauseType, status);
    }

    /// @inheritdoc IAltoVesting
    function rescueVestingTokens() external onlyOwner {
        if (!paused[PAUSE_TYPE]) {
            revert AltoVestingNotPaused();
        }

        uint256 balance = IERC20(VESTING_TOKEN).balanceOf(address(this));

        if (balance != 0) {
            IERC20(VESTING_TOKEN).safeTransfer(msg.sender, balance);
            emit RescueVestingTokens(VESTING_TOKEN, msg.sender, balance);
        }
    }
}
