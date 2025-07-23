// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

struct BonusRewardInfo {
    uint256 bonusDiscount;
    uint256 paymentTokenShare;
    address paymentTokenShareReceiver;
}

interface IRewardsAdapter {
    /// @notice Returns the bonus reward and payment token share for a user
    /// @param user The user address
    /// @return The bonus reward and payment token share
    /// @dev this has to always return and never revert
    function getBonusRewardInfo(address user) external view returns (BonusRewardInfo memory);
}
