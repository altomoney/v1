// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

library TWAltoErrorsLib {
    error NotAuthorized();
    error NotValid();
    error LockNotExpired();
    error EmergencySweepCooldownNotReached();
    error RescueModeActive();
    error EmergencySweepActivated();
}
