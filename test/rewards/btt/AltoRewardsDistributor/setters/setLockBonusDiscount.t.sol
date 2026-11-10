// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {RewardsDistributorCommon} from "../RewardsDistributorCommon.t.sol";
import {IRewardsEvents, IRewardsErrors} from "@alto/rewards/interfaces/IRewardsDistributor.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract AltoRewardsDistributorSetLockBonusDiscount is RewardsDistributorCommon {
    function test_RevertWhen_CallerIsNotOwner() external {
        uint256 newDiscount = 0.1 ether; // 10%

        vm.prank(ALICE);
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, ALICE));
        distributor.setLockBonusDiscount(newDiscount);
    }

    modifier whenCallerIsOwner() {
        _;
    }

    function test_RevertWhen_NewLockBonusDiscountIsGreaterThanMAX_DISCOUNT() external whenCallerIsOwner {
        uint256 maxDiscount = distributor.MAX_DISCOUNT();
        uint256 invalidDiscount = maxDiscount + 1;

        vm.prank(OWNER);
        // it should revert
        vm.expectRevert(IRewardsErrors.AltoRewardsDistributorInvalidInput.selector);
        distributor.setLockBonusDiscount(invalidDiscount);
    }

    function test_WhenNewLockBonusDiscountIsValid() external whenCallerIsOwner {
        uint256 newDiscount = 0.2 ether; // 20%
        uint256 oldDiscount = distributor.lockBonusDiscount();

        // it should emit SetLockBonusDiscount event
        vm.expectEmit(false, false, false, true);
        emit IRewardsEvents.SetLockBonusDiscount(newDiscount);

        vm.prank(OWNER);
        distributor.setLockBonusDiscount(newDiscount);

        // it should update lock bonus discount
        assertEq(distributor.lockBonusDiscount(), newDiscount);
        assertNotEq(distributor.lockBonusDiscount(), oldDiscount); // sanity check
    }

    function test_WhenSettingZeroDiscount() external whenCallerIsOwner {
        uint256 zeroDiscount = 0;

        // it should emit SetLockBonusDiscount event
        vm.expectEmit(false, false, false, true);
        emit IRewardsEvents.SetLockBonusDiscount(zeroDiscount);

        vm.prank(OWNER);
        distributor.setLockBonusDiscount(zeroDiscount);

        // it should update lock bonus discount
        assertEq(distributor.lockBonusDiscount(), zeroDiscount);
    }

    function test_WhenSettingMaximumDiscount() external whenCallerIsOwner {
        uint256 maxDiscount = distributor.MAX_DISCOUNT();

        // it should emit SetLockBonusDiscount event
        vm.expectEmit(false, false, false, true);
        emit IRewardsEvents.SetLockBonusDiscount(maxDiscount);

        vm.prank(OWNER);
        distributor.setLockBonusDiscount(maxDiscount);

        // it should update lock bonus discount
        assertEq(distributor.lockBonusDiscount(), maxDiscount);
    }

    function test_WhenUpdatingDiscountMultipleTimes() external whenCallerIsOwner {
        uint256 discount1 = 0.1 ether; // 10%
        uint256 discount2 = 0.3 ether; // 30%

        // Set first discount
        vm.expectEmit(false, false, false, true);
        emit IRewardsEvents.SetLockBonusDiscount(discount1);

        vm.prank(OWNER);
        distributor.setLockBonusDiscount(discount1);

        assertEq(distributor.lockBonusDiscount(), discount1);

        // Set second discount
        vm.expectEmit(false, false, false, true);
        emit IRewardsEvents.SetLockBonusDiscount(discount2);

        vm.prank(OWNER);
        distributor.setLockBonusDiscount(discount2);

        assertEq(distributor.lockBonusDiscount(), discount2);
        assertNotEq(distributor.lockBonusDiscount(), discount1); // sanity check
    }
}
