// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

library TWAltoEventsLib {
    event Participate(
        address indexed participant,
        uint256 bucketId,
        uint256 lockAmount,
        uint256 multiplier,
        uint256 expiry,
        bool isReused
    );
    event ExitPosition(uint256 indexed bucketId, address indexed releasedTo, uint256 amount);

    event RescueMode(bool _rescueMode);
    event SetEmergencySweepCooldown(uint256 emergencySweepCooldown);
    event ActivateEmergencySweep();
    event AdvanceEpoch(uint256 indexed epoch, uint256 indexed lastProcessedEpoch);
}
