// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {AltoReferralWhitelistAdapter} from "@alto/rewards/adapters/AltoReferralWhitelistAdapter.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

abstract contract ReferralWhitelistAdapterCommon is Test {
    AltoReferralWhitelistAdapter public adapter;

    address public constant OWNER = address(0x1);
    address public constant ALICE = address(0x2);
    address public constant BOB = address(0x3);
    address public constant CHARLIE = address(0x4);
    address public constant DAVE = address(0x5);
    address public constant EVE = address(0x6);

    uint256 public constant INITIAL_BONUS_DISCOUNT = 0.05 ether; // 5%
    uint256 public constant INITIAL_PAYMENT_TOKEN_SHARE = 0.03 ether; // 3%

    // Merkle tree data for testing
    bytes32[] public merkleLeaves;
    bytes32 public merkleRoot;

    // Sample proof data - these would be generated off-chain in practice
    bytes32[] public aliceProof;
    bytes32[] public bobProof;
    bytes32[] public charlieProof;

    function setUp() public virtual {
        // Setup merkle tree for whitelist testing
        _setupMerkleTree();

        // Deploy adapter contract
        vm.prank(OWNER);
        adapter = new AltoReferralWhitelistAdapter(INITIAL_BONUS_DISCOUNT, INITIAL_PAYMENT_TOKEN_SHARE);

        // Set merkle root for whitelist activation
        vm.prank(OWNER);
        adapter.submitNewPendingRoot(merkleRoot, bytes32(0));
        vm.prank(OWNER);
        adapter.acceptPendingRoot(merkleRoot);
    }

    function _setupMerkleTree() internal {
        // Create leaves for users
        merkleLeaves = new bytes32[](3);
        merkleLeaves[0] = keccak256(abi.encode(ALICE));
        merkleLeaves[1] = keccak256(abi.encode(BOB));
        merkleLeaves[2] = keccak256(abi.encode(CHARLIE));

        // Calculate merkle root
        bytes32[] memory level1 = new bytes32[](2);
        level1[0] = _hashPair(merkleLeaves[0], merkleLeaves[1]);
        level1[1] = merkleLeaves[2];

        merkleRoot = _hashPair(level1[0], level1[1]);

        // Generate proofs
        aliceProof = new bytes32[](2);
        aliceProof[0] = merkleLeaves[1]; // Bob's leaf
        aliceProof[1] = merkleLeaves[2]; // Charlie's leaf

        bobProof = new bytes32[](2);
        bobProof[0] = merkleLeaves[0]; // Alice's leaf
        bobProof[1] = merkleLeaves[2]; // Charlie's leaf

        charlieProof = new bytes32[](1);
        charlieProof[0] = _hashPair(merkleLeaves[0], merkleLeaves[1]); // Hash of Alice and Bob
    }

    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    modifier givenOwnerIsCaller() {
        vm.startPrank(OWNER);
        _;
        vm.stopPrank();
    }

    modifier givenUserIsWhitelisted(address user) {
        vm.prank(OWNER);
        adapter.setReferralWhitelist(user, true);
        _;
    }

    modifier givenUserHasReferral(address user, address referral) {
        vm.prank(OWNER);
        adapter.setReferral(user, referral);
        _;
    }
}
