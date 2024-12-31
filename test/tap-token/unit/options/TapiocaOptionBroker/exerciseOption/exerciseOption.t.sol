// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {TOBTestBase, ITapiocaOptionBroker} from "../TOBTestBase.t.sol";
import {Test, stdError, StdStorage, stdStorage} from "forge-std/Test.sol";

contract TapiocaOptionBrokerExerciseOptionTest is TOBTestBase {
    address testUser;
    uint256 lockAmount;
    uint256 exerciseAmount;

    function setUp() public override {
        super.setUp();
        testUser = makeAddr("testUser");
        lockAmount = 1e18;
        exerciseAmount = 1e18;

        vm.startPrank(owner);
        tob.setMarket(address(market), true);
        tob.setPaymentToken(address(paymentToken), paymentTokenOracle, "");
        vm.stopPrank();
    }

    function _setupValidPosition() internal {
        _mintTapToken(testUser, lockAmount);
        deal(address(usdo), testUser, lockAmount);

        vm.startPrank(testUser);
        tapToken.approve(address(tob), lockAmount);
        usdo.approve(address(tob), lockAmount);
        tob.lock(testUser, 0, lockAmount, market);
        vm.stopPrank();

        // Advance epoch
        vm.startPrank(owner);
        vm.warp(block.timestamp + EPOCH_DURATION);
        vm.mockCall(address(tapOracle), abi.encodeWithSignature("get(bytes)"), abi.encode(true, 1e18));
        tob.advanceWeek();
        vm.stopPrank();
    }

    function test_revertWhen_positionNotActive() public {
        _setupValidPosition();

        vm.startPrank(testUser);
        vm.expectRevert("PositionNotActive()");
        tob.exerciseOption(0, address(paymentToken), exerciseAmount);
        vm.stopPrank();
    }

    function test_revertWhen_epochNotAdvanced() public {
        _setupValidPosition();

        // Try to exercise without advancing epoch
        vm.startPrank(testUser);
        vm.expectRevert("EpochNotAdvanced()");
        tob.exerciseOption(0, address(paymentToken), exerciseAmount);
        vm.stopPrank();
    }

    function test_revertWhen_invalidPaymentToken() public {
        _setupValidPosition();

        vm.startPrank(testUser);
        vm.expectRevert("InvalidPaymentToken()");
        tob.exerciseOption(0, address(0), exerciseAmount);
        vm.stopPrank();
    }

    function test_revertWhen_amountTooLow() public {
        _setupValidPosition();

        vm.startPrank(testUser);
        vm.expectRevert("AmountTooLow()");
        tob.exerciseOption(0, address(paymentToken), 0);
        vm.stopPrank();
    }

    function test_revertWhen_amountTooHigh() public {
        _setupValidPosition();

        vm.startPrank(testUser);
        vm.expectRevert(ITapiocaOptionBroker.TooHigh.selector);
        tob.exerciseOption(0, address(paymentToken), lockAmount + 1);
        vm.stopPrank();
    }

    function test_exerciseOption_validConditions() public {
        _setupValidPosition();

        // Mock payment token oracle
        vm.mockCall(address(paymentTokenOracle), abi.encodeWithSignature("get(bytes)"), abi.encode(true, 1e18));

        // Mint payment tokens to user
        deal(address(paymentToken), testUser, exerciseAmount);

        vm.startPrank(testUser);
        paymentToken.approve(address(tob), exerciseAmount);

        uint256 initialPaymentTokenBalance = paymentToken.balanceOf(testUser);
        uint256 initialTapBalance = tapToken.balanceOf(testUser);

        tob.exerciseOption(0, address(paymentToken), exerciseAmount);

        assertEq(
            paymentToken.balanceOf(testUser),
            initialPaymentTokenBalance - exerciseAmount,
            "Payment token balance should decrease"
        );
        assertEq(tapToken.balanceOf(testUser), initialTapBalance + exerciseAmount, "TAP balance should increase");

        vm.stopPrank();
    }
}
