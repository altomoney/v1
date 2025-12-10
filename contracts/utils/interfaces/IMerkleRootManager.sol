// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice The pending root struct for a merkle tree distribution during the timelock.
struct PendingMerkleRoot {
    /// @dev The submitted pending root.
    bytes32 merkleRoot;
    /// @dev The timestamp from which the pending root can be accepted.
    uint256 validFrom;
    /// @dev The ipfs hash used for distribution
    bytes32 ipfsHash;
}

/// @title IMerkleRootManagerErrors
/// @notice Interface containing all error definitions for the MerkleRootManager
interface IMerkleRootManagerErrors {
    /// @notice Error thrown when executor does not have the merkle root updater role
    error MerkleRootManagerNotUpdater();
    /// @notice Error thrown when the input is invalid
    error MerkleRootManagerInvalidInput();
    /// @notice Error thrown when a pending root already exists with the same values
    error MerkleRootManagerAlreadyPending();
    /// @notice Error thrown when the timelock has not expired yet
    error MerkleRootManagerTimelockNotExpired();
    /// @notice Error thrown when the pending root is not set
    error MerkleRootManagerPendingRootNotSet();
    /// @notice Error thrown when the merkle root is not set
    error MerkleRootManagerRootNotSet();
    /// @notice Error thrown when the caller is not the owner
    error MerkleRootManagerNotOwner();
}

/// @title IMerkleRootManagerEvents
/// @notice Interface containing all event definitions for the MerkleRootManager
interface IMerkleRootManagerEvents {
    /// @notice Emitted when a pending root is submitted
    /// @param updater The address that submitted the pending root
    /// @param root The new merkle root
    event SubmitPendingMerkleRoot(address indexed updater, bytes32 indexed root, bytes32 indexed ipfsHash);

    /// @notice Emitted when a root is accepted and set
    /// @param executor The address that executed the acceptance
    /// @param root The new merkle root
    event AcceptPendingMerkleRoot(address indexed executor, bytes32 indexed root, bytes32 indexed ipfsHash);

    /// @notice Emitted when a pending root is revoked
    /// @param updater The address that revoked the pending root
    /// @param root The revoked merkle root
    event RevokePendingMerkleRoot(address indexed updater, bytes32 indexed root);

    /// @notice Emitted when the timelock is updated
    /// @param timelock The new timelock duration in seconds
    event SetMerkleRootTimelock(uint256 timelock);

    /// @notice Emitted when a root updater is added or removed
    /// @param updater The updater address
    /// @param active Whether the updater is active or not
    event SetMerkleRootUpdater(address indexed updater, bool active);
}

/// @title IMerkleRootManager
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice Interface for managing merkle roots with timelock functionality
interface IMerkleRootManagerBase is IMerkleRootManagerErrors, IMerkleRootManagerEvents {
    /// @notice The merkle root used for distribution
    function merkleRoot() external view returns (bytes32);

    /// @notice The ipfs hash used for distribution
    function ipfsHash() external view returns (bytes32);

    /// @notice Returns whether an address is allowed to submit a new merkle root
    /// @param updater The address to check
    /// @return true if the address is allowed to submit a new merkle root
    function isMerkleRootUpdater(address updater) external view returns (bool);

    /// @notice The time after which a pending root can be accepted since it was submitted
    function merkleRootTimelock() external view returns (uint256);

    /// @notice Submits a new merkle root
    /// @param newMerkleRoot The new merkle root
    function submitNewPendingRoot(bytes32 newMerkleRoot, bytes32 newIpfsHash) external;

    /// @notice Accepts and sets the current pending merkle root
    /// @param merkleRootToAccept The root to accept (0 to accept the pending root)
    /// @dev Can only be called after the timelock has expired, or immediately by owner
    function acceptPendingRoot(bytes32 merkleRootToAccept) external;

    /// @notice Revokes the pending root
    /// @param merkleRootToRevoke The root to revoke (0 to revoke the pending root)
    /// @dev Can be frontrun with acceptPendingRoot if timelock has passed
    function revokePendingRoot(bytes32 merkleRootToRevoke) external;

    /// @notice Sets the timelock duration for root updates
    /// @param newTimelock The new timelock duration in seconds
    function setMerkleRootTimelock(uint256 newTimelock) external;

    /// @notice Sets or removes a root updater
    /// @param updater The address of the root updater
    /// @param active Whether the root updater should be active
    function setMerkleRootUpdater(address updater, bool active) external;
}

interface IMerkleRootManagerStaticTypes is IMerkleRootManagerBase {
    /// @notice Returns the pending merkle root and the timestamp from which it can be accepted
    function pendingMerkleRoot() external view returns (bytes32 root, uint256 validFrom, bytes32 ipfsHash);
}

interface IMerkleRootManager is IMerkleRootManagerBase {
    /// @notice Returns the pending merkle root and the timestamp from which it can be accepted
    function pendingMerkleRoot() external view returns (PendingMerkleRoot memory);
}
