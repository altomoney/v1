// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

library TWAltoEventsLib {
    event AddRewardToken(address indexed rewardTokenAddress, uint256 rewardTokenIndex);
    event DistributeReward(
        address indexed rewardTokenAddress, address indexed from, uint256 amount, uint256 rewardTokenIndex
    );

    event ClaimReward(
        address indexed rewardTokenAddress,
        address indexed to,
        uint256 indexed twTapTokenId,
        uint256 amount,
        uint256 rewardTokenIndex
    );
    event Participate(
        address indexed participant,
        uint256 mintedTokenId,
        uint256 tapAmount,
        uint256 multiplier,
        uint256 expiry,
        uint256 bucketId
    );
    event ExitPosition(uint256 indexed twTapTokenId, address indexed releasedTo, uint256 amount);
    event NewDelegate(address indexed participant, uint256 indexed bucketId, address indexed delegatee);

    event LogMaxRewardsLength(uint256 _oldLength, uint256 _newLength, uint256 _currentLength);
    event RescueMode(bool _rescueMode);
    event SetCluster(address _cluster);
    event EmergencySweepLocks();
    event EmergencySweepRewards();
    event SetEmergencySweepCooldown(uint256 emergencySweepCooldown);
    event ActivateEmergencySweep();
    event SetTapOft(address tapOFT);
}
