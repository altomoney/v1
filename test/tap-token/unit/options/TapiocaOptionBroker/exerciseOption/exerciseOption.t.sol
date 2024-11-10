// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

contract TapiocaOptionBroker_exerciseOptiontree is Test {
    function test_RevertWhen_ContractIsPaused() external {
        // it should revert
        vm.skip(true);
    }

    function test_WhenPositionIsNotActive() external {
        // it should revert with OptionExpired
        vm.skip(true);
    }

    function test_WhenPaymentTokenIsNotSupported() external {
        // it should revert with PaymentTokenNotSupported
        vm.skip(true);
    }

    function test_WhenCurrentTimestampIsInNextEpoch() external {
        // it should revert with AdvanceEpochFirst
        vm.skip(true);
    }

    function test_WhenLessThanOneEpochHasPassedSinceLock() external {
        // it should revert with OneEpochCooldown
        vm.skip(true);
    }

    function test_WhenTapAmountIsGreaterThanEligibleAmount() external {
        // it should revert with TooHigh
        vm.skip(true);
    }

    function test_WhenChosenAmountIsLessThan1e18() external {
        // it should revert with TooLow
        vm.skip(true);
    }

    modifier whenAllConditionsAreMet() {
        _;
    }

    function test_WhenAllConditionsAreMet() external whenAllConditionsAreMet {
        // it should calculate eligible tap amount correctly
        // it should update position's amountExercisedCurrentEpoch
        // it should process OTC deal
        // it should emit ExerciseOption event
        // it should calculate TAP valuation in USD
        // it should calculate discounted payment amount
        // it should transfer payment token from sender
        // it should extract TAP to sender
        // it should return discounted payment amount
        vm.skip(true);
    }

    modifier whenGettingPaymentTokenValuation() {
        _;
    }

    function test_WhenOracleCallSucceeds() external whenAllConditionsAreMet whenGettingPaymentTokenValuation {
        // it should get payment token valuation
        vm.skip(true);
    }

    function test_WhenOracleCallFails() external whenAllConditionsAreMet whenGettingPaymentTokenValuation {
        // it should revert with Failed
        vm.skip(true);
    }
}
