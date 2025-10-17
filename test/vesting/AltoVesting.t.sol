// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {AltoVesting} from "@alto/vesting/AltoVesting.sol";
import {IAltoVesting, VestingInfo} from "@alto/vesting/interfaces/IAltoVesting.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {ERC20MockMintable} from "@alto-test/helpers/ERC20MockMintable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IMerkleRootManagerErrors} from "@alto/utils/interfaces/IMerkleRootManager.sol";

contract AltoVestingTest is Test {
    AltoVesting public vesting;
    AltoVesting public nonUpdatableVesting;
    ERC20MockMintable public vestingToken;

    address public OWNER = makeAddr("Alto-multisig");
    address public UPDATER = makeAddr("updater");
    address public ALICE = makeAddr("alice");
    address public BOB = makeAddr("bob");
    address public ALICE_AUTHORIZED_CALLER = makeAddr("alice-authorized-caller");
    address public BOB_AUTHORIZED_CALLER = makeAddr("bob-authorized-caller");
    address public PAUSER = makeAddr("pauser");

    uint256 public constant INITIAL_TIMELOCK = 3 days;
    uint256 public constant ALICE_VESTING_DURATION = 3 * 365 days; // 3 years
    uint256 public constant BOB_VESTING_DURATION = 1 * 365 days; // 1 year
    uint256 public constant TOTAL_VESTING_AMOUNT = 1_000_000 ether;
    uint256 public constant ALICE_TOTAL_VESTING_AMOUNT = TOTAL_VESTING_AMOUNT;
    uint256 public constant BOB_TOTAL_VESTING_AMOUNT = TOTAL_VESTING_AMOUNT * 2;

    bytes32 public merkleRoot;
    bytes32[] public aliceProof;
    bytes32[] public bobProof;
    VestingInfo public aliceVestingInfo;
    VestingInfo public bobVestingInfo;

    function setUp() public {
        vestingToken = new ERC20MockMintable("Alto Token", "ALTO");

        aliceVestingInfo = VestingInfo({
            startAt: block.timestamp,
            vestingDuration: ALICE_VESTING_DURATION,
            totalVestingAmount: ALICE_TOTAL_VESTING_AMOUNT
        });

        bobVestingInfo = VestingInfo({
            startAt: block.timestamp,
            vestingDuration: BOB_VESTING_DURATION,
            totalVestingAmount: BOB_TOTAL_VESTING_AMOUNT
        });

        // Setup merkle tree
        _setupMerkleTree();

        // Deploy AltoVesting contract
        vesting = new AltoVesting(OWNER, INITIAL_TIMELOCK, true, address(vestingToken), merkleRoot, bytes32(0));

        nonUpdatableVesting =
            new AltoVesting(OWNER, INITIAL_TIMELOCK, false, address(vestingToken), merkleRoot, bytes32(0));

        // Setup vesting contract
        vm.startPrank(OWNER);
        vesting.setMerkleRootUpdater(UPDATER, true);
        vesting.setPauser(PAUSER, keccak256("PAUSE"), true);
        // accept pending root immediately by Owner
        vesting.acceptPendingRoot(merkleRoot);
        vm.stopPrank();

        // Fund vesting contract with tokens
        vestingToken.mint(address(vesting), ALICE_TOTAL_VESTING_AMOUNT + BOB_TOTAL_VESTING_AMOUNT);
        vestingToken.mint(address(nonUpdatableVesting), ALICE_TOTAL_VESTING_AMOUNT + BOB_TOTAL_VESTING_AMOUNT);

        // Setup authorization for AUTHORIZED_CALLER to act on behalf of ALICE
        vm.prank(ALICE);
        vesting.setAuthorization(ALICE_AUTHORIZED_CALLER, true);
    }

    function _setupMerkleTree() internal {
        bytes32 aliceLeaf = keccak256(bytes.concat(keccak256(abi.encode(ALICE, aliceVestingInfo))));
        bytes32 bobLeaf = keccak256(bytes.concat(keccak256(abi.encode(BOB, bobVestingInfo))));

        if (uint256(aliceLeaf) < uint256(bobLeaf)) {
            merkleRoot = keccak256(abi.encodePacked(aliceLeaf, bobLeaf));
            aliceProof = new bytes32[](1);
            aliceProof[0] = bobLeaf;

            bobProof = new bytes32[](1);
            bobProof[0] = aliceLeaf;
        } else {
            merkleRoot = keccak256(abi.encodePacked(bobLeaf, aliceLeaf));
            aliceProof = new bytes32[](1);
            aliceProof[0] = bobLeaf;

            bobProof = new bytes32[](1);
            bobProof[0] = aliceLeaf;
        }
    }

    function test_RevertWhen_ContractIsPaused() external {
        vm.prank(PAUSER);
        vesting.pause(keccak256("PAUSE"), true);

        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, keccak256("PAUSE")));
        vesting.claim(ALICE, aliceVestingInfo, aliceProof);
    }

    function test_RescueVestingTokens_WhenPaused() external {
        vm.prank(PAUSER);
        vesting.pause(keccak256("PAUSE"), true);

        uint256 balance = vestingToken.balanceOf(address(vesting));

        vm.expectEmit(true, true, true, true);
        emit IAltoVesting.RescueVestingTokens(address(vestingToken), OWNER, balance);

        vm.prank(OWNER);
        vesting.rescueVestingTokens();

        // it should transfer all tokens to owner
        assertEq(vestingToken.balanceOf(OWNER), balance);
        assertEq(vestingToken.balanceOf(address(vesting)), 0);
    }

    function test_RevertWhen_RescueVestingTokens_NotPaused() external {
        vm.prank(OWNER);
        vm.expectRevert(IAltoVesting.AltoVestingNotPaused.selector);
        vesting.rescueVestingTokens();
    }

    function test_RevertWhen_SenderIsNotAuthorizedToActOnBehalf() external {
        vm.prank(BOB);
        //  // BOB is not authorized to act on behalf of ALICE, it should revert with AltoVestingUnauthorized
        vm.expectRevert(IAltoVesting.AltoVestingUnauthorized.selector);
        vesting.claim(ALICE, aliceVestingInfo, aliceProof);
    }

    function test_Revert_Given_InvalidMerkleProof() external {
        bytes32[] memory invalidProof = new bytes32[](1);
        invalidProof[0] = bytes32(uint256(999));

        vm.prank(ALICE);
        vm.expectRevert(IAltoVesting.AltoVestingInvalidInput.selector);
        vesting.claim(ALICE, aliceVestingInfo, invalidProof);
    }

    function test_RevertGiven_VestingInfoDoesNotMatchProvidedParameters() external {
        VestingInfo memory wrongVestingInfo = VestingInfo({
            startAt: block.timestamp,
            vestingDuration: ALICE_VESTING_DURATION,
            totalVestingAmount: ALICE_TOTAL_VESTING_AMOUNT + 1 // Incorrect total amount
        });

        vm.prank(ALICE);
        vm.expectRevert(IAltoVesting.AltoVestingInvalidInput.selector);
        vesting.claim(ALICE, wrongVestingInfo, aliceProof);
    }

    function test_RevertGiven_VestingDurationIsZero() external {
        VestingInfo memory invalidVestingInfo = VestingInfo({
            startAt: block.timestamp,
            vestingDuration: 0, // Invalid vesting duration
            totalVestingAmount: ALICE_TOTAL_VESTING_AMOUNT
        });

        bytes32 invalidAliceLeaf = keccak256(bytes.concat(keccak256(abi.encode(ALICE, invalidVestingInfo))));
        bytes32 bobLeaf = keccak256(bytes.concat(keccak256(abi.encode(BOB, bobVestingInfo))));
        bytes32 invalidRoot = _createMerkleRoot(invalidAliceLeaf, bobLeaf);
        bytes32[] memory invalidProof = new bytes32[](1);
        invalidProof[0] = bobLeaf;

        vm.startPrank(OWNER);
        vesting.submitNewPendingRoot(invalidRoot, bytes32(0));
        vesting.acceptPendingRoot(invalidRoot);
        vm.stopPrank();

        vm.prank(ALICE);
        vm.expectRevert(IAltoVesting.AltoVestingInvalidInput.selector);
        vesting.claim(ALICE, invalidVestingInfo, invalidProof);
    }

    function test_WhenVestingHasNotStarted() external {
        VestingInfo memory futureVestingInfo = VestingInfo({
            startAt: block.timestamp + 1 days,
            vestingDuration: ALICE_VESTING_DURATION,
            totalVestingAmount: ALICE_TOTAL_VESTING_AMOUNT
        });

        bytes32 futureLeaf = keccak256(bytes.concat(keccak256(abi.encode(ALICE, futureVestingInfo))));
        bytes32 bobLeaf = keccak256(bytes.concat(keccak256(abi.encode(BOB, bobVestingInfo))));
        bytes32 futureRoot = _createMerkleRoot(futureLeaf, bobLeaf);
        bytes32[] memory futureProof = new bytes32[](1);
        futureProof[0] = bobLeaf;

        vm.startPrank(OWNER);
        vesting.submitNewPendingRoot(futureRoot, bytes32(0));
        vesting.acceptPendingRoot(futureRoot);
        vm.stopPrank();

        vm.prank(ALICE);
        vm.expectRevert(IAltoVesting.AltoVestingInvalidInput.selector);
        vesting.claim(ALICE, futureVestingInfo, futureProof);
    }

    function test_WhenVestingIsFullyVested() external {
        vm.warp(block.timestamp + ALICE_VESTING_DURATION + 1 days);

        uint256 initialBalance = vestingToken.balanceOf(ALICE);

        vm.expectEmit(true, true, true, true);
        emit IAltoVesting.ClaimVesting(ALICE, ALICE, ALICE_TOTAL_VESTING_AMOUNT);

        vm.prank(ALICE);
        uint256 claimedAmount = vesting.claim(ALICE, aliceVestingInfo, aliceProof);

        assertEq(claimedAmount, ALICE_TOTAL_VESTING_AMOUNT);
        assertEq(vestingToken.balanceOf(ALICE), initialBalance + ALICE_TOTAL_VESTING_AMOUNT);
        assertEq(vesting.claimed(ALICE), ALICE_TOTAL_VESTING_AMOUNT);
    }

    function test_Alice_And_Bob_Vesting() external {
        vm.warp(block.timestamp + ALICE_VESTING_DURATION + 1 days);

        uint256 aliceInitialBalance = vestingToken.balanceOf(ALICE);
        uint256 bobInitialBalance = vestingToken.balanceOf(BOB);

        vm.prank(ALICE);
        uint256 claimedAmount = vesting.claim(ALICE, aliceVestingInfo, aliceProof);

        assertEq(claimedAmount, ALICE_TOTAL_VESTING_AMOUNT);
        assertEq(vestingToken.balanceOf(ALICE), aliceInitialBalance + ALICE_TOTAL_VESTING_AMOUNT);
        assertEq(vesting.claimed(ALICE), ALICE_TOTAL_VESTING_AMOUNT);

        vm.prank(BOB);
        uint256 bobClaimedAmount = vesting.claim(BOB, bobVestingInfo, bobProof);
        assertEq(bobClaimedAmount, BOB_TOTAL_VESTING_AMOUNT);
        assertEq(vestingToken.balanceOf(BOB), bobInitialBalance + BOB_TOTAL_VESTING_AMOUNT);
        assertEq(vesting.claimed(BOB), BOB_TOTAL_VESTING_AMOUNT);
    }

    function test_WhenVestingIsPartiallyVested() external {
        vm.warp(block.timestamp + ALICE_VESTING_DURATION / 2);

        uint256 initialBalance = vestingToken.balanceOf(ALICE);

        vm.prank(ALICE);
        uint256 claimedAmount = vesting.claim(ALICE, aliceVestingInfo, aliceProof);

        assertTrue(claimedAmount > ALICE_TOTAL_VESTING_AMOUNT / 2 - 2);
        assertTrue(claimedAmount < ALICE_TOTAL_VESTING_AMOUNT / 2 + 2);
        assertEq(vestingToken.balanceOf(ALICE), initialBalance + claimedAmount);
        assertEq(vesting.claimed(ALICE), claimedAmount);
    }

    function test_WhenUserHasPartiallyClaimedBefore() external {
        vm.warp(block.timestamp + ALICE_VESTING_DURATION / 2);

        vm.prank(ALICE);
        uint256 firstClaimAmount = vesting.claim(ALICE, aliceVestingInfo, aliceProof);

        // Now fast forward to full vesting
        vm.warp(block.timestamp + ALICE_VESTING_DURATION / 2 + 1 days);
        uint256 balanceBeforeSecondClaim = vestingToken.balanceOf(ALICE);

        vm.prank(ALICE);
        uint256 claimedAmount = vesting.claim(ALICE, aliceVestingInfo, aliceProof);

        assertEq(vestingToken.balanceOf(ALICE), balanceBeforeSecondClaim + claimedAmount);

        assertEq(vesting.claimed(ALICE), ALICE_TOTAL_VESTING_AMOUNT);

        assertTrue(claimedAmount > 0);
        assertEq(firstClaimAmount + claimedAmount, TOTAL_VESTING_AMOUNT);
    }

    function test_WhenSenderIsAuthorizedButNotTheOnBehalfUser() external {
        vm.warp(block.timestamp + ALICE_VESTING_DURATION + 1 days);

        uint256 initialBalance = vestingToken.balanceOf(ALICE);

        vm.expectEmit(true, true, true, true);
        emit IAltoVesting.ClaimVesting(ALICE_AUTHORIZED_CALLER, ALICE, ALICE_TOTAL_VESTING_AMOUNT);

        vm.prank(ALICE_AUTHORIZED_CALLER);
        uint256 claimedAmount = vesting.claim(ALICE, aliceVestingInfo, aliceProof);

        assertEq(vestingToken.balanceOf(ALICE), initialBalance + ALICE_TOTAL_VESTING_AMOUNT);

        assertEq(vesting.claimed(ALICE), ALICE_TOTAL_VESTING_AMOUNT);

        assertEq(claimedAmount, ALICE_TOTAL_VESTING_AMOUNT);
    }

    function test_RevertGiven_ClaimedAmountEqualsTotalVestingAmount() external {
        vm.warp(block.timestamp + ALICE_VESTING_DURATION + 1 days);

        vm.prank(ALICE);
        vesting.claim(ALICE, aliceVestingInfo, aliceProof);

        vm.prank(ALICE);
        vm.expectRevert(IAltoVesting.AltoVestingNotEnoughVestedAmount.selector);
        vesting.claim(ALICE, aliceVestingInfo, aliceProof);
    }

    function test_RevertGiven_ClaimedAmountExceedsTotalVestingAmount() external {
        vm.warp(block.timestamp + ALICE_VESTING_DURATION / 2);

        vm.prank(ALICE);
        vesting.claim(ALICE, aliceVestingInfo, aliceProof);

        // reduce alice total vesting amount by half
        VestingInfo memory smallerVestingInfo = VestingInfo({
            startAt: block.timestamp - ALICE_VESTING_DURATION / 2,
            vestingDuration: ALICE_VESTING_DURATION,
            totalVestingAmount: ALICE_TOTAL_VESTING_AMOUNT / 2
        });

        bytes32 smallerLeaf = keccak256(bytes.concat(keccak256(abi.encode(ALICE, smallerVestingInfo))));
        bytes32 bobLeaf = keccak256(bytes.concat(keccak256(abi.encode(BOB, bobVestingInfo))));
        bytes32 smallerRoot = _createMerkleRoot(smallerLeaf, bobLeaf);
        bytes32[] memory smallerProof = new bytes32[](1);
        smallerProof[0] = bobLeaf;

        vm.startPrank(OWNER);
        vesting.submitNewPendingRoot(smallerRoot, bytes32(0));
        vesting.acceptPendingRoot(smallerRoot);
        vm.stopPrank();

        vm.prank(ALICE);
        vm.expectRevert(IAltoVesting.AltoVestingNotEnoughVestedAmount.selector);
        vesting.claim(ALICE, smallerVestingInfo, smallerProof);

        vm.warp(block.timestamp + ALICE_VESTING_DURATION + 1 days);

        vm.prank(ALICE);
        vm.expectRevert(IAltoVesting.AltoVestingNotEnoughVestedAmount.selector);
        vesting.claim(ALICE, smallerVestingInfo, smallerProof);
    }

    function test_Alice_And_Bob_Vesting_With_Update_Disabled_Merkle_Root() external {
        vm.startPrank(ALICE);
        vm.warp(block.timestamp + ALICE_VESTING_DURATION + 1 days);
        uint256 aliceClaimedAmount = nonUpdatableVesting.claim(ALICE, aliceVestingInfo, aliceProof);
        assertEq(aliceClaimedAmount, ALICE_TOTAL_VESTING_AMOUNT);
        assertEq(nonUpdatableVesting.claimed(ALICE), ALICE_TOTAL_VESTING_AMOUNT);
        assertEq(vestingToken.balanceOf(ALICE), ALICE_TOTAL_VESTING_AMOUNT);

        vm.startPrank(BOB);
        vm.warp(block.timestamp + BOB_VESTING_DURATION + 1 days);
        uint256 bobClaimedAmount = nonUpdatableVesting.claim(BOB, bobVestingInfo, bobProof);
        assertEq(bobClaimedAmount, BOB_TOTAL_VESTING_AMOUNT);
        assertEq(nonUpdatableVesting.claimed(BOB), BOB_TOTAL_VESTING_AMOUNT);
        assertEq(vestingToken.balanceOf(BOB), BOB_TOTAL_VESTING_AMOUNT);
        vm.stopPrank();
    }

    function test_Revert_SubmitNewPendingRoot_When_VestingIsNotUpdatable() external {
        vm.startPrank(OWNER);
        vm.expectRevert(IAltoVesting.AltoVestingNotUpdatable.selector);
        nonUpdatableVesting.submitNewPendingRoot(bytes32(uint256(123)), bytes32(0));
        vm.stopPrank();
    }

    function test_RevertAcceptPendingRoot_When_VestingIsNotUpdatable() external {
        vm.startPrank(OWNER);
        AltoVesting newNonUpdatableVesting =
            new AltoVesting(OWNER, INITIAL_TIMELOCK, false, address(vestingToken), bytes32(uint256(123)), bytes32(0));
        vm.stopPrank();

        vm.startPrank(ALICE);
        vm.expectRevert(IMerkleRootManagerErrors.MerkleRootManagerRootNotSet.selector);
        newNonUpdatableVesting.acceptPendingRoot(bytes32(uint256(123)));
        vm.stopPrank();
    }

    function test_Revert_AcceptPendingRoot_When_VestingIsNotUpdatable() external {
        vm.startPrank(OWNER);
        vesting.submitNewPendingRoot(bytes32(uint256(123)), bytes32(0));
        vm.stopPrank();

        vm.startPrank(ALICE);
        vm.expectRevert(IMerkleRootManagerErrors.MerkleRootManagerTimelockNotExpired.selector);
        vesting.acceptPendingRoot(bytes32(uint256(123)));
        vm.stopPrank();

        vm.warp(block.timestamp + INITIAL_TIMELOCK);
        vm.startPrank(ALICE);
        vesting.acceptPendingRoot(bytes32(uint256(123)));
        vm.stopPrank();
    }

    function _createMerkleRoot(bytes32 leaf1, bytes32 leaf2) internal pure returns (bytes32) {
        if (uint256(leaf1) < uint256(leaf2)) {
            return keccak256(abi.encodePacked(leaf1, leaf2));
        } else {
            return keccak256(abi.encodePacked(leaf2, leaf1));
        }
    }
}
