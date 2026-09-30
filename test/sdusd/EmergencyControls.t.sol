// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {EmergencyController} from "@alto/utils/EmergencyController.sol";
import {FROZEN_TYPE, PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {FeeSourceType} from "@alto/sdusd/interfaces/IProtocolFeeCollector.sol";
import {SDUSDCommon} from "./btt/SDUSD/SDUSDCommon.t.sol";

contract SdusdPauserSafeMock {
    mapping(address => bool) public isOwner;

    function setOwner(address member, bool status) external {
        isOwner[member] = status;
    }
}

contract SDUSDEmergencyControlsTest is SDUSDCommon {
    EmergencyController internal controller;
    SdusdPauserSafeMock internal pauserSafe;
    address internal responder = makeAddr("responder");

    function setUp() public override {
        super.setUp();
        pauserSafe = new SdusdPauserSafeMock();
        pauserSafe.setOwner(responder, true);
        controller = EmergencyController(
            address(
                new ERC1967Proxy(
                    address(new EmergencyController()),
                    abi.encodeCall(
                        EmergencyController.initialize,
                        (ADMIN, address(pauserSafe), address(marketRegistry), address(usmRegistry))
                    )
                )
            )
        );

        vm.startPrank(ADMIN);
        controller.setPauseWhitelist(address(vault), true);
        controller.setFrozenWhitelist(address(vault), true);
        controller.setPauseWhitelist(address(collector), true);
        vault.setPauser(address(controller), FROZEN_TYPE, true);
        vault.setPauser(address(controller), PAUSE_TYPE, true);
        vault.setPauser(address(pauserSafe), FROZEN_TYPE, true);
        vault.setPauser(address(pauserSafe), PAUSE_TYPE, true);
        collector.setPauser(address(controller), PAUSE_TYPE, true);
        collector.setPauser(address(pauserSafe), PAUSE_TYPE, true);
        vm.stopPrank();
        _depositFor(USER, 100 ether);
        vm.prank(USER);
        vault.approve(SPENDER, type(uint256).max);
    }

    function test_FreezeBlocksEntriesButAllowsExitsAndNewRewards() public {
        _freezeVault();
        assertEq(vault.maxDeposit(USER), 0);
        assertEq(vault.maxMint(USER), 0);
        _assertEntriesRevert(FROZEN_TYPE);
        _notifyRewards(REWARD_AMOUNT);
        assertEq(vault.rewardsForPeriod(), REWARD_AMOUNT);
        assertGt(vault.maxWithdraw(USER), 0);
        assertEq(vault.maxRedeem(USER), vault.balanceOf(USER));
        vm.startPrank(SPENDER);
        vault.withdraw(1 ether, RECEIVER, USER);
        vault.redeem(1 ether, RECEIVER, USER);
        vm.stopPrank();
        assertEq(dusd.balanceOf(RECEIVER), 2 ether);
    }

    function test_PauseBlocksAllVaultActionsIncludingZeroAndDelegatedExits() public {
        _pauseVault();
        assertEq(vault.maxDeposit(USER), 0);
        assertEq(vault.maxMint(USER), 0);
        assertEq(vault.maxWithdraw(USER), 0);
        assertEq(vault.maxRedeem(USER), 0);
        _assertEntriesRevert(PAUSE_TYPE);
        uint256 assetsBefore = vault.accountedAssets();
        uint256 sharesBefore = vault.balanceOf(USER);
        for (uint256 i; i < 2; ++i) {
            address caller = i == 0 ? USER : SPENDER;
            vm.startPrank(caller);
            for (uint256 amount; amount <= 1 ether; amount += 1 ether) {
                vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSE_TYPE));
                vault.withdraw(amount, RECEIVER, USER);
                vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSE_TYPE));
                vault.redeem(amount, RECEIVER, USER);
            }
            vm.stopPrank();
        }
        vm.prank(address(collector));
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSE_TYPE));
        vault.notifyRewardAmount(REWARD_AMOUNT);
        assertEq(vault.accountedAssets(), assetsBefore);
        assertEq(vault.balanceOf(USER), sharesBefore);
    }

    function test_RewardClockTransfersAndPreviewsContinueInBothStates() public {
        _notifyRewards(REWARD_AMOUNT);
        uint256 assetsBefore = vault.totalAssets();
        uint256 depositQuote = vault.previewDeposit(1 ether);
        uint256 mintQuote = vault.previewMint(1 ether);
        uint256 withdrawQuote = vault.previewWithdraw(1 ether);
        uint256 redeemQuote = vault.previewRedeem(1 ether);
        _freezeVault();
        _pauseVault();
        assertEq(vault.previewDeposit(1 ether), depositQuote);
        assertEq(vault.previewMint(1 ether), mintQuote);
        assertEq(vault.previewWithdraw(1 ether), withdrawQuote);
        assertEq(vault.previewRedeem(1 ether), redeemQuote);
        uint256 usageBefore = vault.depositCapUsage();
        vm.prank(USER);
        vault.transfer(RECEIVER, 1 ether);
        vm.prank(SPENDER);
        vault.transferFrom(USER, RECEIVER, 1 ether);
        assertEq(vault.depositCapUsage(), usageBefore);
        assertEq(vault.balanceOf(RECEIVER), 2 ether);
        vm.warp(vault.periodStart() + REWARD_DURATION / 2);
        assertEq(vault.totalAssets(), assetsBefore + REWARD_AMOUNT / 2);
        assertEq(vault.lockedRewardsRemaining(), REWARD_AMOUNT / 2);
        _finishRewardPeriod();
        assertEq(vault.totalAssets(), assetsBefore + REWARD_AMOUNT);
        assertEq(vault.lockedRewardsRemaining(), 0);
    }

    function test_ClearingPauseLeavesFreezeActive() public {
        _freezeVault();
        _pauseVault();
        vm.prank(PAUSER);
        vault.pause(PAUSE_TYPE, false);
        assertEq(vault.maxDeposit(USER), 0);
        _assertEntriesRevert(FROZEN_TYPE);
        assertGt(vault.maxWithdraw(USER), 0);
        vm.prank(USER);
        vault.withdraw(1 ether, RECEIVER, USER);
        _notifyRewards(REWARD_AMOUNT);
        vm.prank(PAUSER);
        vault.pause(FROZEN_TYPE, false);
        assertGt(vault.maxDeposit(USER), 0);
        _depositFor(USER, 1 ether);
        _mintFor(USER, 1 ether);
    }

    function test_ClearingFreezeLeavesPauseActive() public {
        _freezeVault();
        _pauseVault();
        vm.prank(PAUSER);
        vault.pause(FROZEN_TYPE, false);
        _assertEntriesRevert(PAUSE_TYPE);
        assertEq(vault.maxWithdraw(USER), 0);
        assertEq(vault.maxRedeem(USER), 0);
        vm.prank(PAUSER);
        vault.pause(PAUSE_TYPE, false);
        vm.prank(USER);
        vault.redeem(1 ether, RECEIVER, USER);
    }

    function test_IndividualMemberActivatesControlsIdempotentlyAndSafeClearsThem() public {
        vm.startPrank(responder);
        controller.freeze(address(vault));
        controller.freeze(address(vault));
        controller.pause(address(vault));
        controller.pause(address(vault));
        controller.pause(address(collector));
        controller.pause(address(collector));
        vm.expectRevert(abi.encodeWithSelector(IPausable.Unauthorized.selector, responder, FROZEN_TYPE));
        vault.pause(FROZEN_TYPE, false);
        vm.expectRevert(abi.encodeWithSelector(IPausable.Unauthorized.selector, responder, PAUSE_TYPE));
        vault.pause(PAUSE_TYPE, false);
        vm.expectRevert(abi.encodeWithSelector(IPausable.Unauthorized.selector, responder, PAUSE_TYPE));
        collector.pause(PAUSE_TYPE, false);
        vm.stopPrank();
        assertTrue(vault.paused(FROZEN_TYPE));
        assertTrue(vault.paused(PAUSE_TYPE));
        assertTrue(collector.paused(PAUSE_TYPE));

        vm.startPrank(address(pauserSafe));
        vault.pause(FROZEN_TYPE, false);
        vault.pause(PAUSE_TYPE, false);
        collector.pause(PAUSE_TYPE, false);
        vm.stopPrank();
        assertFalse(vault.paused(FROZEN_TYPE));
        assertFalse(vault.paused(PAUSE_TYPE));
        assertFalse(collector.paused(PAUSE_TYPE));
        _depositFor(USER, 1 ether);
        vm.prank(USER);
        vault.withdraw(1 ether, RECEIVER, USER);
        collector.harvest(new FeeSourceType[](0), new address[](0));
    }

    function test_RemovedMemberCannotActivateAnyNewControl() public {
        pauserSafe.setOwner(responder, false);
        vm.startPrank(responder);
        vm.expectRevert(abi.encodeWithSelector(EmergencyController.Unauthorized.selector, responder));
        controller.freeze(address(vault));
        vm.expectRevert(abi.encodeWithSelector(EmergencyController.Unauthorized.selector, responder));
        controller.pause(address(vault));
        vm.expectRevert(abi.encodeWithSelector(EmergencyController.Unauthorized.selector, responder));
        controller.pause(address(collector));
        vm.stopPrank();
    }

    function test_PermissionsAreSpecificToEachTypeAndOwnershipDoesNotBypassThem() public {
        vm.startPrank(ADMIN);
        vault.setPauser(NEW_PAUSER, PAUSE_TYPE, true);
        vault.setPauser(ADMIN, FROZEN_TYPE, false);
        vault.setPauser(ADMIN, PAUSE_TYPE, false);
        collector.setPauser(ADMIN, PAUSE_TYPE, false);
        vm.expectRevert(abi.encodeWithSelector(IPausable.Unauthorized.selector, ADMIN, FROZEN_TYPE));
        vault.pause(FROZEN_TYPE, true);
        vm.expectRevert(abi.encodeWithSelector(IPausable.Unauthorized.selector, ADMIN, PAUSE_TYPE));
        vault.pause(PAUSE_TYPE, true);
        vm.expectRevert(abi.encodeWithSelector(IPausable.Unauthorized.selector, ADMIN, PAUSE_TYPE));
        collector.pause(PAUSE_TYPE, true);
        vm.stopPrank();
        vm.prank(NEW_PAUSER);
        vm.expectRevert(abi.encodeWithSelector(IPausable.Unauthorized.selector, NEW_PAUSER, FROZEN_TYPE));
        vault.pause(FROZEN_TYPE, true);
        _freezeVault();
        vm.prank(NEW_PAUSER);
        vm.expectRevert(abi.encodeWithSelector(IPausable.Unauthorized.selector, NEW_PAUSER, FROZEN_TYPE));
        vault.pause(FROZEN_TYPE, false);
    }

    function _assertEntriesRevert(bytes32 pauseType) internal {
        for (uint256 amount; amount <= 1 ether; amount += 1 ether) {
            vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, pauseType));
            vault.deposit(amount, USER);
            vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, pauseType));
            vault.mint(amount, USER);
        }
    }
}
