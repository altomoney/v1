// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {AltoVesting} from "@alto/vesting/AltoVesting.sol";
import {IAltoVesting, VestingInfo} from "@alto/vesting/interfaces/IAltoVesting.sol";
import {IMerkleRootManagerErrors} from "@alto/utils/interfaces/IMerkleRootManager.sol";
import {IMerkleRootManagerEvents} from "@alto/utils/interfaces/IMerkleRootManager.sol";
import {ERC20MockMintable} from "@alto-test/helpers/ERC20MockMintable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract AltoVestingSubmitNewPendingRoot is Test {
    AltoVesting public updatableVesting;
    AltoVesting public nonUpdatableVesting;
    ERC20MockMintable public vestingToken;

    address public OWNER = makeAddr("owner");
    address public UPDATER = makeAddr("updater");
    address public NON_UPDATER = makeAddr("non-updater");

    uint256 public constant INITIAL_TIMELOCK = 3 days;
    bytes32 public constant TEST_MERKLE_ROOT = bytes32(uint256(123));
    bytes32 public constant NEW_MERKLE_ROOT = bytes32(uint256(789));
    bytes32 public constant NEW_IPFS_HASH = bytes32(uint256(101112));
    bytes32 public constant ZERO_MERKLE_ROOT = bytes32(0);

    // Modifiers for BTT structure
    modifier givenCallerIsNotMerkleRootUpdaterOrOwner() {
        _;
    }

    modifier givenCallerIsMerkleRootUpdater() {
        vm.startPrank(UPDATER);
        _;
        vm.stopPrank();
    }

    modifier givenCallerIsOwner() {
        vm.startPrank(OWNER);
        _;
        vm.stopPrank();
    }

    modifier givenVestingIsNotUpdatable() {
        _;
    }

    modifier givenVestingIsUpdatable() {
        _;
    }

    modifier givenNewMerkleRootIsZero() {
        _;
    }

    modifier givenNewMerkleRootIsSameAsCurrentPending() {
        // First submit a pending root
        vm.prank(UPDATER);
        updatableVesting.submitNewPendingRoot(NEW_MERKLE_ROOT, NEW_IPFS_HASH);
        _;
    }

    modifier givenNewMerkleRootIsValid() {
        _;
    }

    function setUp() public {
        vestingToken = new ERC20MockMintable("Alto Token", "ALTO");

        // Deploy updatable vesting
        updatableVesting =
            new AltoVesting(OWNER, INITIAL_TIMELOCK, true, address(vestingToken), TEST_MERKLE_ROOT, bytes32(0));

        // Deploy non-updatable vesting
        nonUpdatableVesting =
            new AltoVesting(OWNER, INITIAL_TIMELOCK, false, address(vestingToken), TEST_MERKLE_ROOT, bytes32(0));

        // Set up updater for both contracts
        vm.startPrank(OWNER);
        updatableVesting.setMerkleRootUpdater(UPDATER, true);
        nonUpdatableVesting.setMerkleRootUpdater(UPDATER, true);
        vm.stopPrank();
    }

    function test_RevertWhen_CallerIsNotMerkleRootUpdaterOrOwner()
        external
        givenCallerIsNotMerkleRootUpdaterOrOwner
        givenVestingIsUpdatable
        givenNewMerkleRootIsValid
    {
        vm.prank(NON_UPDATER);
        vm.expectRevert(IMerkleRootManagerErrors.MerkleRootManagerNotUpdater.selector);
        updatableVesting.submitNewPendingRoot(NEW_MERKLE_ROOT, NEW_IPFS_HASH);
    }

    function test_RevertWhen_VestingIsNotUpdatable()
        external
        givenCallerIsMerkleRootUpdater
        givenVestingIsNotUpdatable
        givenNewMerkleRootIsValid
    {
        vm.expectRevert(IAltoVesting.AltoVestingNotUpdatable.selector);
        nonUpdatableVesting.submitNewPendingRoot(NEW_MERKLE_ROOT, NEW_IPFS_HASH);
    }

    function test_RevertWhen_NewMerkleRootIsZero()
        external
        givenCallerIsMerkleRootUpdater
        givenVestingIsUpdatable
        givenNewMerkleRootIsZero
    {
        vm.expectRevert(IMerkleRootManagerErrors.MerkleRootManagerInvalidInput.selector);
        updatableVesting.submitNewPendingRoot(ZERO_MERKLE_ROOT, NEW_IPFS_HASH);
    }

    function test_RevertWhen_NewMerkleRootIsSameAsCurrentPending()
        external
        givenVestingIsUpdatable
        givenNewMerkleRootIsSameAsCurrentPending
        givenCallerIsMerkleRootUpdater
    {
        vm.expectRevert(IMerkleRootManagerErrors.MerkleRootManagerAlreadyPending.selector);
        updatableVesting.submitNewPendingRoot(NEW_MERKLE_ROOT, NEW_IPFS_HASH);
    }

    function test_WhenCallerIsMerkleRootUpdater_GivenAllConditionsAreMetForValidSubmission()
        external
        givenVestingIsUpdatable
        givenNewMerkleRootIsValid
        givenCallerIsMerkleRootUpdater
    {
        // it should emit SubmitPendingMerkleRoot event with correct parameters
        vm.expectEmit(true, true, true, true);
        emit IMerkleRootManagerEvents.SubmitPendingMerkleRoot(UPDATER, NEW_MERKLE_ROOT, NEW_IPFS_HASH);

        updatableVesting.submitNewPendingRoot(NEW_MERKLE_ROOT, NEW_IPFS_HASH);

        // it should set pendingMerkleRoot with new merkle root
        (bytes32 pendingRoot, uint256 validFrom, bytes32 pendingIpfsHash) = updatableVesting.pendingMerkleRoot();
        assertEq(pendingRoot, NEW_MERKLE_ROOT);

        // it should set pendingMerkleRoot with new ipfs hash
        assertEq(pendingIpfsHash, NEW_IPFS_HASH);

        // it should set pendingMerkleRoot validFrom to current timestamp + timelock
        assertEq(validFrom, block.timestamp + INITIAL_TIMELOCK);
    }

    function test_WhenCallerIsOwner_GivenAllConditionsAreMetForValidSubmission()
        external
        givenCallerIsOwner
        givenVestingIsUpdatable
        givenNewMerkleRootIsValid
    {
        // it should emit SubmitPendingMerkleRoot event with correct parameters
        vm.expectEmit(true, true, true, true);
        emit IMerkleRootManagerEvents.SubmitPendingMerkleRoot(OWNER, NEW_MERKLE_ROOT, NEW_IPFS_HASH);

        updatableVesting.submitNewPendingRoot(NEW_MERKLE_ROOT, NEW_IPFS_HASH);

        // it should set pendingMerkleRoot with new merkle root
        (bytes32 pendingRoot, uint256 validFrom, bytes32 pendingIpfsHash) = updatableVesting.pendingMerkleRoot();
        assertEq(pendingRoot, NEW_MERKLE_ROOT);

        // it should set pendingMerkleRoot with new ipfs hash
        assertEq(pendingIpfsHash, NEW_IPFS_HASH);

        // it should set pendingMerkleRoot validFrom to current timestamp + timelock
        assertEq(validFrom, block.timestamp + INITIAL_TIMELOCK);
    }
}
