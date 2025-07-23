// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {NftRewardsAdapterCommon} from "../NftRewardsAdapterCommon.t.sol";
import {AltoNftRewardsAdapter} from "@alto/rewards/AltoNftRewardsAdapter.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract AltoNftRewardsAdapterSetBonusDiscount is NftRewardsAdapterCommon {
    function test_RevertWhen_CallerIsNotOwner() external {
        uint256 newDiscount = 0.08 ether; // 8%

        vm.prank(ALICE);
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, ALICE));
        adapter.setBonusDiscount(newDiscount);
    }

    modifier whenCallerIsOwner() {
        _;
    }

    function test_RevertWhen_BonusDiscountIsGreaterThan0_1Ether() external whenCallerIsOwner {
        uint256 invalidDiscount = 0.1 ether + 1;

        vm.prank(OWNER);
        // it should revert
        vm.expectRevert(AltoNftRewardsAdapter.AltoNftRewardsInvalidInput.selector);
        adapter.setBonusDiscount(invalidDiscount);
    }

    function test_WhenSettingNormalDiscountValue() external whenCallerIsOwner {
        uint256 newDiscount = 0.08 ether; // 8%
        uint256 oldDiscount = adapter.bonusDiscount();

        // it should emit BonusDiscountSet event
        vm.expectEmit(false, false, false, true);
        emit AltoNftRewardsAdapter.BonusDiscountSet(newDiscount);

        vm.prank(OWNER);
        adapter.setBonusDiscount(newDiscount);

        // it should update bonus discount
        assertEq(adapter.bonusDiscount(), newDiscount);
        assertNotEq(adapter.bonusDiscount(), oldDiscount);
    }

    function test_WhenSettingZeroDiscount() external whenCallerIsOwner {
        uint256 zeroDiscount = 0;

        // it should emit BonusDiscountSet event
        vm.expectEmit(false, false, false, true);
        emit AltoNftRewardsAdapter.BonusDiscountSet(zeroDiscount);

        vm.prank(OWNER);
        adapter.setBonusDiscount(zeroDiscount);

        // it should update bonus discount
        assertEq(adapter.bonusDiscount(), zeroDiscount);
    }

    function test_WhenSettingMaximumDiscount() external whenCallerIsOwner {
        uint256 maxDiscount = 0.1 ether; // 10%

        // it should emit BonusDiscountSet event
        vm.expectEmit(false, false, false, true);
        emit AltoNftRewardsAdapter.BonusDiscountSet(maxDiscount);

        vm.prank(OWNER);
        adapter.setBonusDiscount(maxDiscount);

        // it should update bonus discount
        assertEq(adapter.bonusDiscount(), maxDiscount);
    }

    function test_WhenUpdatingDiscountMultipleTimes() external whenCallerIsOwner {
        uint256 discount1 = 0.02 ether; // 2%
        uint256 discount2 = 0.09 ether; // 9%

        // Set first discount
        vm.expectEmit(false, false, false, true);
        emit AltoNftRewardsAdapter.BonusDiscountSet(discount1);

        vm.prank(OWNER);
        adapter.setBonusDiscount(discount1);

        assertEq(adapter.bonusDiscount(), discount1);

        // Set second discount
        vm.expectEmit(false, false, false, true);
        emit AltoNftRewardsAdapter.BonusDiscountSet(discount2);

        vm.prank(OWNER);
        adapter.setBonusDiscount(discount2);

        assertEq(adapter.bonusDiscount(), discount2);
        assertNotEq(adapter.bonusDiscount(), discount1);
    }
}
