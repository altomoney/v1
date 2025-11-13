// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {AltoVesting} from "@alto/vesting/AltoVesting.sol";
import {IAltoVesting, VestingInfo} from "@alto/vesting/interfaces/IAltoVesting.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {ERC20MockMintable} from "@alto-test/helpers/ERC20MockMintable.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";

contract AltoVestingClaim is Test {
    AltoVesting public vesting;
    ERC20MockMintable public vestingToken;

    address public OWNER = makeAddr("owner");
    address public UPDATER = makeAddr("updater");
    address public ALICE = makeAddr("alice");
    address public BOB = makeAddr("bob");
    address public ALICE_AUTHORIZED_CALLER = makeAddr("alice-authorized-caller");
    address public PAUSER = makeAddr("pauser");

    uint256 public constant INITIAL_TIMELOCK = 3 days;
    uint256 public constant VESTING_DURATION = 365 days;
    uint256 public constant TOTAL_VESTING_AMOUNT = 1000 ether;

    bytes32 public merkleRoot;
    bytes32[] public aliceProof;
    bytes32 public aliceLeaf;
    bytes32 public bobLeaf;
    VestingInfo public aliceVestingInfo;
    VestingInfo public bobVestingInfo;

    // Modifiers for BTT structure
    modifier givenContractIsPaused() {
        vm.prank(PAUSER);
        vesting.pause(PAUSE_TYPE, true);
        _;
    }

    modifier givenSenderIsNotAuthorized() {
        // Alice is not authorized by default
        _;
    }

    modifier givenSenderIsAuthorized() {
        vm.prank(ALICE);
        vesting.setAuthorization(ALICE_AUTHORIZED_CALLER, true);
        _;
    }

    modifier givenVestingDurationIsZero() {
        _;
    }

    modifier givenMerkleProofIsInvalid() {
        // Use invalid proof
        aliceProof = new bytes32[](1);
        aliceProof[0] = keccak256("invalid");
        _;
    }

    modifier givenMerkleProofIsValid() {
        // Merkle proof is valid by default
        _;
    }

    modifier givenVestingHasNotStarted() {
        _;
    }

    modifier givenUserHasAlreadyClaimedFullAmount() {
        // First claim the full amount
        vm.prank(ALICE);
        vesting.claim(ALICE, aliceVestingInfo, aliceProof);
        _;
    }

    modifier givenUserHasPartiallyClaimed() {
        // First claim partial amount
        vm.prank(ALICE);
        vesting.claim(ALICE, aliceVestingInfo, aliceProof);
        _;
    }

    modifier givenUserHasNeverClaimed() {
        // User has never claimed by default
        _;
    }

    modifier givenVestingIsFullyVested() {
        vm.warp(block.timestamp + VESTING_DURATION);
        _;
    }

    modifier givenVestingIsPartiallyVested() {
        vm.warp(block.timestamp + VESTING_DURATION / 2);
        _;
    }

    function setUp() public {
        vestingToken = new ERC20MockMintable("Alto Token", "ALTO");

        aliceVestingInfo = VestingInfo({
            startAt: block.timestamp, vestingDuration: VESTING_DURATION, totalVestingAmount: TOTAL_VESTING_AMOUNT
        });

        bobVestingInfo = VestingInfo({
            startAt: block.timestamp, vestingDuration: VESTING_DURATION, totalVestingAmount: TOTAL_VESTING_AMOUNT
        });

        _setupMerkleTree();

        vesting = new AltoVesting(OWNER, INITIAL_TIMELOCK, true, address(vestingToken), merkleRoot, bytes32(0));

        vm.startPrank(OWNER);
        vesting.setMerkleRootUpdater(UPDATER, true);
        vesting.setPauser(PAUSER, PAUSE_TYPE, true);
        vesting.acceptPendingRoot(merkleRoot);
        vm.stopPrank();

        vestingToken.mint(address(vesting), 2 * TOTAL_VESTING_AMOUNT);
    }

    function _setupMerkleTree() internal {
        aliceLeaf = keccak256(bytes.concat(keccak256(abi.encode(ALICE, aliceVestingInfo))));
        bobLeaf = keccak256(bytes.concat(keccak256(abi.encode(BOB, bobVestingInfo))));

        if (uint256(aliceLeaf) < uint256(bobLeaf)) {
            merkleRoot = keccak256(abi.encodePacked(aliceLeaf, bobLeaf));
            aliceProof = new bytes32[](1);
            aliceProof[0] = bobLeaf;
        } else {
            merkleRoot = keccak256(abi.encodePacked(bobLeaf, aliceLeaf));
            aliceProof = new bytes32[](1);
            aliceProof[0] = bobLeaf;
        }
    }

    function test_RevertWhen_ContractIsPaused() external givenContractIsPaused {
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSE_TYPE));
        vesting.claim(ALICE, aliceVestingInfo, aliceProof);
    }

    function test_RevertWhen_SenderIsNotAuthorizedToActOnBehalfOfOnBehalf() external givenSenderIsNotAuthorized {
        vm.prank(BOB);
        vm.expectRevert(IAltoVesting.AltoVestingUnauthorized.selector);
        vesting.claim(ALICE, aliceVestingInfo, aliceProof);
    }

    function test_RevertWhen_VestingDurationIsZero() external givenVestingDurationIsZero {
        // Update merkle root for zero duration vesting
        VestingInfo memory invalidVestingInfo =
            VestingInfo({startAt: block.timestamp, vestingDuration: 0, totalVestingAmount: TOTAL_VESTING_AMOUNT});

        bytes32 invalidLeaf = keccak256(bytes.concat(keccak256(abi.encode(ALICE, invalidVestingInfo))));
        bytes32 invalidRoot = _createMerkleRoot(invalidLeaf, bobLeaf);
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

    function test_RevertGiven_ProofDoesNotVerifyAgainstMerkleRoot() external givenMerkleProofIsInvalid {
        vm.prank(ALICE);
        vm.expectRevert(IAltoVesting.AltoVestingInvalidInput.selector);
        vesting.claim(ALICE, aliceVestingInfo, aliceProof);
    }

    function test_RevertGiven_VestingInfoDoesNotMatchProvidedParameters() external givenMerkleProofIsValid {
        VestingInfo memory wrongVestingInfo = VestingInfo({
            startAt: block.timestamp, vestingDuration: VESTING_DURATION, totalVestingAmount: TOTAL_VESTING_AMOUNT + 1
        });

        vm.prank(ALICE);
        vm.expectRevert(IAltoVesting.AltoVestingInvalidInput.selector);
        vesting.claim(ALICE, wrongVestingInfo, aliceProof);
    }

    function test_RevertGiven_ClaimedAmountEqualsVestedAmount()
        external
        givenVestingIsFullyVested
        givenUserHasAlreadyClaimedFullAmount
    {
        vm.prank(ALICE);
        vm.expectRevert(IAltoVesting.AltoVestingNotEnoughVestedAmount.selector);
        vesting.claim(ALICE, aliceVestingInfo, aliceProof);
    }

    function test_RevertGiven_ClaimedAmountExceedsVestedAmount() external {
        vm.warp(block.timestamp + VESTING_DURATION / 2);

        vm.prank(ALICE);
        vesting.claim(ALICE, aliceVestingInfo, aliceProof);

        VestingInfo memory smallerVestingInfo = VestingInfo({
            startAt: block.timestamp - VESTING_DURATION / 2,
            vestingDuration: VESTING_DURATION,
            totalVestingAmount: TOTAL_VESTING_AMOUNT / 2
        });

        bytes32 smallerLeaf = keccak256(bytes.concat(keccak256(abi.encode(ALICE, smallerVestingInfo))));
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
    }

    function test_RevertWhen_VestingHasNotStarted_CurrentTimestampIsBeforeStartAt() external givenVestingHasNotStarted {
        // Update merkle root for future vesting
        VestingInfo memory futureVestingInfo = VestingInfo({
            startAt: block.timestamp + 1 days,
            vestingDuration: VESTING_DURATION,
            totalVestingAmount: TOTAL_VESTING_AMOUNT
        });

        bytes32 futureLeaf = keccak256(bytes.concat(keccak256(abi.encode(ALICE, futureVestingInfo))));
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

    function test_RevertWhen_VestingHasNotStarted_CurrentTimestampEqualsStartAt() external givenVestingHasNotStarted {
        vm.prank(ALICE);
        vm.expectRevert(IAltoVesting.AltoVestingInvalidInput.selector);
        vesting.claim(ALICE, aliceVestingInfo, aliceProof);
    }

    function test_WhenVestingIsFullyVested() external givenVestingIsFullyVested givenUserHasNeverClaimed {
        uint256 initialBalance = vestingToken.balanceOf(ALICE);

        vm.expectEmit(true, true, true, true);
        emit IAltoVesting.ClaimVesting(ALICE, ALICE, TOTAL_VESTING_AMOUNT);

        vm.prank(ALICE);
        uint256 claimedAmount = vesting.claim(ALICE, aliceVestingInfo, aliceProof);

        assertEq(claimedAmount, TOTAL_VESTING_AMOUNT);
        assertEq(vestingToken.balanceOf(ALICE), initialBalance + TOTAL_VESTING_AMOUNT);
        assertEq(vesting.claimed(ALICE), TOTAL_VESTING_AMOUNT);
    }

    function test_WhenVestingIsPartiallyVested() external givenVestingIsPartiallyVested givenUserHasNeverClaimed {
        uint256 initialBalance = vestingToken.balanceOf(ALICE);

        vm.expectEmit(true, true, true, true);
        emit IAltoVesting.ClaimVesting(ALICE, ALICE, TOTAL_VESTING_AMOUNT / 2);

        vm.prank(ALICE);
        uint256 claimedAmount = vesting.claim(ALICE, aliceVestingInfo, aliceProof);

        assertEq(claimedAmount, TOTAL_VESTING_AMOUNT / 2);
        assertEq(vestingToken.balanceOf(ALICE), initialBalance + claimedAmount);
        assertEq(vesting.claimed(ALICE), claimedAmount);
    }

    function test_WhenUserHasPartiallyClaimedBefore()
        external
        givenVestingIsPartiallyVested
        givenUserHasPartiallyClaimed
    {
        // half amount was vested, so now we claim the remaining half
        vm.warp(block.timestamp + VESTING_DURATION / 2 + 1 days);
        uint256 balanceBeforeSecondClaim = vestingToken.balanceOf(ALICE);

        vm.expectEmit(true, true, true, true);
        emit IAltoVesting.ClaimVesting(ALICE, ALICE, TOTAL_VESTING_AMOUNT / 2);
        vm.prank(ALICE);
        uint256 claimedAmount = vesting.claim(ALICE, aliceVestingInfo, aliceProof);

        assertEq(vestingToken.balanceOf(ALICE), balanceBeforeSecondClaim + claimedAmount);
        assertEq(vesting.claimed(ALICE), TOTAL_VESTING_AMOUNT);
        assertEq(claimedAmount, TOTAL_VESTING_AMOUNT / 2);
    }

    function test_WhenSenderIsAuthorizedButNotTheOnBehalfUser()
        external
        givenVestingIsFullyVested
        givenSenderIsAuthorized
        givenUserHasNeverClaimed
    {
        uint256 initialBalance = vestingToken.balanceOf(ALICE);

        vm.expectEmit(true, true, true, true);
        emit IAltoVesting.ClaimVesting(ALICE_AUTHORIZED_CALLER, ALICE, TOTAL_VESTING_AMOUNT);

        vm.prank(ALICE_AUTHORIZED_CALLER);
        uint256 claimedAmount = vesting.claim(ALICE, aliceVestingInfo, aliceProof);

        assertEq(vestingToken.balanceOf(ALICE), initialBalance + TOTAL_VESTING_AMOUNT);
        assertEq(vesting.claimed(ALICE), TOTAL_VESTING_AMOUNT);
        assertEq(claimedAmount, TOTAL_VESTING_AMOUNT);
    }

    function _createMerkleRoot(bytes32 leaf1, bytes32 leaf2) internal pure returns (bytes32) {
        if (uint256(leaf1) < uint256(leaf2)) {
            return keccak256(abi.encodePacked(leaf1, leaf2));
        } else {
            return keccak256(abi.encodePacked(leaf2, leaf1));
        }
    }
}
