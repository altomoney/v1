// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./AltoStakingCommon.t.sol";

contract AltoStaking_AdvanceEpoch_Test is AltoStakingCommon {
    function setUp() public override {
        super.setUp();
        _setupStandardStaking();
    }

    function test_RevertWhen_ContractIsPaused() public {
        _pauseContract();

        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSE_TYPE));
        staking.advanceEpoch(1);
    }

    function test_RevertWhen_ContractIsInRescueMode() public {
        _enableRescueMode();

        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, RESCUE_MODE_PAUSE_TYPE));
        staking.advanceEpoch(1);
    }

    function test_RevertWhen_LimitIsZeroAndCurrentEpochNotFinished() public {
        vm.expectRevert(
            abi.encodeWithSelector(ITVLWeightedContainersErrors.TVLWeightedContainersCurrentEpochNotFinished.selector)
        );
        staking.advanceEpoch(0);
    }

    function test_AdvanceEpoch_WhenLimitIsZeroAfterTimeAdvance() public {
        // Advance time to finish current epoch
        _advanceEpochs(1);
        uint256 currentEpochAfterTime = staking.currentEpoch();

        staking.advanceEpoch(0);

        // With limit 0, it should advance to current epoch (all available epochs)
        assertEq(staking.nextEpochToProcess(), currentEpochAfterTime);
    }

    function test_AdvanceEpoch_WhenLimitIsGreaterThanAvailable() public {
        uint256 initialEpoch = staking.nextEpochToProcess();

        // Advance time by 2 epochs
        _advanceEpochs(2);

        uint256 currentEpoch = staking.currentEpoch();
        uint256 epochsToAdvance = currentEpoch - initialEpoch;

        staking.advanceEpoch(epochsToAdvance + 10); // Try to advance more than available

        assertEq(staking.nextEpochToProcess(), currentEpoch);
    }

    function test_AdvanceEpoch_WhenLimitEqualsEpochsToAdvance() public {
        uint256 initialEpoch = staking.nextEpochToProcess();

        // Advance time by 3 epochs
        _advanceEpochs(3);

        uint256 currentEpoch = staking.currentEpoch();
        uint256 epochsToAdvance = currentEpoch - initialEpoch;

        staking.advanceEpoch(epochsToAdvance);

        assertEq(staking.nextEpochToProcess(), currentEpoch);
    }

    function test_AdvanceEpoch_PartialAdvancement() public {
        uint256 initialEpoch = staking.nextEpochToProcess();

        // Advance time by 5 epochs
        _advanceEpochs(5);

        // Only advance 2 epochs
        staking.advanceEpoch(2);

        assertEq(staking.nextEpochToProcess(), initialEpoch + 2);
    }
}
