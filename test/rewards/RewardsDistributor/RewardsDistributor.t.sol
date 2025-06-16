// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {RewardsDistributor, CLAIM_PAUSE_TYPE} from "@alto/rewards/RewardsDistributor.sol";
import {PendingRoot} from "@alto/rewards/interfaces/IRewardsDistributor.sol";
import {RewardErrorsLib} from "@alto/rewards/libraries/RewardErrorsLib.sol";
import {RewardEventsLib} from "@alto/rewards/libraries/RewardEventsLib.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "@alto-test/helpers/ERC20Mock.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";

contract MockOracle {
    int256 public price;
    uint8 public decimals;

    constructor(int256 _price, uint8 _decimals) {
        price = _price;
        decimals = _decimals;
    }

    function latestAnswer() external view returns (int256) {
        return price;
    }

    function setPrice(int256 _price) external {
        price = _price;
    }
}

contract MockLock {
    mapping(address => uint256) public locked;
    address public lastTo;
    uint256 public lastAmount;
    IERC20 public rewardToken;

    constructor(address _rewardToken) {
        rewardToken = IERC20(_rewardToken);
    }

    function lock(uint256 amount, address to) external {
        locked[to] += amount;
        lastTo = to;
        lastAmount = amount;
        // Pull tokens from caller (RewardsDistributor)
        rewardToken.transferFrom(msg.sender, address(this), amount);
    }
}

