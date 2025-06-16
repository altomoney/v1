// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

library RewardErrorsLib {
    error NotOwner();
    error NotUpdaterRole();
    error NotAltoRewardsOptions();
    error AlreadyPending();
    error NoPendingRoot();
    error TimelockNotExpired();
    error RootNotSet();
    error InvalidProofOrExpired();
    error AlreadySet();
    error UnauthorizedRootChange();
    error ZeroAddress();
    error ExpiredClaim();
    error InvalidPurchaseAmount();
    error InvalidPaymentToken();
    error InvalidOracleDecimals();
    error PriceNotSet();
    error InvalidOraclePrice();
    error InvalidPrice();
    error InvalidDiscount();
    error LockNotSet();
}
