// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {TOBTestBase, ITapiocaOptionBroker} from "../TOBTestBase.t.sol";
import {Test, stdError, StdStorage, stdStorage} from "forge-std/Test.sol";
import {Participation} from "tap-token/interfaces/ITapiocaOptionBroker.sol";

contract TapiocaOptionBrokerExerciseOptionTest is TOBTestBase {
    address testUser;
    uint256 collateralAmount;
    uint256 borrowAmount;
    uint256 lockAmount;
    uint256 exerciseAmount;

    function setUp() public override {
        super.setUp();
        testUser = makeAddr("testUser");
        lockAmount = 1e18;
        collateralAmount = 6e18;
        borrowAmount = 2e18;
        exerciseAmount = 1e18;
    }

    function _setupValidPosition() internal {
        _setupValidPosition(testUser, collateralAmount, borrowAmount, lockAmount);
    }

    function test_revertWhen_positionNotActive() public {
        _setupValidPosition();

        vm.startPrank(testUser);
        vm.expectRevert(ITapiocaOptionBroker.OneEpochCooldown.selector);
        tob.exerciseOption(testUser, 0, address(paymentToken), exerciseAmount);
        vm.stopPrank();
    }

    function test_revertWhen_epochNotAdvanced() public {
        _setupValidPosition();

        vm.warp(block.timestamp + EPOCH_DURATION);
        tob.advanceWeek();

        vm.warp(block.timestamp + EPOCH_DURATION * 3);

        // Try to exercise without advancing epoch
        vm.startPrank(testUser);
        vm.expectRevert(ITapiocaOptionBroker.AdvanceEpochFirst.selector);
        tob.exerciseOption(testUser, 0, address(paymentToken), exerciseAmount);
        vm.stopPrank();
    }

    function test_revertWhen_invalidPaymentToken() public {
        _setupValidPosition();
        vm.warp(block.timestamp + EPOCH_DURATION);
        tob.advanceWeek();

        vm.startPrank(testUser);
        vm.expectRevert(ITapiocaOptionBroker.PaymentTokenNotSupported.selector);
        tob.exerciseOption(testUser, 0, address(0), exerciseAmount);
        vm.stopPrank();
    }

    function test_revertWhen_amountTooLow() public {
        _setupValidPosition();

        vm.warp(block.timestamp + EPOCH_DURATION);
        tob.advanceWeek();

        vm.startPrank(testUser);
        vm.expectRevert(ITapiocaOptionBroker.TooLow.selector);
        tob.exerciseOption(testUser, 0, address(paymentToken), 1);
        vm.stopPrank();
    }

    function test_revertWhen_amountTooHigh() public {
        _setupValidPosition();

        vm.warp(block.timestamp + EPOCH_DURATION);
        tob.advanceWeek();
        vm.startPrank(testUser);
        vm.expectRevert(ITapiocaOptionBroker.TooHigh.selector);
        tob.exerciseOption(testUser, 0, address(paymentToken), 999999999e18);
        vm.stopPrank();
    }

    function test_exerciseOption_validConditions() public {
        _setupValidPosition();
        Participation memory position = tob.getParticipation(testUser, 0);

        // Mint payment tokens to user
        deal(address(paymentToken), testUser, exerciseAmount);

        vm.startPrank(testUser);
        paymentToken.approve(address(tob), exerciseAmount);

        uint256 initialPaymentTokenBalance = paymentToken.balanceOf(testUser);
        uint256 initialTapBalance = tapToken.balanceOf(testUser);

        vm.warp(block.timestamp + EPOCH_DURATION * 9);
        tob.advanceWeek();

        tob.exerciseOption(testUser, 0, address(paymentToken), exerciseAmount);

        assertLt(paymentToken.balanceOf(testUser), initialPaymentTokenBalance, "Payment token balance should decrease");
        assertEq(tapToken.balanceOf(testUser), initialTapBalance + exerciseAmount, "TAP balance should increase");

        vm.stopPrank();
    }
}
