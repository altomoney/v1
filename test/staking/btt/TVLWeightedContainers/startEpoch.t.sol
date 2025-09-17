// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {TVLWeightedContainersCommon} from "./TVLWeightedContainersCommon.t.sol";
import {
    ITVLWeightedContainersErrors,
    ITVLWeightedContainersEvents
} from "@alto/staking/interfaces/ITVLWeightedContainers.sol";

contract TVLWeightedContainersStartEpoch is TVLWeightedContainersCommon {
    function setUp() public override {
        super.setUp();
        _deployWithSingleContainer();
    }

    modifier givenEpochAlreadyStarted() {
        containers.activateContainer(1);
        containers.startEpoch();
        _;
    }

    function test_RevertGiven_EpochAlreadyStarted() external givenEpochAlreadyStarted {
        // it should revert
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersAlreadyStarted.selector);
        containers.startEpoch();
    }

    modifier givenEpochNotStarted() {
        _;
    }

    function test_RevertWhen_NoActiveContainers() external givenEpochNotStarted {
        // it should revert
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersNoContainers.selector);
        containers.startEpoch();
    }

    function test_WhenActiveContainersExist() external givenEpochNotStarted {
        containers.activateContainer(1);

        vm.expectEmit(true, true, true, true);
        emit ITVLWeightedContainersEvents.EpochStarted(block.timestamp);

        containers.startEpoch();

        // it should set initializedAtTimestamp to current block timestamp
        assertEq(containers.initializedAtTimestamp(), block.timestamp);
    }
}