contract RewardsDistributorTest is Test {
    RewardsDistributor public distributor;
    ERC20Mock public rewardToken;
    ERC20Mock public paymentToken;
    ERC20Mock public paymentToken2;
    MockOracle public paymentOracle;
    MockOracle public paymentOracle2;
    MockLock public lockContract;

    address public owner = address(0x1);
    address public updater = address(0x2);
    address public alice = address(0x3);
    address public bob = address(0x4);

    uint256 public constant INITIAL_TIMELOCK = 1 days;
    bytes32 public constant INITIAL_IPFS_HASH = bytes32(0);

    // Test merkle tree data
    bytes32 public testRoot;
    bytes32[] public aliceProof;
    bytes32[] public bobProof;
    uint256 public aliceAvailable = 1000 * 10 ** 18;
    uint256 public bobAvailable = 2000 * 10 ** 18;

    // Pricing constants
    uint256 public constant REWARD_PRICE = 100 * 10 ** 8; // $100 per token (8 decimals)
    uint256 public constant PAYMENT_TOKEN_PRICE = 1 * 10 ** 8; // $1 per payment token (8 decimals)
    uint256 public constant BASE_DISCOUNT = 1000; // 10%
    uint256 public constant LOCK_BONUS_DISCOUNT = 500; // 5% additional

    function setUp() public {
        // Deploy tokens
        rewardToken = new ERC20Mock("Reward Token", "RWD", 18);
        paymentToken = new ERC20Mock("Payment Token", "PAY", 6);
        paymentToken2 = new ERC20Mock("Payment Token 2", "PAY2", 18);

        // Deploy oracles
        paymentOracle = new MockOracle(int256(PAYMENT_TOKEN_PRICE), 8);
        paymentOracle2 = new MockOracle(int256(2 * 10 ** 8), 8); // $2 per token

        // Deploy lock contract
        lockContract = new MockLock(address(rewardToken));

        // Setup merkle tree
        _setupMerkleTree();

        // Deploy distributor
        distributor = new RewardsDistributor(owner, INITIAL_TIMELOCK, testRoot, INITIAL_IPFS_HASH, address(rewardToken));

        // Setup distributor
        vm.startPrank(owner);
        distributor.setRootUpdater(updater, true);
        distributor.setPaymentToken(address(paymentToken), address(paymentOracle));
        distributor.setPaymentToken(address(paymentToken2), address(paymentOracle2));
        distributor.setRewardPrice(REWARD_PRICE);
        distributor.setDiscount(BASE_DISCOUNT);
        distributor.setLockBonusDiscount(LOCK_BONUS_DISCOUNT);
        distributor.setLockContract(address(lockContract));
        vm.stopPrank();

        // Fund distributor with reward tokens
        rewardToken.mint(address(distributor), 10000 * 10 ** 18);

        // Fund users with payment tokens
        paymentToken.mint(alice, 1000000 * 10 ** 6); // 1M tokens with 6 decimals
        paymentToken.mint(bob, 1000000 * 10 ** 6);
        paymentToken2.mint(alice, 1000000 * 10 ** 18); // 1M tokens with 18 decimals
        paymentToken2.mint(bob, 1000000 * 10 ** 18);
    }

    function _setupMerkleTree() internal {
        // Create leaves - the leaves are double hashed as per the contract implementation
        bytes32 aliceLeaf = keccak256(bytes.concat(keccak256(abi.encode(alice, aliceAvailable))));
        bytes32 bobLeaf = keccak256(bytes.concat(keccak256(abi.encode(bob, bobAvailable))));

        // For a proper merkle tree, we need to order the leaves
        if (uint256(aliceLeaf) < uint256(bobLeaf)) {
            testRoot = keccak256(abi.encodePacked(aliceLeaf, bobLeaf));
            // Proofs
            aliceProof = new bytes32[](1);
            aliceProof[0] = bobLeaf;

            bobProof = new bytes32[](1);
            bobProof[0] = aliceLeaf;
        } else {
            testRoot = keccak256(abi.encodePacked(bobLeaf, aliceLeaf));
            // Proofs
            aliceProof = new bytes32[](1);
            aliceProof[0] = bobLeaf;

            bobProof = new bytes32[](1);
            bobProof[0] = aliceLeaf;
        }
    }

    function _setupMerkleTree(uint256 aliceClaim, uint256 bobClaim)
        internal
        returns (bytes32 root, bytes32[] memory aliceProofResult, bytes32[] memory bobProofResult)
    {
        // Create leaves - the leaves are double hashed as per the contract implementation
        bytes32 aliceLeaf = keccak256(bytes.concat(keccak256(abi.encode(alice, aliceClaim))));
        bytes32 bobLeaf = keccak256(bytes.concat(keccak256(abi.encode(bob, bobClaim))));

        // For a proper merkle tree, we need to order the leaves
        if (uint256(aliceLeaf) < uint256(bobLeaf)) {
            testRoot = keccak256(abi.encodePacked(aliceLeaf, bobLeaf));
            // Proofs
            aliceProof = new bytes32[](1);
            aliceProof[0] = bobLeaf;

            bobProof = new bytes32[](1);
            bobProof[0] = aliceLeaf;
        } else {
            testRoot = keccak256(abi.encodePacked(bobLeaf, aliceLeaf));
            // Proofs
            aliceProof = new bytes32[](1);
            aliceProof[0] = bobLeaf;

            bobProof = new bytes32[](1);
            bobProof[0] = aliceLeaf;
        }

        return (testRoot, aliceProof, bobProof);
    }

    function test_Constructor() public {
        assertEq(distributor.owner(), owner);
        assertEq(distributor.timelock(), INITIAL_TIMELOCK);
        assertEq(distributor.root(), testRoot);
        assertEq(distributor.ipfsHash(), INITIAL_IPFS_HASH);
        assertEq(distributor.rewardToken(), address(rewardToken));
    }

    function test_SetPaymentToken() public {
        address newToken = address(new ERC20Mock("New Token", "NEW", 18));
        address newOracle = address(new MockOracle(int256(100 * 10 ** 8), 8));

        vm.expectEmit(true, true, false, false);
        emit RewardEventsLib.PaymentTokenSet(newToken, newOracle);

        vm.prank(owner);
        distributor.setPaymentToken(newToken, newOracle);

        assertEq(distributor.paymentTokens(newToken), newOracle);
    }

    function test_SetRewardPrice() public {
        uint256 newPrice = 200 * 10 ** 8;

        vm.expectEmit(false, false, false, true);
        emit RewardEventsLib.RewardPriceSet(newPrice);

        vm.prank(owner);
        distributor.setRewardPrice(newPrice);

        assertEq(distributor.rewardPrice(), newPrice);
    }

    function test_SetDiscount() public {
        uint256 newDiscount = 2000; // 20%

        vm.expectEmit(false, false, false, true);
        emit RewardEventsLib.DiscountSet(newDiscount);

        vm.prank(owner);
        distributor.setDiscount(newDiscount);

        assertEq(distributor.discount(), newDiscount);
    }

    function test_SetLockBonusDiscount() public {
        uint256 newLockBonusDiscount = 1000; // 10%

        vm.expectEmit(false, false, false, true);
        emit RewardEventsLib.LockBonusDiscountSet(newLockBonusDiscount);

        vm.prank(owner);
        distributor.setLockBonusDiscount(newLockBonusDiscount);

        assertEq(distributor.lockBonusDiscount(), newLockBonusDiscount);
    }

    function test_SetLock() public {
        address newLock = address(0x999);

        vm.expectEmit(true, false, false, false);
        emit RewardEventsLib.LockSet(newLock);

        vm.prank(owner);
        distributor.setLockContract(newLock);

        assertEq(distributor.lockContract(), newLock);
    }

    function test_ClaimPurchase_FullAmount_NoLock() public {
        // Approve payment
        vm.startPrank(alice);
        paymentToken.approve(address(distributor), type(uint256).max);

        // Calculate expected payment
        // 1000 tokens * $100/token = $100,000
        // With 10% discount = $90,000
        // At $1/payment token = 90,000 payment tokens (6 decimals) = 90,000 * 10^6
        uint256 expectedPayment = 90000 * 10 ** 6;

        uint256 alicePaymentBefore = paymentToken.balanceOf(alice);
        uint256 aliceRewardBefore = rewardToken.balanceOf(alice);

        // Purchase full amount
        uint256 purchased =
            distributor.claimPurchase(aliceAvailable, aliceProof, aliceAvailable, address(paymentToken), false);

        assertEq(purchased, aliceAvailable);
        assertEq(distributor.assigned(alice), aliceAvailable);
        assertEq(distributor.purchased(alice), aliceAvailable);
        assertEq(paymentToken.balanceOf(alice), alicePaymentBefore - expectedPayment);
        assertEq(rewardToken.balanceOf(alice), aliceRewardBefore + aliceAvailable);
        vm.stopPrank();
    }

    function test_ClaimPurchase_PartialAmounts() public {
        // Approve payment
        vm.startPrank(alice);
        paymentToken.approve(address(distributor), type(uint256).max);

        // Purchase 30% first
        uint256 firstPurchase = (aliceAvailable * 30) / 100;
        distributor.claimPurchase(aliceAvailable, aliceProof, firstPurchase, address(paymentToken), false);

        assertEq(distributor.assigned(alice), aliceAvailable);
        assertEq(distributor.purchased(alice), firstPurchase);

        // Purchase another 50%
        uint256 secondPurchase = (aliceAvailable * 50) / 100;
        distributor.claimPurchase(aliceAvailable, aliceProof, secondPurchase, address(paymentToken), false);

        assertEq(distributor.purchased(alice), firstPurchase + secondPurchase);

        // Purchase remaining 20%
        uint256 remaining = aliceAvailable - distributor.purchased(alice);
        distributor.claimPurchase(aliceAvailable, aliceProof, remaining, address(paymentToken), false);

        assertEq(distributor.purchased(alice), aliceAvailable);
        vm.stopPrank();
    }

    function test_ClaimPurchase_WithLock() public {
        // Approve payment
        vm.startPrank(alice);
        paymentToken.approve(address(distributor), type(uint256).max);

        // Calculate expected payment with lock discount
        // 1000 tokens * $100/token = $100,000
        // With 5% lock bonus discount (not combined with base discount) = $95,000
        // At $1/payment token = 95,000 payment tokens
        uint256 expectedPayment = 95000 * 10 ** 6;

        uint256 alicePaymentBefore = paymentToken.balanceOf(alice);

        // Purchase with lock
        distributor.claimPurchase(aliceAvailable, aliceProof, aliceAvailable, address(paymentToken), true);

        assertEq(paymentToken.balanceOf(alice), alicePaymentBefore - expectedPayment);
        assertEq(lockContract.locked(alice), aliceAvailable);
        assertEq(lockContract.lastTo(), alice);
        assertEq(lockContract.lastAmount(), aliceAvailable);
        vm.stopPrank();
    }

    function test_ClaimPurchase_DifferentPaymentToken() public {
        // Use payment token 2 ($2 per token)
        vm.startPrank(alice);
        paymentToken2.approve(address(distributor), type(uint256).max);

        // Calculate expected payment
        // 1000 tokens * $100/token = $100,000
        // With 10% discount = $90,000
        // At $2/payment token = 45,000 payment tokens (18 decimals)
        uint256 expectedPayment = 45000 * 10 ** 18;

        uint256 alicePaymentBefore = paymentToken2.balanceOf(alice);
        uint256 aliceRewardBefore = rewardToken.balanceOf(alice);

        distributor.claimPurchase(aliceAvailable, aliceProof, aliceAvailable, address(paymentToken2), false);

        assertEq(paymentToken2.balanceOf(alice), alicePaymentBefore - expectedPayment);
        assertEq(distributor.purchased(alice), aliceAvailable);
        assertEq(distributor.assigned(alice), aliceAvailable);
        assertEq(rewardToken.balanceOf(alice), aliceRewardBefore + aliceAvailable);
        vm.stopPrank();
    }

    function test_ClaimPurchase_RevertIf_ExceedsAllocation() public {
        vm.startPrank(alice);
        paymentToken.approve(address(distributor), type(uint256).max);

        // Try to purchase more than allocated
        vm.expectRevert(RewardErrorsLib.InvalidPurchaseAmount.selector);
        distributor.claimPurchase(aliceAvailable, aliceProof, aliceAvailable + 1, address(paymentToken), false);
        vm.stopPrank();
    }

    function test_ClaimPurchase_RevertIf_AlreadyFullyPurchased() public {
        vm.startPrank(alice);
        paymentToken.approve(address(distributor), type(uint256).max);

        // Purchase full amount
        distributor.claimPurchase(aliceAvailable, aliceProof, aliceAvailable, address(paymentToken), false);

        // Try to purchase again
        vm.expectRevert(RewardErrorsLib.InvalidPurchaseAmount.selector);
        distributor.claimPurchase(aliceAvailable, aliceProof, 1, address(paymentToken), false);
        vm.stopPrank();
    }

    function test_ClaimPurchase_RevertIf_InvalidPaymentToken() public {
        vm.startPrank(alice);

        // Try with unregistered payment token
        vm.expectRevert(RewardErrorsLib.InvalidPaymentToken.selector);
        distributor.claimPurchase(aliceAvailable, aliceProof, aliceAvailable, address(0x999), false);
        vm.stopPrank();
    }

    function test_ClaimPurchase_RevertIf_PriceNotSet() public {
        // Deploy new distributor without setting price
        RewardsDistributor newDistributor =
            new RewardsDistributor(owner, INITIAL_TIMELOCK, testRoot, INITIAL_IPFS_HASH, address(rewardToken));

        vm.prank(owner);
        newDistributor.setPaymentToken(address(paymentToken), address(paymentOracle));

        vm.startPrank(alice);
        paymentToken.approve(address(newDistributor), type(uint256).max);

        vm.expectRevert(RewardErrorsLib.PriceNotSet.selector);
        newDistributor.claimPurchase(aliceAvailable, aliceProof, aliceAvailable, address(paymentToken), false);
        vm.stopPrank();
    }

    function test_ClaimPurchase_RevertIf_LockNotSet() public {
        // Deploy new distributor without setting lock
        RewardsDistributor newDistributor =
            new RewardsDistributor(owner, INITIAL_TIMELOCK, testRoot, INITIAL_IPFS_HASH, address(rewardToken));

        vm.startPrank(owner);
        newDistributor.setPaymentToken(address(paymentToken), address(paymentOracle));
        newDistributor.setRewardPrice(REWARD_PRICE);
        vm.stopPrank();

        // Fund distributor
        rewardToken.mint(address(newDistributor), 10000 * 10 ** 18);

        vm.startPrank(alice);
        paymentToken.approve(address(newDistributor), type(uint256).max);

        vm.expectRevert(RewardErrorsLib.LockNotSet.selector);
        newDistributor.claimPurchase(
            aliceAvailable,
            aliceProof,
            aliceAvailable,
            address(paymentToken),
            true // try to lock
        );
        vm.stopPrank();
    }

    function test_MerkleTreeUpdate_IncreasedAllocation() public {
        // Set initial root

        // Alice purchases half of initial allocation
        vm.startPrank(alice);
        paymentToken.approve(address(distributor), type(uint256).max);

        uint256 firstPurchase = aliceAvailable / 2;
        distributor.claimPurchase(aliceAvailable, aliceProof, firstPurchase, address(paymentToken), false);

        assertEq(distributor.assigned(alice), aliceAvailable);
        assertEq(distributor.purchased(alice), firstPurchase);
        vm.stopPrank();

        // Create new merkle tree with increased allocation
        uint256 aliceNewAvailable = 1500 * 10 ** 18;
        bytes32 aliceNewLeaf = keccak256(bytes.concat(keccak256(abi.encode(alice, aliceNewAvailable))));
        bytes32 bobLeaf = keccak256(bytes.concat(keccak256(abi.encode(bob, bobAvailable))));

        bytes32 newRoot;
        bytes32[] memory aliceNewProof = new bytes32[](1);

        if (uint256(aliceNewLeaf) < uint256(bobLeaf)) {
            newRoot = keccak256(abi.encodePacked(aliceNewLeaf, bobLeaf));
            aliceNewProof[0] = bobLeaf;
        } else {
            newRoot = keccak256(abi.encodePacked(bobLeaf, aliceNewLeaf));
            aliceNewProof[0] = bobLeaf;
        }

        // Update root
        vm.prank(updater);
        distributor.submitRoot(newRoot, bytes32(0));

        vm.warp(block.timestamp + INITIAL_TIMELOCK);
        distributor.acceptRoot();

        // Alice can now purchase from the increased allocation
        vm.startPrank(alice);
        uint256 additionalPurchase = 700 * 10 ** 18; // More than original allocation allows
        distributor.claimPurchase(aliceNewAvailable, aliceNewProof, additionalPurchase, address(paymentToken), false);

        assertEq(distributor.assigned(alice), aliceNewAvailable);
        assertEq(distributor.purchased(alice), firstPurchase + additionalPurchase);
        vm.stopPrank();
    }

    function test_WithdrawTokens() public {
        // First make a purchase to get payment tokens in the contract

        vm.startPrank(alice);
        paymentToken.approve(address(distributor), type(uint256).max);
        distributor.claimPurchase(aliceAvailable, aliceProof, aliceAvailable, address(paymentToken), false);
        vm.stopPrank();

        uint256 contractBalance = paymentToken.balanceOf(address(distributor));
        assertGt(contractBalance, 0);

        // Withdraw as owner
        address recipient = address(0x999);
        uint256 recipientBefore = paymentToken.balanceOf(recipient);

        vm.expectEmit(true, true, false, true);
        emit RewardEventsLib.PaymentTokenWithdrawn(address(paymentToken), recipient, contractBalance);

        vm.prank(owner);
        distributor.withdrawTokens(address(paymentToken), recipient, contractBalance);

        assertEq(paymentToken.balanceOf(recipient), recipientBefore + contractBalance);
        assertEq(paymentToken.balanceOf(address(distributor)), 0);
    }

    function test_OracleFailure() public {
        // Set oracle price to 0
        paymentOracle.setPrice(0);

        vm.startPrank(alice);
        paymentToken.approve(address(distributor), type(uint256).max);

        vm.expectRevert(RewardErrorsLib.InvalidOraclePrice.selector);
        distributor.claimPurchase(aliceAvailable, aliceProof, aliceAvailable, address(paymentToken), false);
        vm.stopPrank();
    }

    function test_SubmitRoot_WithoutExpiry() public {
        bytes32 newRoot = bytes32(uint256(1));
        bytes32 newIpfsHash = bytes32(uint256(2));

        vm.expectEmit(true, true, false, true);
        emit RewardEventsLib.PendingRootSet(updater, newRoot, newIpfsHash);

        vm.prank(updater);
        distributor.submitRoot(newRoot, newIpfsHash);

        PendingRoot memory pending = distributor.pendingRoot();
        assertEq(pending.root, newRoot);
        assertEq(pending.ipfsHash, newIpfsHash);
        assertEq(pending.validAt, block.timestamp + INITIAL_TIMELOCK);
    }

    function test_Pause_BlocksClaims() public {
        // Pause the contract
        vm.prank(distributor.owner());
        distributor.setPauser(bob, CLAIM_PAUSE_TYPE, true);

        vm.prank(bob);
        distributor.pause(CLAIM_PAUSE_TYPE, true);

        assertEq(distributor.paused(CLAIM_PAUSE_TYPE), true);

        // Try to purchase while paused - should fail
        vm.startPrank(alice);
        paymentToken.approve(address(distributor), type(uint256).max);

        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, CLAIM_PAUSE_TYPE));
        distributor.claimPurchase(aliceAvailable, aliceProof, aliceAvailable, address(paymentToken), false);
        vm.stopPrank();

        // Unpause and try again - should work
        vm.prank(bob);
        distributor.pause(CLAIM_PAUSE_TYPE, false);

        assertEq(distributor.paused(CLAIM_PAUSE_TYPE), false);

        vm.startPrank(alice);
        uint256 purchased =
            distributor.claimPurchase(aliceAvailable, aliceProof, aliceAvailable, address(paymentToken), false);
        assertEq(purchased, aliceAvailable);
        vm.stopPrank();
    }

    function testFuzz_ClaimPurchase_VariousPurchaseAmounts(uint256 purchaseAmount, uint256 aliceClaim) public {
        aliceClaim = bound(aliceClaim, 0.01e18, 100_000_000e18);
        purchaseAmount = bound(purchaseAmount, 0.01e18, aliceClaim);

        (bytes32 root, bytes32[] memory aliceLeafProof,) = _setupMerkleTree(aliceClaim, 100e18);
        paymentToken.mint(alice, purchaseAmount);
        rewardToken.mint(address(distributor), aliceClaim);

        vm.prank(owner);
        distributor.submitRoot(root, bytes32(0));

        vm.warp(block.timestamp + INITIAL_TIMELOCK);
        distributor.acceptRoot();

        vm.startPrank(alice);
        paymentToken.approve(address(distributor), type(uint256).max);

        uint256 alicePaymentBefore = paymentToken.balanceOf(alice);
        uint256 aliceRewardBefore = rewardToken.balanceOf(alice);

        // Calculate expected payment
        uint256 baseCostUSD = (purchaseAmount * REWARD_PRICE + 10 ** 18 - 1) / 10 ** 18; // Round up
        uint256 discountedCostUSD = baseCostUSD * (10000 - BASE_DISCOUNT) / 10000;
        uint256 expectedPayment = (discountedCostUSD * 10 ** 6 + PAYMENT_TOKEN_PRICE - 1) / PAYMENT_TOKEN_PRICE; // Round up

        // Purchase tokens
        uint256 purchased =
            distributor.claimPurchase(aliceClaim, aliceLeafProof, purchaseAmount, address(paymentToken), false);

        // Verify results
        assertEq(purchased, purchaseAmount);
        assertEq(distributor.assigned(alice), aliceClaim);
        assertEq(distributor.purchased(alice), purchaseAmount);

        // Check payment was taken (allow for rounding)
        uint256 actualPayment = alicePaymentBefore - paymentToken.balanceOf(alice);
        assertGe(actualPayment, expectedPayment - 1);
        assertLe(actualPayment, expectedPayment + 1);

        // Check rewards were received
        assertEq(rewardToken.balanceOf(alice), aliceRewardBefore + purchaseAmount);

        vm.stopPrank();
    }

    function testFuzz_ClaimPurchase_MultiplePartialPurchases(uint256[3] memory amounts) public {
        // Ensure total doesn't exceed allocation
        uint256 total;
        for (uint256 i = 0; i < 3; i++) {
            amounts[i] = bound(amounts[i], 0.01e18, aliceAvailable / 3);
            total += amounts[i];
        }

        // Ensure we don't exceed allocation
        if (total > aliceAvailable) {
            amounts[2] = aliceAvailable - amounts[0] - amounts[1];
            total = aliceAvailable;
        }

        vm.startPrank(alice);
        paymentToken.approve(address(distributor), type(uint256).max);

        uint256 totalPurchased;
        for (uint256 i = 0; i < 3; i++) {
            if (amounts[i] > 0 && totalPurchased + amounts[i] <= aliceAvailable) {
                distributor.claimPurchase(aliceAvailable, aliceProof, amounts[i], address(paymentToken), false);
                totalPurchased += amounts[i];
                assertEq(distributor.purchased(alice), totalPurchased);
            }
        }

        assertEq(distributor.assigned(alice), aliceAvailable);
        vm.stopPrank();
    }

    function testFuzz_ClaimPurchase_VariousTokenPrices(uint256 tokenPrice) public {
        // Bound token price to reasonable range (avoid overflow and ensure > 0)
        tokenPrice = bound(tokenPrice, 0.01e8, 100000e8);

        // Create new oracle with fuzzed price
        MockOracle fuzzOracle = new MockOracle(int256(tokenPrice), 8);

        // Set up new payment token with fuzzed oracle
        ERC20Mock fuzzPaymentToken = new ERC20Mock("Fuzz Token", "FUZZ", 6);
        fuzzPaymentToken.mint(alice, type(uint128).max);

        vm.prank(owner);
        distributor.setPaymentToken(address(fuzzPaymentToken), address(fuzzOracle));

        vm.startPrank(alice);
        fuzzPaymentToken.approve(address(distributor), type(uint256).max);

        uint256 purchaseAmount = aliceAvailable / 2;
        uint256 alicePaymentBefore = fuzzPaymentToken.balanceOf(alice);

        // Calculate expected payment
        uint256 baseCostUSD = (purchaseAmount * REWARD_PRICE + 10 ** 18 - 1) / 10 ** 18;
        uint256 discountedCostUSD = baseCostUSD * (10000 - BASE_DISCOUNT) / 10000;
        uint256 expectedPayment = (discountedCostUSD * 10 ** 6 + tokenPrice - 1) / tokenPrice;

        // Should not revert for valid prices
        distributor.claimPurchase(aliceAvailable, aliceProof, purchaseAmount, address(fuzzPaymentToken), false);

        uint256 actualPayment = alicePaymentBefore - fuzzPaymentToken.balanceOf(alice);

        // Verify payment is never zero for non-zero purchase
        assertGt(actualPayment, 0);

        // Verify payment is within expected range (allowing for rounding)
        assertGe(actualPayment, expectedPayment - 1);
        assertLe(actualPayment, expectedPayment + 1);

        vm.stopPrank();
    }

    function testFuzz_ClaimPurchase_VariousDiscounts(uint256 discount, uint256 lockDiscount, bool shouldLock) public {
        // Bound discounts to valid range (0-100%)
        vm.assume(discount <= 10000 && lockDiscount <= 10000);
        discount = bound(discount, 1, 10000);
        lockDiscount = bound(lockDiscount, discount + 1, 10000);

        // Set new discounts
        vm.startPrank(owner);
        distributor.setDiscount(discount);
        distributor.setLockBonusDiscount(lockDiscount);
        vm.stopPrank();

        vm.startPrank(alice);
        paymentToken.approve(address(distributor), type(uint256).max);

        uint256 purchaseAmount = aliceAvailable / 2;
        uint256 alicePaymentBefore = paymentToken.balanceOf(alice);

        // Calculate expected payment with appropriate discount
        uint256 appliedDiscount = shouldLock ? lockDiscount : discount;
        uint256 baseCostUSD = (purchaseAmount * REWARD_PRICE + 10 ** 18 - 1) / 10 ** 18;
        uint256 discountedCostUSD = baseCostUSD * (10000 - appliedDiscount) / 10000;
        uint256 expectedPayment = (discountedCostUSD * 10 ** 6 + PAYMENT_TOKEN_PRICE - 1) / PAYMENT_TOKEN_PRICE;

        distributor.claimPurchase(aliceAvailable, aliceProof, purchaseAmount, address(paymentToken), shouldLock);

        uint256 actualPayment = alicePaymentBefore - paymentToken.balanceOf(alice);

        // For 100% discount, payment should be minimal (rounding up ensures at least 1)
        if (appliedDiscount == 10000) {
            assertLe(actualPayment, 1);
        } else {
            assertGe(actualPayment, expectedPayment - 1);
            assertLe(actualPayment, expectedPayment + 1);
        }

        vm.stopPrank();
    }

    function testFuzz_ClaimPurchase_VariousDecimals(uint8 paymentDecimals, uint8 rewardDecimals) public {
        // Bound decimals to reasonable range
        paymentDecimals = uint8(bound(paymentDecimals, 0, 18));
        rewardDecimals = uint8(bound(rewardDecimals, 6, 18));

        // Create tokens with fuzzed decimals
        ERC20Mock fuzzRewardToken = new ERC20Mock("Fuzz Reward", "FRWD", rewardDecimals);
        ERC20Mock fuzzPaymentToken = new ERC20Mock("Fuzz Payment", "FPAY", paymentDecimals);

        // Create new distributor with fuzzed reward token
        RewardsDistributor fuzzDistributor =
            new RewardsDistributor(owner, INITIAL_TIMELOCK, testRoot, INITIAL_IPFS_HASH, address(fuzzRewardToken));

        // Setup
        MockOracle fuzzOracle = new MockOracle(int256(1 * 10 ** 8), 8); // $1

        vm.startPrank(owner);
        fuzzDistributor.setRootUpdater(updater, true);
        fuzzDistributor.setPaymentToken(address(fuzzPaymentToken), address(fuzzOracle));
        fuzzDistributor.setRewardPrice(100 * 10 ** 8); // $100
        fuzzDistributor.setDiscount(1000); // 10%
        vm.stopPrank();

        // Fund
        uint256 scaledAllocation = 1000 * 10 ** rewardDecimals;
        fuzzRewardToken.mint(address(fuzzDistributor), scaledAllocation * 10);
        fuzzPaymentToken.mint(alice, type(uint128).max);

        // Create new merkle tree for fuzzed allocation
        bytes32 aliceFuzzLeaf = keccak256(bytes.concat(keccak256(abi.encode(alice, scaledAllocation))));
        bytes32 bobFuzzLeaf = keccak256(bytes.concat(keccak256(abi.encode(bob, scaledAllocation))));

        bytes32 fuzzRoot;
        bytes32[] memory fuzzProof = new bytes32[](1);

        if (uint256(aliceFuzzLeaf) < uint256(bobFuzzLeaf)) {
            fuzzRoot = keccak256(abi.encodePacked(aliceFuzzLeaf, bobFuzzLeaf));
            fuzzProof[0] = bobFuzzLeaf;
        } else {
            fuzzRoot = keccak256(abi.encodePacked(bobFuzzLeaf, aliceFuzzLeaf));
            fuzzProof[0] = bobFuzzLeaf;
        }

        // Update root
        vm.prank(updater);
        fuzzDistributor.submitRoot(fuzzRoot, bytes32(0));
        vm.warp(block.timestamp + INITIAL_TIMELOCK);
        fuzzDistributor.acceptRoot();

        // Test claim
        vm.startPrank(alice);
        fuzzPaymentToken.approve(address(fuzzDistributor), type(uint256).max);

        uint256 purchaseAmount = scaledAllocation / 2;

        // Should not revert for any valid decimal combination
        fuzzDistributor.claimPurchase(scaledAllocation, fuzzProof, purchaseAmount, address(fuzzPaymentToken), false);

        assertEq(fuzzDistributor.purchased(alice), purchaseAmount);
        assertEq(fuzzRewardToken.balanceOf(alice), purchaseAmount);

        vm.stopPrank();
    }
}
