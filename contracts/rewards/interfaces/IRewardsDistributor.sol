// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice The pending root struct for a merkle tree distribution during the timelock.
struct PendingRoot {
    /// @dev The submitted pending root.
    bytes32 root;
    /// @dev The optional ipfs hash containing metadata about the root (e.g. the merkle tree itself).
    bytes32 ipfsHash;
    /// @dev The timestamp at which the pending root can be accepted.
    uint256 validAt;
}

interface IOracle {
    function latestAnswer() external view returns (int256);
    function decimals() external view returns (uint8);
}

interface ILock {
    function lock(uint256 amount, address to) external;
}

interface IRewardsDistributorBase {
    // user facing functions
    function claimPurchase(
        uint256 availableToPurchase,
        bytes32[] calldata proof,
        uint256 purchaseAmount,
        address paymentToken,
        bool shouldLock
    ) external returns (uint256 amount);
    function purchased(address) external view returns (uint256);
    // getters
    function root() external view returns (bytes32);
    function timelock() external view returns (uint256);
    function ipfsHash() external view returns (bytes32);
    function rewardToken() external view returns (address);
    function isUpdater(address) external view returns (bool);
    function assigned(address) external view returns (uint256);
    function paymentTokens(address) external view returns (address);
    function rewardPrice() external view returns (uint256);
    function discount() external view returns (uint256);
    function lockBonusDiscount() external view returns (uint256);
    function lockContract() external view returns (address);
    // admin ops functions
    function withdrawTokens(address token, address to, uint256 amount) external;
    // root admin functions
    function acceptRoot() external;
    function setTimelock(uint256 newTimelock) external;
    function setRootUpdater(address updater, bool active) external;
    function revokePendingRoot() external;
    function submitRoot(bytes32 newRoot, bytes32 ipfsHash) external;
    // admin setter functions
    function setPaymentToken(address token, address oracle) external;
    function setRewardPrice(uint256 newPrice) external;
    function setDiscount(uint256 newDiscount) external;
    function setLockBonusDiscount(uint256 newLockBonusDiscount) external;
    function setLockContract(address newLockContract) external;
}

/// @dev This interface is inherited by the RewardsDistributor so that function signatures are checked by the
/// @dev Consider using the IRewardsDistributor interface instead of this one.
interface IRewardsDistributorStaticTyping is IRewardsDistributorBase {
    function pendingRoot() external view returns (bytes32 root, bytes32 ipfsHash, uint256 validAt);
}

/// @title IRewardsDistributor
/// @dev Use this interface for RewardsDistributor to have access to all the functions with the appropriate
/// function signatures.
interface IRewardsDistributor is IRewardsDistributorBase {
    function pendingRoot() external view returns (PendingRoot memory);
}
