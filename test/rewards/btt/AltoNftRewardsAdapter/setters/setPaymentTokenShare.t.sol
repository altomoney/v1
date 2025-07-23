// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {NftRewardsAdapterCommon} from "../NftRewardsAdapterCommon.t.sol";
import {AltoNftRewardsAdapter} from "@alto/rewards/AltoNftRewardsAdapter.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract AltoNftRewardsAdapterSetPaymentTokenShare is NftRewardsAdapterCommon {
    function test_RevertWhen_CallerIsNotOwner() external {
        uint256 newShare = 0.07 ether; // 7%

        vm.prank(ALICE);
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, ALICE));
        adapter.setPaymentTokenShare(newShare);
    }

    modifier whenCallerIsOwner() {
        _;
    }

    function test_RevertWhen_PaymentTokenShareIsGreaterThan0_1Ether() external whenCallerIsOwner {
        uint256 invalidShare = 0.1 ether + 1;

        vm.prank(OWNER);
        // it should revert
        vm.expectRevert(AltoNftRewardsAdapter.AltoNftRewardsInvalidInput.selector);
        adapter.setPaymentTokenShare(invalidShare);
    }

    function test_WhenSettingNormalShareValue() external whenCallerIsOwner {
        uint256 newShare = 0.07 ether; // 7%
        uint256 oldShare = adapter.paymentTokenShare();

        // it should emit PaymentTokenShareSet event
        vm.expectEmit(false, false, false, true);
        emit AltoNftRewardsAdapter.PaymentTokenShareSet(newShare);

        vm.prank(OWNER);
        adapter.setPaymentTokenShare(newShare);

        // it should update payment token share
        assertEq(adapter.paymentTokenShare(), newShare);
        assertNotEq(adapter.paymentTokenShare(), oldShare);
    }

    function test_WhenSettingZeroShare() external whenCallerIsOwner {
        uint256 zeroShare = 0;

        // it should emit PaymentTokenShareSet event
        vm.expectEmit(false, false, false, true);
        emit AltoNftRewardsAdapter.PaymentTokenShareSet(zeroShare);

        vm.prank(OWNER);
        adapter.setPaymentTokenShare(zeroShare);

        // it should update payment token share
        assertEq(adapter.paymentTokenShare(), zeroShare);
    }

    function test_WhenSettingMaximumShare() external whenCallerIsOwner {
        uint256 maxShare = 0.1 ether; // 10%

        // it should emit PaymentTokenShareSet event
        vm.expectEmit(false, false, false, true);
        emit AltoNftRewardsAdapter.PaymentTokenShareSet(maxShare);

        vm.prank(OWNER);
        adapter.setPaymentTokenShare(maxShare);

        // it should update payment token share
        assertEq(adapter.paymentTokenShare(), maxShare);
    }

    function test_WhenUpdatingShareMultipleTimes() external whenCallerIsOwner {
        uint256 share1 = 0.02 ether; // 2%
        uint256 share2 = 0.08 ether; // 8%

        // Set first share
        vm.expectEmit(false, false, false, true);
        emit AltoNftRewardsAdapter.PaymentTokenShareSet(share1);

        vm.prank(OWNER);
        adapter.setPaymentTokenShare(share1);

        assertEq(adapter.paymentTokenShare(), share1);

        // Set second share
        vm.expectEmit(false, false, false, true);
        emit AltoNftRewardsAdapter.PaymentTokenShareSet(share2);

        vm.prank(OWNER);
        adapter.setPaymentTokenShare(share2);

        assertEq(adapter.paymentTokenShare(), share2);
        assertNotEq(adapter.paymentTokenShare(), share1);
    }
}
