// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {UniversalRewardsDistributor, PAUSE} from "@alto/utils/UniversalRewardsDistributor.sol";
import {IUniversalRewardsDistributor} from "@alto/utils/interfaces/IUniversalRewardsDistributor.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {ERC20MockDecimals} from "@alto-test/helpers/ERC20MockDecimals.sol";

contract UniversalRewardsDistributorClaim is Test {
    UniversalRewardsDistributor public distributor;
    ERC20MockDecimals public rewardToken;
    ERC20MockDecimals public rewardToken2;

    address public OWNER = address(0x1);
    address public UPDATER = address(0x2);
    address public ALICE = address(0x3);
    address public BOB = address(0x4);
    address public AUTHORIZED_CALLER = address(0x5);
    address public PAUSER = address(0x6);

    uint256 public constant INITIAL_TIMELOCK = 1 days;

    // Test merkle tree data
    bytes32 public testRoot;
    bytes32[] public aliceProof;
    bytes32[] public bobProof;
    uint256 public aliceTotalReward = 1000 ether;
    uint256 public bobTotalReward = 2000 ether;

    function setUp() public {
        // Deploy tokens
        rewardToken = new ERC20MockDecimals("Reward Token", "RWD", 18);
        rewardToken2 = new ERC20MockDecimals("Reward Token 2", "RWD2", 6);

        // Setup merkle tree
        _setupMerkleTree();

        // Deploy distributor
        distributor = new UniversalRewardsDistributor(OWNER, INITIAL_TIMELOCK);

        // Setup distributor
        vm.startPrank(OWNER);
        distributor.setMerkleRootUpdater(UPDATER, true);
        distributor.setPauser(PAUSER, PAUSE, true);
        distributor.submitNewPendingRoot(testRoot, bytes32(0));
        distributor.acceptPendingRoot(testRoot);
        vm.stopPrank();

        // Fund distributor with reward tokens
        deal(address(rewardToken), address(distributor), 10000 ether);
        deal(address(rewardToken2), address(distributor), 10000 * 10 ** 6);

        // Setup authorization for AUTHORIZED_CALLER to act on behalf of ALICE
        vm.prank(ALICE);
        distributor.setAuthorization(AUTHORIZED_CALLER, true);
    }

    function _setupMerkleTree() internal {
        bytes32 aliceLeaf =
            keccak256(bytes.concat(keccak256(abi.encode(ALICE, address(rewardToken), aliceTotalReward))));
        bytes32 bobLeaf = keccak256(bytes.concat(keccak256(abi.encode(BOB, address(rewardToken), bobTotalReward))));

        if (uint256(aliceLeaf) < uint256(bobLeaf)) {
            testRoot = keccak256(abi.encodePacked(aliceLeaf, bobLeaf));
            aliceProof = new bytes32[](1);
            aliceProof[0] = bobLeaf;

            bobProof = new bytes32[](1);
            bobProof[0] = aliceLeaf;
        } else {
            testRoot = keccak256(abi.encodePacked(bobLeaf, aliceLeaf));
            aliceProof = new bytes32[](1);
            aliceProof[0] = bobLeaf;

            bobProof = new bytes32[](1);
            bobProof[0] = aliceLeaf;
        }
    }

    function _generateMerkleTreeZeroLeaf()
        internal
        returns (bytes32[] memory p1Proof, bytes32[] memory p2Proof, bytes32 _merkleRoot)
    {
        bytes32 p1Leaf = keccak256(bytes.concat(keccak256(abi.encode(ALICE, address(rewardToken), aliceTotalReward))));
        bytes32 p2Leaf = keccak256(
            bytes.concat(
                keccak256(
                    abi.encode(address(0x0000000000000000000000000000000000000000), address(rewardToken), 1000 ether)
                )
            )
        );

        if (uint256(p1Leaf) < uint256(p2Leaf)) {
            _merkleRoot = keccak256(abi.encodePacked(p1Leaf, p2Leaf));
            p1Proof = new bytes32[](1);
            p1Proof[0] = p2Leaf;

            p2Proof = new bytes32[](1);
            p2Proof[0] = p1Leaf;
        } else {
            _merkleRoot = keccak256(abi.encodePacked(p2Leaf, p1Leaf));
            p1Proof = new bytes32[](1);
            p1Proof[0] = p2Leaf;

            p2Proof = new bytes32[](1);
            p2Proof[0] = p1Leaf;
        }

        return (p1Proof, p2Proof, _merkleRoot);
    }

    function test_RevertWhen_ContractIsPaused() external {
        // Pause the contract
        vm.prank(PAUSER);
        distributor.pause(PAUSE, true);

        vm.prank(ALICE);
        // it should revert with PausablePaused
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSE));
        distributor.claim(ALICE, address(rewardToken), aliceTotalReward, aliceProof);
    }

    function test_RevertWhen_SenderIsNotAuthorizedToActOnBehalfOfOnBehalf() external {
        vm.prank(BOB); // BOB is not authorized to act on behalf of ALICE
        // it should revert with RewardsDistributorUnauthorized
        vm.expectRevert(IUniversalRewardsDistributor.RewardsDistributorUnauthorized.selector);
        distributor.claim(ALICE, address(rewardToken), aliceTotalReward, aliceProof);
    }

    modifier whenMerkleProofIsInvalid() {
        _;
    }

    function test_RevertGiven_MerkleRootIsNotSet() external whenMerkleProofIsInvalid {
        // Set merkle root to some other non-zero value
        vm.startPrank(OWNER);
        distributor.submitNewPendingRoot(bytes32(uint256(999)), bytes32(0));
        distributor.acceptPendingRoot(bytes32(uint256(999)));
        vm.stopPrank();

        // Try to claim with old proof against wrong root
        vm.prank(ALICE);
        // it should revert with RewardsDistributorInvalidInput
        vm.expectRevert(IUniversalRewardsDistributor.RewardsDistributorInvalidInput.selector);
        distributor.claim(ALICE, address(rewardToken), aliceTotalReward, aliceProof);
    }

    function test_RevertGiven_ProofDoesNotVerifyAgainstMerkleRoot() external whenMerkleProofIsInvalid {
        bytes32[] memory invalidProof = new bytes32[](1);
        invalidProof[0] = bytes32(uint256(999));

        vm.prank(ALICE);
        // it should revert with RewardsDistributorInvalidInput
        vm.expectRevert(IUniversalRewardsDistributor.RewardsDistributorInvalidInput.selector);
        distributor.claim(ALICE, address(rewardToken), aliceTotalReward, invalidProof);
    }

    function test_RevertGiven_LeafDataDoesNotMatchProvidedParameters() external whenMerkleProofIsInvalid {
        vm.prank(ALICE);
        // it should revert with RewardsDistributorInvalidInput
        vm.expectRevert(IUniversalRewardsDistributor.RewardsDistributorInvalidInput.selector);
        distributor.claim(ALICE, address(rewardToken), aliceTotalReward + 1, aliceProof); // Wrong total amount
    }

    modifier whenUserHasAlreadyClaimedTheFullAmount() {
        _;
    }

    function test_RevertGiven_ClaimedAmountEqualsTotalRewardTokenAssignedToUser()
        external
        whenUserHasAlreadyClaimedTheFullAmount
    {
        // First claim the full amount
        vm.prank(ALICE);
        distributor.claim(ALICE, address(rewardToken), aliceTotalReward, aliceProof);

        // Try to claim again
        vm.prank(ALICE);
        // it should revert with RewardsDistributorInvalidInput
        vm.expectRevert(IUniversalRewardsDistributor.RewardsDistributorInvalidInput.selector);
        distributor.claim(ALICE, address(rewardToken), aliceTotalReward, aliceProof);
    }

    function test_RevertGiven_ClaimedAmountExceedsTotalRewardTokenAssignedToUser()
        external
        whenUserHasAlreadyClaimedTheFullAmount
    {
        // First make a claim to establish the mapping, then directly override it
        vm.prank(ALICE);
        distributor.claim(ALICE, address(rewardToken), aliceTotalReward, aliceProof);

        // Now manually set claimed amount to exceed total for a new attempt
        // Create a new merkle tree for a smaller amount
        uint256 smallerAmount = aliceTotalReward / 2;
        bytes32 smallerLeaf = keccak256(bytes.concat(keccak256(abi.encode(ALICE, address(rewardToken), smallerAmount))));
        bytes32 smallerRoot = keccak256(abi.encodePacked(smallerLeaf));
        bytes32[] memory smallerProof = new bytes32[](0); // Single leaf tree

        vm.startPrank(OWNER);
        distributor.submitNewPendingRoot(smallerRoot, bytes32(0));
        distributor.acceptPendingRoot(smallerRoot);
        vm.stopPrank();

        vm.prank(ALICE);
        // it should revert with RewardsDistributorInvalidInput
        vm.expectRevert(IUniversalRewardsDistributor.RewardsDistributorInvalidInput.selector);
        distributor.claim(ALICE, address(rewardToken), smallerAmount, smallerProof);
    }

    modifier whenAllConditionsAreMetForValidClaim() {
        _;
    }

    function test_WhenUserHasNeverClaimedBefore() external whenAllConditionsAreMetForValidClaim {
        uint256 initialBalance = rewardToken.balanceOf(ALICE);

        // it should emit ClaimRewardToken event
        vm.expectEmit(true, true, true, true);
        emit IUniversalRewardsDistributor.ClaimRewardToken(ALICE, ALICE, address(rewardToken), aliceTotalReward);

        vm.prank(ALICE);
        uint256 claimedAmount = distributor.claim(ALICE, address(rewardToken), aliceTotalReward, aliceProof);

        // it should transfer full totalRewardTokenAssignedToUser amount
        assertEq(rewardToken.balanceOf(ALICE), initialBalance + aliceTotalReward);

        // it should update claimed mapping to totalRewardTokenAssignedToUser
        assertEq(distributor.claimed(ALICE, address(rewardToken)), aliceTotalReward);

        // it should return the claimed amount
        assertEq(claimedAmount, aliceTotalReward);
    }

    function test_WhenUserHasPartiallyClaimedBefore() external whenAllConditionsAreMetForValidClaim {
        uint256 firstClaimAmount = aliceTotalReward / 3;

        // Setup merkle tree for partial claim first
        bytes32 partialAliceLeaf =
            keccak256(bytes.concat(keccak256(abi.encode(ALICE, address(rewardToken), firstClaimAmount))));
        bytes32 partialBobLeaf =
            keccak256(bytes.concat(keccak256(abi.encode(BOB, address(rewardToken), bobTotalReward))));

        bytes32 partialRoot;
        bytes32[] memory partialAliceProof = new bytes32[](1);

        if (uint256(partialAliceLeaf) < uint256(partialBobLeaf)) {
            partialRoot = keccak256(abi.encodePacked(partialAliceLeaf, partialBobLeaf));
            partialAliceProof[0] = partialBobLeaf;
        } else {
            partialRoot = keccak256(abi.encodePacked(partialBobLeaf, partialAliceLeaf));
            partialAliceProof[0] = partialBobLeaf;
        }

        // Set partial root and make first claim
        vm.startPrank(OWNER);
        distributor.submitNewPendingRoot(partialRoot, bytes32(0));
        distributor.acceptPendingRoot(partialRoot);
        vm.stopPrank();

        vm.prank(ALICE);
        distributor.claim(ALICE, address(rewardToken), firstClaimAmount, partialAliceProof);

        // Now set up for full claim with updated merkle root
        vm.startPrank(OWNER);
        distributor.submitNewPendingRoot(testRoot, bytes32(0));
        distributor.acceptPendingRoot(testRoot);
        vm.stopPrank();

        uint256 balanceBeforeSecondClaim = rewardToken.balanceOf(ALICE);
        uint256 expectedRemainingAmount = aliceTotalReward - firstClaimAmount;

        // it should emit ClaimRewardToken event
        vm.expectEmit(true, true, true, true);
        emit IUniversalRewardsDistributor.ClaimRewardToken(ALICE, ALICE, address(rewardToken), expectedRemainingAmount);

        vm.prank(ALICE);
        uint256 claimedAmount = distributor.claim(ALICE, address(rewardToken), aliceTotalReward, aliceProof);

        // it should transfer remaining unclaimed amount
        assertEq(rewardToken.balanceOf(ALICE), balanceBeforeSecondClaim + expectedRemainingAmount);

        // it should update claimed mapping to totalRewardTokenAssignedToUser
        assertEq(distributor.claimed(ALICE, address(rewardToken)), aliceTotalReward);

        // it should return the newly claimed amount
        assertEq(claimedAmount, expectedRemainingAmount);
    }

    function test_WhenSenderIsAuthorizedButNotTheOnBehalfUser() external whenAllConditionsAreMetForValidClaim {
        uint256 initialBalance = rewardToken.balanceOf(ALICE);

        // it should emit ClaimRewardToken event with correct caller and onBehalf
        vm.expectEmit(true, true, true, true);
        emit IUniversalRewardsDistributor.ClaimRewardToken(
            AUTHORIZED_CALLER, ALICE, address(rewardToken), aliceTotalReward
        );

        vm.prank(AUTHORIZED_CALLER); // Authorized caller claiming on behalf of ALICE
        uint256 claimedAmount = distributor.claim(ALICE, address(rewardToken), aliceTotalReward, aliceProof);

        // it should transfer tokens to onBehalf address
        assertEq(rewardToken.balanceOf(ALICE), initialBalance + aliceTotalReward);

        // it should update claimed mapping for onBehalf
        assertEq(distributor.claimed(ALICE, address(rewardToken)), aliceTotalReward);

        // it should return the claimed amount
        assertEq(claimedAmount, aliceTotalReward);
    }
}
