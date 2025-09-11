// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {RewardsDistributorCommon} from "./RewardsDistributorCommon.t.sol";
import {AltoRewardsDistributor} from "@alto/rewards/AltoRewardsDistributor.sol";
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

contract AltoRewardsDistributorRevokeAdapter is RewardsDistributorCommon {
    function test_RevertWhen_CallerIsNotOwner() external {
        MockAdapter adapter = new MockAdapter();

        // First whitelist the adapter
        vm.prank(OWNER);
        distributor.whitelistAdapter(address(adapter));

        vm.prank(ALICE);
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, ALICE));
        distributor.revokeAdapter(address(adapter));
    }

    modifier whenCallerIsOwner() {
        _;
    }

    function test_RevertWhen_AdapterIsNotInWhitelist() external whenCallerIsOwner {
        MockAdapter adapter = new MockAdapter();

        vm.prank(OWNER);
        // it should revert
        vm.expectRevert(IRewardsErrors.AltoRewardsDistributorInvalidInput.selector);
        distributor.revokeAdapter(address(adapter));
    }

    function test_WhenAdapterIsInWhitelist() external whenCallerIsOwner {
        MockAdapter adapter1 = new MockAdapter();
        MockAdapter adapter2 = new MockAdapter();
        MockAdapter adapter3 = new MockAdapter();

        // Whitelist multiple adapters to test array integrity
        vm.startPrank(OWNER);
        distributor.whitelistAdapter(address(adapter1));
        distributor.whitelistAdapter(address(adapter2));
        distributor.whitelistAdapter(address(adapter3));
        vm.stopPrank();

        // it should emit RevokeAdapter event
        vm.expectEmit(true, false, false, false);
        emit IRewardsEvents.RevokeAdapter(address(adapter2));

        vm.prank(OWNER);
        distributor.revokeAdapter(address(adapter2));

        // Verify adapter2 is removed and array integrity is maintained
        // We can test this by trying to revoke it again (should fail)
        vm.prank(OWNER);
        vm.expectRevert(IRewardsErrors.AltoRewardsDistributorInvalidInput.selector);
        distributor.revokeAdapter(address(adapter2));

        // Verify other adapters can still be revoked
        vm.prank(OWNER);
        vm.expectEmit(true, false, false, false);
        emit IRewardsEvents.RevokeAdapter(address(adapter1));
        distributor.revokeAdapter(address(adapter1));

        vm.prank(OWNER);
        vm.expectEmit(true, false, false, false);
        emit IRewardsEvents.RevokeAdapter(address(adapter3));
        distributor.revokeAdapter(address(adapter3));
    }

    function test_WhenRevokingLastAdapter() external whenCallerIsOwner {
        MockAdapter adapter = new MockAdapter();

        // Whitelist single adapter
        vm.prank(OWNER);
        distributor.whitelistAdapter(address(adapter));

        // it should emit RevokeAdapter event
        vm.expectEmit(true, false, false, false);
        emit IRewardsEvents.RevokeAdapter(address(adapter));

        vm.prank(OWNER);
        distributor.revokeAdapter(address(adapter));

        // Verify adapter is removed
        vm.prank(OWNER);
        vm.expectRevert(IRewardsErrors.AltoRewardsDistributorInvalidInput.selector);
        distributor.revokeAdapter(address(adapter));
    }

    function test_WhenRevokingFirstAdapterInList() external whenCallerIsOwner {
        MockAdapter adapter1 = new MockAdapter();
        MockAdapter adapter2 = new MockAdapter();

        // Whitelist adapters
        vm.startPrank(OWNER);
        distributor.whitelistAdapter(address(adapter1));
        distributor.whitelistAdapter(address(adapter2));
        vm.stopPrank();

        // Revoke first adapter (it should maintain array integrity by swapping with last)
        vm.prank(OWNER);
        vm.expectEmit(true, false, false, false);
        emit IRewardsEvents.RevokeAdapter(address(adapter1));
        distributor.revokeAdapter(address(adapter1));

        // Verify adapter1 is removed but adapter2 still exists
        vm.prank(OWNER);
        vm.expectRevert(IRewardsErrors.AltoRewardsDistributorInvalidInput.selector);
        distributor.revokeAdapter(address(adapter1));

        // adapter2 should still be revokable
        vm.prank(OWNER);
        distributor.revokeAdapter(address(adapter2));
    }
}
