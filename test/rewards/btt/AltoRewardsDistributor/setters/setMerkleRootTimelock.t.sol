// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {RewardsDistributorCommon} from "../RewardsDistributorCommon.t.sol";
import {AltoRewardsDistributor} from "@alto/rewards/AltoRewardsDistributor.sol";
import {IRewardsEvents} from "@alto/rewards/interfaces/IRewardsDistributor.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IMerkleRootManagerEvents, IMerkleRootManagerErrors} from "@alto/rewards/interfaces/IMerkleRootManager.sol";

contract AltoRewardsDistributorSetMerkleRootTimelock is RewardsDistributorCommon {
    function test_RevertWhen_CallerIsNotOwner() external {
        uint256 newTimelock = 2 days;

        vm.prank(ALICE);
        // it should revert
        vm.expectRevert(IMerkleRootManagerErrors.MerkleRootManagerNotOwner.selector);
        distributor.setMerkleRootTimelock(newTimelock);
    }

    modifier whenCallerIsOwner() {
        _;
    }

    function test_RevertWhen_NewTimelockEqualsCurrentTimelock() external whenCallerIsOwner {
        uint256 currentTimelock = distributor.merkleRootTimelock();

        vm.prank(OWNER);
        // it should revert
        vm.expectRevert(IMerkleRootManagerErrors.MerkleRootManagerInvalidInput.selector);
        distributor.setMerkleRootTimelock(currentTimelock);
    }

    function test_WhenNewTimelockIsDifferentFromCurrentTimelock() external whenCallerIsOwner {
        uint256 currentTimelock = distributor.merkleRootTimelock();
        uint256 newTimelock = currentTimelock + 1 days;

        // it should emit SetMerkleRootTimelock event
        vm.expectEmit(false, false, false, true);
        emit IMerkleRootManagerEvents.SetMerkleRootTimelock(newTimelock);

        vm.prank(OWNER);
        distributor.setMerkleRootTimelock(newTimelock);

        // it should update merkle root timelock
        assertEq(distributor.merkleRootTimelock(), newTimelock);
        assertNotEq(distributor.merkleRootTimelock(), currentTimelock); // sanity check
    }

    function test_WhenSettingZeroTimelock() external whenCallerIsOwner {
        uint256 currentTimelock = distributor.merkleRootTimelock();
        uint256 zeroTimelock = 0;

        // Only proceed if current timelock is not already zero
        vm.assume(currentTimelock != zeroTimelock);

        // it should emit SetMerkleRootTimelock event
        vm.expectEmit(false, false, false, true);
        emit IMerkleRootManagerEvents.SetMerkleRootTimelock(zeroTimelock);

        vm.prank(OWNER);
        distributor.setMerkleRootTimelock(zeroTimelock);

        // it should update merkle root timelock
        assertEq(distributor.merkleRootTimelock(), zeroTimelock);
    }

    function test_WhenIncreasingTimelock() external whenCallerIsOwner {
        uint256 currentTimelock = distributor.merkleRootTimelock();
        uint256 longerTimelock = currentTimelock + 7 days;

        // it should emit SetMerkleRootTimelock event
        vm.expectEmit(false, false, false, true);
        emit IMerkleRootManagerEvents.SetMerkleRootTimelock(longerTimelock);

        vm.prank(OWNER);
        distributor.setMerkleRootTimelock(longerTimelock);

        // it should update merkle root timelock
        assertEq(distributor.merkleRootTimelock(), longerTimelock);
        assertGt(distributor.merkleRootTimelock(), currentTimelock); // sanity check
    }

    function test_WhenDecreasingTimelock() external whenCallerIsOwner {
        uint256 currentTimelock = distributor.merkleRootTimelock();

        // Only test if current timelock allows for decrease
        vm.assume(currentTimelock > 1 hours);

        uint256 shorterTimelock = currentTimelock - 1 hours;

        // it should emit SetMerkleRootTimelock event
        vm.expectEmit(false, false, false, true);
        emit IMerkleRootManagerEvents.SetMerkleRootTimelock(shorterTimelock);

        vm.prank(OWNER);
        distributor.setMerkleRootTimelock(shorterTimelock);

        // it should update merkle root timelock
        assertEq(distributor.merkleRootTimelock(), shorterTimelock);
        assertLt(distributor.merkleRootTimelock(), currentTimelock); // sanity check
    }

    function test_WhenUpdatingTimelockMultipleTimes() external whenCallerIsOwner {
        uint256 timelock1 = 2 days;
        uint256 timelock2 = 5 days;
        uint256 timelock3 = 12 hours;

        // Set first timelock
        vm.expectEmit(false, false, false, true);
        emit IMerkleRootManagerEvents.SetMerkleRootTimelock(timelock1);

        vm.prank(OWNER);
        distributor.setMerkleRootTimelock(timelock1);

        assertEq(distributor.merkleRootTimelock(), timelock1);

        // Set second timelock
        vm.expectEmit(false, false, false, true);
        emit IMerkleRootManagerEvents.SetMerkleRootTimelock(timelock2);

        vm.prank(OWNER);
        distributor.setMerkleRootTimelock(timelock2);

        assertEq(distributor.merkleRootTimelock(), timelock2);

        // Set third timelock
        vm.expectEmit(false, false, false, true);
        emit IMerkleRootManagerEvents.SetMerkleRootTimelock(timelock3);

        vm.prank(OWNER);
        distributor.setMerkleRootTimelock(timelock3);

        assertEq(distributor.merkleRootTimelock(), timelock3);
    }
}
