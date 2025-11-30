// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {UniversalRewardsDistributor} from "@alto/utils/UniversalRewardsDistributor.sol";
import {IMerkleRootManagerEvents} from "@alto/utils/interfaces/IMerkleRootManager.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract UniversalRewardsDistributorConstructor is Test {
    address public OWNER = address(0x1);
    address public ZERO_ADDRESS = address(0);
    uint256 public constant INITIAL_TIMELOCK = 1 days;

    function test_RevertWhen_OwnerIsZeroAddress() external {
        // it should revert with OwnableInvalidOwner
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, ZERO_ADDRESS));
        new UniversalRewardsDistributor(ZERO_ADDRESS, INITIAL_TIMELOCK);
    }

    modifier whenInitialTimelockIsSet() {
        _;
    }

    function test_WhenValidParameters() external whenInitialTimelockIsSet {
        // it should emit SetMerkleRootTimelock event
        vm.expectEmit(true, true, true, true);
        emit IMerkleRootManagerEvents.SetMerkleRootTimelock(INITIAL_TIMELOCK);

        UniversalRewardsDistributor distributor = new UniversalRewardsDistributor(OWNER, INITIAL_TIMELOCK);

        // it should set the owner correctly
        assertEq(distributor.owner(), OWNER);

        // it should set merkleRootTimelock to initialTimelock
        assertEq(distributor.merkleRootTimelock(), INITIAL_TIMELOCK);
    }

    function test_WhenAllParametersAreValid() external {
        UniversalRewardsDistributor distributor = new UniversalRewardsDistributor(OWNER, INITIAL_TIMELOCK);

        // it should inherit from all parent contracts correctly
        // Check that it properly implements all interfaces
        assertEq(distributor.owner(), OWNER); // Ownable
        assertEq(distributor.merkleRootTimelock(), INITIAL_TIMELOCK); // MerkleRootManager
        assertEq(distributor.nonce(OWNER), 0); // Auth

        // it should initialize Auth with correct EIP712 domain
        // We can't directly test the domain separator, but we can verify nonce works
        assertEq(distributor.nonce(address(0x123)), 0);

        // it should initialize Ownable with correct owner
        assertEq(distributor.owner(), OWNER);
        assertEq(distributor.pendingOwner(), address(0));

        // it should be ready for operation
        // Check initial state is correct
        assertEq(distributor.merkleRoot(), bytes32(0));
        assertEq(distributor.ipfsHash(), bytes32(0));
        assertFalse(distributor.isMerkleRootUpdater(OWNER)); // Owner is not automatically an updater

        (bytes32 pendingRoot, uint256 validFrom,) = distributor.pendingMerkleRoot();
        assertEq(pendingRoot, bytes32(0));
        assertEq(validFrom, 0);
    }

    // Fuzz test for different timelock values
    function testFuzz_ConstructorWithDifferentTimelocks(uint256 timelock) external {
        timelock = bound(timelock, 0, 365 days); // Reasonable bounds

        vm.expectEmit(true, true, true, true);
        emit IMerkleRootManagerEvents.SetMerkleRootTimelock(timelock);

        UniversalRewardsDistributor distributor = new UniversalRewardsDistributor(OWNER, timelock);

        assertEq(distributor.owner(), OWNER);
        assertEq(distributor.merkleRootTimelock(), timelock);
    }
}
