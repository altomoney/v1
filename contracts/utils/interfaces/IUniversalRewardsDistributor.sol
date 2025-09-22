// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IAuth} from "@alto/utils/interfaces/IAuth.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";

interface IUniversalRewardsDistributor is IAuth, IPausable {
    error RewardsDistributorInvalidInput();
    error RewardsDistributorUnauthorized();
    error RewardsDistributorNotPaused();

    event ClaimRewardToken(address indexed caller, address indexed onBehalf, address rewardToken, uint256 amount);

    /// @notice Emitted when tokens are withdrawn
    /// @param token The token address
    /// @param to The recipient address
    /// @param amount The amount withdrawn
    event RescueRewardTokens(address indexed token, address indexed to, uint256 amount);

    /// @notice The `amount` of `reward` token already claimed by `user`.
    /// @param user The user's address
    /// @param rewardToken The reward token's address
    /// @return The amount of `rewardToken` already claimed by `user`
    function claimed(address user, address rewardToken) external view returns (uint256);

    /// @notice Claims all of the unclaimed `rewardToken` on behalf of `onBehalf`
    /// @param onBehalf The user's address that's eligible for the claim
    /// @param rewardToken The reward token's address
    /// @param totalRewardTokenAssignedToUser The total amount of `rewardToken` assigned to `onBehalf`
    /// @param proof The merkle proof that validates this claim
    /// @return amount The amount of `rewardToken` claimed in the current claim
    function claim(
        address onBehalf,
        address rewardToken,
        uint256 totalRewardTokenAssignedToUser,
        bytes32[] calldata proof
    ) external returns (uint256 amount);

    /// @notice Withdraws tokens from the contract
    /// @param token The token to withdraw
    /// @dev It is used primarily to withdraw the reward tokens in case of contract change or other reasons.
    /// @dev Contract has to be paused before calling this function.
    function rescueRewardTokens(address token) external;
}
