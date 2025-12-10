// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

import {
    IMerkleRootManagerBase,
    IMerkleRootManagerStaticTypes,
    PendingMerkleRoot
} from "@alto/utils/interfaces/IMerkleRootManager.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/// @title Merkle Root Manager
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice An abstract contract for managing merkle roots with timelock functionality
abstract contract MerkleRootManager is IMerkleRootManagerStaticTypes {
    /// @inheritdoc IMerkleRootManagerBase
    bytes32 public merkleRoot;

    /// @inheritdoc IMerkleRootManagerBase
    bytes32 public ipfsHash;

    /// @inheritdoc IMerkleRootManagerBase
    mapping(address => bool) public isMerkleRootUpdater;

    /// @inheritdoc IMerkleRootManagerBase
    uint256 public merkleRootTimelock;

    /// @inheritdoc IMerkleRootManagerStaticTypes
    PendingMerkleRoot public pendingMerkleRoot;

    /// @notice reverts if the caller is not a merkle root updater or the owner
    modifier onlyMerkleRootUpdater() {
        if (!isMerkleRootUpdater[msg.sender] && msg.sender != _getOwner()) {
            revert MerkleRootManagerNotUpdater();
        }
        _;
    }

    modifier onlyMerkleRootManagerOwner() {
        if (msg.sender != _getOwner()) {
            revert MerkleRootManagerNotOwner();
        }
        _;
    }

    /// @notice Abstract function to get the owner address - must be implemented by inheriting contract
    function _getOwner() internal view virtual returns (address);

    /// @inheritdoc IMerkleRootManagerBase
    function submitNewPendingRoot(bytes32 newMerkleRoot, bytes32 newIpfsHash) external onlyMerkleRootUpdater {
        _submitNewPendingRoot(newMerkleRoot, newIpfsHash);
    }

    /// @dev Submits a new pending merkle root.
    /// @param newMerkleRoot The new merkle root.
    /// @param newIpfsHash The new ipfs hash.
    function _submitNewPendingRoot(bytes32 newMerkleRoot, bytes32 newIpfsHash) internal virtual {
        if (newMerkleRoot == pendingMerkleRoot.merkleRoot) {
            revert MerkleRootManagerAlreadyPending();
        }

        if (newMerkleRoot == bytes32(0)) {
            revert MerkleRootManagerInvalidInput();
        }

        pendingMerkleRoot = PendingMerkleRoot({
            merkleRoot: newMerkleRoot, validFrom: block.timestamp + merkleRootTimelock, ipfsHash: newIpfsHash
        });

        emit SubmitPendingMerkleRoot(msg.sender, newMerkleRoot, newIpfsHash);
    }

    /// @inheritdoc IMerkleRootManagerBase
    function acceptPendingRoot(bytes32 merkleRootToAccept) external {
        _acceptPendingRoot(merkleRootToAccept);
    }

    /// @dev Accepts the pending merkle root.
    /// @param merkleRootToAccept The merkle root to accept.
    function _acceptPendingRoot(bytes32 merkleRootToAccept) internal virtual {
        if (pendingMerkleRoot.validFrom == 0) {
            revert MerkleRootManagerRootNotSet();
        }

        if (merkleRootToAccept != pendingMerkleRoot.merkleRoot) {
            revert MerkleRootManagerInvalidInput();
        }

        if (msg.sender != _getOwner() && block.timestamp < pendingMerkleRoot.validFrom) {
            revert MerkleRootManagerTimelockNotExpired();
        }

        merkleRoot = pendingMerkleRoot.merkleRoot;
        ipfsHash = pendingMerkleRoot.ipfsHash;

        delete pendingMerkleRoot;

        emit AcceptPendingMerkleRoot(msg.sender, merkleRoot, ipfsHash);
    }

    /// @inheritdoc IMerkleRootManagerBase
    function revokePendingRoot(bytes32 merkleRootToRevoke) external onlyMerkleRootUpdater {
        if (pendingMerkleRoot.validFrom == 0) {
            revert MerkleRootManagerPendingRootNotSet();
        }

        if (merkleRootToRevoke != pendingMerkleRoot.merkleRoot) {
            revert MerkleRootManagerInvalidInput();
        }

        emit RevokePendingMerkleRoot(msg.sender, pendingMerkleRoot.merkleRoot);

        delete pendingMerkleRoot;
    }

    /// @inheritdoc IMerkleRootManagerBase
    function setMerkleRootTimelock(uint256 newTimelock) external onlyMerkleRootManagerOwner {
        if (newTimelock == merkleRootTimelock) {
            revert MerkleRootManagerInvalidInput();
        }

        _setMerkleRootTimelock(newTimelock);
    }

    /// @inheritdoc IMerkleRootManagerBase
    function setMerkleRootUpdater(address updater, bool active) external onlyMerkleRootManagerOwner {
        if (isMerkleRootUpdater[updater] == active) {
            revert MerkleRootManagerInvalidInput();
        }

        isMerkleRootUpdater[updater] = active;

        emit SetMerkleRootUpdater(updater, active);
    }

    /// @dev Verifies the proof for the given leaf.
    function _verifyProof(bytes32[] calldata proof, bytes32 leaf) internal view returns (bool) {
        if (merkleRoot == bytes32(0)) {
            revert MerkleRootManagerRootNotSet();
        }

        return MerkleProof.verifyCalldata(proof, merkleRoot, leaf);
    }

    /// @dev Sets the `merkleRootTimelock` to `_merkleRootTimelock`.
    function _setMerkleRootTimelock(uint256 _merkleRootTimelock) internal {
        merkleRootTimelock = _merkleRootTimelock;

        emit SetMerkleRootTimelock(_merkleRootTimelock);
    }
}
