// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {AltoStakingCommon} from "./AltoStakingCommon.t.sol";
import {MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";

contract AltoStakingGetVotes is AltoStakingCommon {
    function setUp() public override {
        super.setUp();
        _setupStandardStaking();
    }

    function test_WhenUserHasNoPositions() external {
        // it should return zero votes
        uint256 votes = staking.getVotes(USER);
        assertEq(votes, 0);
    }

    function test_WhenUserHasExpiredPositionsOnly() external {
        // Create position and let it expire
        _lockPosition(USER, LOCK_AMOUNT, 1, false);

        // Advance time beyond expiry
        _advanceTime(EPOCH_DURATION + 1);

        // it should return zero votes
        uint256 votes = staking.getVotes(USER);
        assertEq(votes, 0);
    }

    modifier whenUserHasActivePositions() {
        _;
    }

    function test_WhenUserHasSingleActivePosition() external whenUserHasActivePositions {
        _lockPosition(USER, LOCK_AMOUNT, 1, false);

        // it should calculate votes as amount * multiplier
        // Container 1 has 0.3 ether multiplier (30%)
        uint256 expectedVotes = LOCK_AMOUNT * 0.3 ether / MATH_PRECISION;

        // it should return correct voting power
        uint256 votes = staking.getVotes(USER);
        assertEq(votes, expectedVotes);
    }

    function test_WhenUserHasMultipleActivePositionsInSameContainer() external whenUserHasActivePositions {
        // Note: AltoStaking doesn't support multiple positions in same container for same user
        // Each lock either creates new position or updates existing one
        // So we test updating existing position

        _lockPosition(USER, LOCK_AMOUNT, 1, false);
        _lockPosition(USER, LOCK_AMOUNT / 2, 1, false); // This will add to existing position

        uint256 totalAmount = LOCK_AMOUNT + LOCK_AMOUNT / 2;

        // it should sum all amounts in container
        // it should multiply by container multiplier
        uint256 expectedVotes = totalAmount * 0.3 ether / MATH_PRECISION;

        // it should return correct total voting power
        uint256 votes = staking.getVotes(USER);
        assertEq(votes, expectedVotes);
    }

    function test_WhenUserHasActivePositionsInDifferentContainers() external whenUserHasActivePositions {
        _lockPosition(USER, LOCK_AMOUNT, 1, false); // 30% multiplier
        _lockPosition(USER, LOCK_AMOUNT, 2, false); // 60% multiplier
        _lockPosition(USER, LOCK_AMOUNT, 3, false); // 100% multiplier

        // it should calculate votes for each container separately
        // it should apply respective multipliers
        uint256 votes1 = LOCK_AMOUNT * 0.3 ether / MATH_PRECISION;
        uint256 votes2 = LOCK_AMOUNT * 0.6 ether / MATH_PRECISION;
        uint256 votes3 = LOCK_AMOUNT * 1.0 ether / MATH_PRECISION;

        // it should sum all voting powers
        uint256 expectedTotalVotes = votes1 + votes2 + votes3;

        // it should return correct total voting power
        uint256 votes = staking.getVotes(USER);
        assertEq(votes, expectedTotalVotes);
    }

    function test_WhenUserHasMixOfActiveAndExpiredPositions() external whenUserHasActivePositions {
        // Create positions with different durations
        _lockPosition(USER, LOCK_AMOUNT, 1, false); // 1 epoch duration
        _lockPosition(USER, LOCK_AMOUNT, 2, false); // 2 epoch duration
        _lockPosition(USER, LOCK_AMOUNT, 3, false); // 3 epoch duration

        // Advance time to expire only first position
        _advanceTime(EPOCH_DURATION + 1);

        // it should include only non-expired positions
        // it should ignore expired positions
        // Container 1 should be expired, containers 2 and 3 should be active
        uint256 votes2 = LOCK_AMOUNT * 0.6 ether / MATH_PRECISION;
        uint256 votes3 = LOCK_AMOUNT * 1.0 ether / MATH_PRECISION;
        uint256 expectedVotes = votes2 + votes3;

        // it should return voting power for active positions only
        uint256 votes = staking.getVotes(USER);
        assertEq(votes, expectedVotes);
    }

    function test_WhenContainersHaveDifferentMultipliers() external whenUserHasActivePositions {
        // Create custom containers with specific multipliers
        _deployEmpty();

        vm.startPrank(OWNER);
        staking.addContainer(shortContainer, 0.1 ether); // 10%
        staking.addContainer(mediumContainer, 0.5 ether); // 50%
        staking.addContainer(longContainer, 1.0 ether); // 100% (maximum allowed)

        staking.activateContainer(1);
        staking.activateContainer(2);
        staking.activateContainer(3);
        staking.startEpoch();
        vm.stopPrank();

        uint256 amount1 = 1000 ether;
        uint256 amount2 = 2000 ether;
        uint256 amount3 = 500 ether;

        _lockPosition(USER, amount1, 1, false);
        _lockPosition(USER, amount2, 2, false);
        _lockPosition(USER, amount3, 3, false);

        // it should apply correct multiplier to each container
        // it should calculate proportional voting power
        uint256 votes1 = amount1 * 0.1 ether / MATH_PRECISION;
        uint256 votes2 = amount2 * 0.5 ether / MATH_PRECISION;
        uint256 votes3 = amount3 * 1.0 ether / MATH_PRECISION;
        uint256 expectedVotes = votes1 + votes2 + votes3;

        // it should return accurate weighted total
        uint256 votes = staking.getVotes(USER);
        assertEq(votes, expectedVotes);
    }

    function test_VotingPowerCalculationAccuracy() external whenUserHasActivePositions {
        // Test with precise amounts
        uint256 preciseAmount = 1234567890123456789; // ~1.234 ether

        _lockPosition(USER, preciseAmount, 1, false); // 30% multiplier

        uint256 expectedVotes = preciseAmount * 0.3 ether / MATH_PRECISION;
        uint256 votes = staking.getVotes(USER);

        assertEq(votes, expectedVotes);
    }

    function test_MultipleUsersVotingPower() external whenUserHasActivePositions {
        // Lock for different users
        _lockPosition(USER, LOCK_AMOUNT, 1, false);
        _lockPosition(USER_2, LOCK_AMOUNT * 2, 1, false);

        uint256 votesUser1 = staking.getVotes(USER);
        uint256 votesUser2 = staking.getVotes(USER_2);

        uint256 expectedVotes1 = LOCK_AMOUNT * 0.3 ether / MATH_PRECISION;
        uint256 expectedVotes2 = LOCK_AMOUNT * 2 * 0.3 ether / MATH_PRECISION;

        assertEq(votesUser1, expectedVotes1);
        assertEq(votesUser2, expectedVotes2);

        // Voting power should be proportional to locked amounts
        assertEq(votesUser2, votesUser1 * 2);
    }

    function test_VotingPowerAfterPartialUnlock() external whenUserHasActivePositions {
        // Create multiple positions
        _lockPosition(USER, LOCK_AMOUNT, 1, false);
        _lockPosition(USER, LOCK_AMOUNT, 2, false);
        _lockPosition(USER, LOCK_AMOUNT, 3, false);

        uint256 initialVotes = staking.getVotes(USER);

        // Advance time to expire first position
        _advanceTime(EPOCH_DURATION + 1);

        // Unlock expired position
        _unlockPosition(USER, RECEIVER, 1);

        uint256 votesAfterUnlock = staking.getVotes(USER);

        // Voting power should decrease by the amount from container 1
        uint256 container1Votes = LOCK_AMOUNT * 0.3 ether / MATH_PRECISION;
        assertEq(votesAfterUnlock, initialVotes - container1Votes);
    }

    function test_VotingPowerWithDeprecatedContainers() external whenUserHasActivePositions {
        // Create positions in all containers
        _lockPosition(USER, LOCK_AMOUNT, 1, false);
        _lockPosition(USER, LOCK_AMOUNT, 2, false);
        _lockPosition(USER, LOCK_AMOUNT, 3, false);

        uint256 initialVotes = staking.getVotes(USER);

        // Deprecate container 2
        vm.prank(OWNER);
        staking.deprecateContainer(2);

        // Voting power should remain the same (deprecated containers still count for existing positions)
        uint256 votesAfterDeprecation = staking.getVotes(USER);
        assertEq(votesAfterDeprecation, initialVotes);
    }

    function test_ZeroAmountPosition() external whenUserHasActivePositions {
        // This shouldn't be possible through normal means, but test edge case
        // Create normal position first
        _lockPosition(USER, LOCK_AMOUNT, 1, false);

        uint256 votes = staking.getVotes(USER);
        assertTrue(votes > 0);

        // After unlock, votes should be zero
        _advanceTime(EPOCH_DURATION + 1);
        _unlockPosition(USER, RECEIVER, 1);

        uint256 votesAfterUnlock = staking.getVotes(USER);
        assertEq(votesAfterUnlock, 0);
    }
}
