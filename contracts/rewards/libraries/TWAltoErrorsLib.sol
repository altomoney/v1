// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

library TWAltoErrorsLib {
    error NotAuthorized();
    error AdvanceWeekFirst();
    error NotValid();
    error Registered();
    error TokenLimitReached();
    error NotApproved(uint256 tokenId, address spender);
    error LockNotExpired();
    error DurationNotMultiple(); // Lock duration should be a multiple of 1 EPOCH
    error EmergencySweepCooldownNotReached();
    error RescueModeActive();
    error EmergencySweepActivated();
}
