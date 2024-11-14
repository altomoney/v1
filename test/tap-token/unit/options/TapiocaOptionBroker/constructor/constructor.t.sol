// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {TOBTestBase, TapiocaOptionBroker, Bucket} from "../TOBTestBase.t.sol";
import {ITWLBase} from "tap-token/interfaces/ITWLBase.sol";

contract TapiocaOptionBroker_constructortree is TOBTestBase {
    function test_RevertWhen_EpochDurationIsZero() external {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(ITWLBase.EPOCH_DURATION_ZERO.selector));
        new TapiocaOptionBroker(payable(0), address(usdo), dao, 0, new Bucket[](0), owner);
    }

    function test_WhenAllParametersAreValid() external {
        // it should set TAP_TOKEN
        // it should set _paymentTokenBeneficiary
        // it should initialize TWLBase
        // it should transfer ownership to admin
        Bucket[] memory buckets = new Bucket[](1);
        buckets[0] = Bucket({
            enabled: true,
            epochGrowthRate: 1,
            epochDecayRate: 1,
            epochCeiling: 10,
            epochFloor: 1,
            rewardsMultiplier: 10000,
            lockEpochDuration: 1,
            currentEpochInflows: 0,
            lastEpochInflows: 0,
            growthGoal: 0
        });

        TapiocaOptionBroker optionBroker =
            new TapiocaOptionBroker(payable(tapToken), address(usdo), dao, EPOCH_DURATION, buckets, owner);

        assertEq(optionBroker.owner(), owner);
        assertEq(address(optionBroker.TAP_TOKEN()), address(tapToken));
        assertEq(address(optionBroker.USDO()), address(usdo));
        assertEq(optionBroker._paymentTokenBeneficiary(), dao);
        assertEq(optionBroker.EPOCH_DURATION(), EPOCH_DURATION);
        assertEq(optionBroker.getBuckets().length, 1);
    }
}
