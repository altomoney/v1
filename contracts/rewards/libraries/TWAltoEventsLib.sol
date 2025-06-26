// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

library TWAltoEventsLib {
    event Participate(
        address indexed participant, uint256 bucketId, uint256 lockAmount, uint256 multiplier, uint256 expiry
    );
    event ExitPosition(uint256 indexed bucketId, address indexed releasedTo, uint256 amount);
    event NewDelegate(address indexed participant, uint256 indexed bucketId, address indexed delegatee);

    event RescueMode(bool _rescueMode);
    event SetEmergencySweepCooldown(uint256 emergencySweepCooldown);
    event ActivateEmergencySweep();
}
