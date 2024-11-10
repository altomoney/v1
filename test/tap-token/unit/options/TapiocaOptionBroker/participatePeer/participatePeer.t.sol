// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

contract TapiocaOptionBroker_participatePeertree is Test {
    function test_RevertWhen_ContractIsPaused() external {
        // it should revert
        vm.skip(true);
    }

    function test_WhenLastEpochNotEqualCurrentEpoch() external {
        // it should call advanceWeek
        vm.skip(true);
    }

    function test_WhenCallerIsNotMAGNETAR() external {
        // it should revert with NotAuthorized
        vm.skip(true);
    }

    function test_WhenSglSharesIsZero() external {
        // it should revert with SharesNotValid
        vm.skip(true);
    }

    function test_WhenUsdoAmountIsZero() external {
        // it should revert with SharesNotValid
        vm.skip(true);
    }

    function test_WhenSingularityPoolIsNotActive() external {
        // it should revert with SingularityNotActive
        vm.skip(true);
    }

    function test_WhenSingularityPoolIsInRescueMode() external {
        // it should revert with SingularityInRescueMode
        vm.skip(true);
    }

    function test_WhenEmergencySweepIsActive() external {
        // it should revert with EmergencySweepActivated
        vm.skip(true);
    }

    modifier whenAllConditionsAreMet() {
        _;
    }

    function test_WhenAllConditionsAreMet() external whenAllConditionsAreMet {
        // it should supply in bucket
        // it should update position details
        // it should update net deposits for current and expiry epochs
        // it should transfer sglShares from sender
        // it should emit Participate event
        vm.skip(true);
    }

    modifier givenAnExistingPosition() {
        _;
    }

    function test_WhenPositionNotExpired() external whenAllConditionsAreMet givenAnExistingPosition {
        // it should clear expected votes at past expiration
        vm.skip(true);
    }

    function test_WhenPositionExpired() external whenAllConditionsAreMet givenAnExistingPosition {
        // it should not clear expected votes
        vm.skip(true);
    }
}
