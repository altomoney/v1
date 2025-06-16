// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

library RewardEventsLib {
    event PendingRootSet(address indexed updater, bytes32 indexed root, bytes32 ipfsHash);
    event RootSet(bytes32 indexed root, bytes32 ipfsHash);
    event PendingRootRevoked(address indexed updater);
    event PurchaseClaimed(address indexed account, address indexed reward, uint256 amount);
    event OwnerSet(address indexed owner);
    event TimelockSet(uint256 timelock);
    event RootUpdaterSet(address indexed updater, bool active);
    event AltoRewardsOptionsSet(address indexed altoRewardsOptions);
    event PaymentTokenSet(address indexed token, address indexed oracle);
    event RewardPriceSet(uint256 price);
    event DiscountSet(uint256 discount);
    event LockBonusDiscountSet(uint256 lockBonusDiscount);
    event LockSet(address indexed lock);
    event PaymentTokenWithdrawn(address indexed token, address indexed to, uint256 amount);
}
