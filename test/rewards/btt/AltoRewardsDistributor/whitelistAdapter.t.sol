// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {RewardsDistributorCommon} from "./RewardsDistributorCommon.t.sol";
import {IRewardsEvents, IRewardsErrors} from "@alto/rewards/interfaces/IRewardsDistributor.sol";
import {IRewardsAdapter, BonusRewardInfo} from "@alto/rewards/interfaces/IRewardsAdapter.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MockAdapter is IRewardsAdapter {
    function getBonusRewardInfo(address) external pure returns (BonusRewardInfo memory) {
        return BonusRewardInfo({
            bonusDiscount: 0.05 ether, // 5%
            paymentTokenShare: 0.1 ether, // 10%
            paymentTokenShareReceiver: address(0x123)
        });
    }
}

contract AltoRewardsDistributorWhitelistAdapter is RewardsDistributorCommon {
    function test_RevertWhen_CallerIsNotOwner() external {
        MockAdapter adapter = new MockAdapter();

        vm.prank(ALICE);
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, ALICE));
        distributor.whitelistAdapter(address(adapter));
    }

    modifier whenCallerIsOwner() {
        _;
    }

    function test_RevertWhen_AdapterIsZeroAddress() external whenCallerIsOwner {
        vm.prank(OWNER);
        // it should revert
        vm.expectRevert(IRewardsErrors.AltoRewardsDistributorInvalidInput.selector);
        distributor.whitelistAdapter(address(0));
    }

    function test_RevertWhen_AdapterIsAlreadyWhitelisted() external whenCallerIsOwner {
        MockAdapter adapter = new MockAdapter();

        // First whitelist
        vm.prank(OWNER);
        distributor.whitelistAdapter(address(adapter));

        // Try to whitelist again
        vm.prank(OWNER);
        // it should revert
        vm.expectRevert(IRewardsErrors.AltoRewardsDistributorInvalidInput.selector);
        distributor.whitelistAdapter(address(adapter));
    }

    function test_RevertWhen_AdaptersWhitelistLengthExceedsMAX_ADAPTERS_WHITELIST() external whenCallerIsOwner {
        uint256 maxAdapters = distributor.MAX_ADAPTERS_WHITELIST();

        // Fill up to max
        for (uint256 i = 0; i < maxAdapters; i++) {
            MockAdapter adapter = new MockAdapter();
            vm.prank(OWNER);
            distributor.whitelistAdapter(address(adapter));
        }

        // Try to add one more
        MockAdapter extraAdapter = new MockAdapter();
        vm.prank(OWNER);
        // it should revert
        vm.expectRevert(IRewardsErrors.AltoRewardsDistributorInvalidInput.selector);
        distributor.whitelistAdapter(address(extraAdapter));
    }

    function test_WhenAdapterIsValidAndNotWhitelisted() external whenCallerIsOwner {
        MockAdapter adapter = new MockAdapter();

        // it should emit WhitelistAdapter event
        vm.expectEmit(true, false, false, false);
        emit IRewardsEvents.WhitelistAdapter(address(adapter));

        vm.prank(OWNER);
        distributor.whitelistAdapter(address(adapter));

        // it should add adapter to whitelist
        // Note: We can't directly check the whitelist array, but we can verify
        // by trying to revoke it (which would fail if not whitelisted)
        vm.prank(OWNER);
        vm.expectEmit(true, false, false, false);
        emit IRewardsEvents.RevokeAdapter(address(adapter));
        distributor.revokeAdapter(address(adapter));
    }
}
