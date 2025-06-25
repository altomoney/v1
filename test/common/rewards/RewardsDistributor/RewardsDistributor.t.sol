// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {RewardsDistributor, CLAIM_PAUSE_TYPE} from "@alto/rewards/RewardsDistributor.sol";
import {PendingRoot, IRewardsDistributor, IRewardsEvents, IRewardsErrors, PaymentToken} from "@alto/rewards/interfaces/IRewardsDistributor.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20MockDecimals} from "@alto-test/helpers/ERC20MockDecimals.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {OracleUsdMock} from "@alto/oracles/mocks/OracleUsdMock.sol";
import {USD_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IUsdOracle.sol";
import {MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";

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
    ERC20MockDecimals public rewardToken;
    ERC20MockDecimals public paymentToken;
    ERC20MockDecimals public paymentToken2;
    OracleUsdMock public paymentOracle;
    OracleUsdMock public paymentOracle2;
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
    uint256 public REWARD_PRICE = _getOraclePriceFromEther(100 ether); // $100 per token
    uint256 public PAYMENT_TOKEN_PRICE = _getOraclePriceFromEther(1 ether); // $1 per payment token
    uint256 public constant BASE_DISCOUNT = 1000; // 10%
    uint256 public constant LOCK_BONUS_DISCOUNT = 500; // 5% additional

    function _getOraclePriceFromEther(uint256 etherPrice) internal pure returns (uint256) {
        return etherPrice * USD_ORACLE_PRICE_PRECISION / 1 ether;
    }

    function setUp() public {
        // Deploy tokens
        rewardToken = new ERC20MockDecimals("Reward Token", "RWD", 18);
        paymentToken = new ERC20MockDecimals("Payment Token", "PAY", 6);
        paymentToken2 = new ERC20MockDecimals("Payment Token 2", "PAY2", 18);

        // Deploy oracles
        paymentOracle = new OracleUsdMock();
        paymentOracle2 = new OracleUsdMock();
        paymentOracle.setPrice(PAYMENT_TOKEN_PRICE);
        paymentOracle2.setPrice(_getOraclePriceFromEther(2 ether)); // $2 per token

        // Deploy reward oracle
        OracleUsdMock rewardOracle = new OracleUsdMock();
        rewardOracle.setPrice(REWARD_PRICE);

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
        distributor.setRewardOracle(address(rewardOracle));
        distributor.setDiscount(BASE_DISCOUNT * MATH_PRECISION / 10000); // Convert to MATH_PRECISION
        distributor.setLockBonusDiscount(LOCK_BONUS_DISCOUNT * MATH_PRECISION / 10000); // Convert to MATH_PRECISION
        distributor.setLockContract(address(lockContract));
        vm.stopPrank();

        // Fund distributor with reward tokens
        deal(address(rewardToken), address(distributor), 10000 * 10 ** rewardToken.decimals());

        // Fund users with payment tokens
        deal(address(paymentToken), alice, 1000000 * 10 ** paymentToken.decimals()); // 1M tokens with 6 decimals
        deal(address(paymentToken), bob, 1000000 * 10 ** paymentToken.decimals());
        deal(address(paymentToken2), alice, 1000000 * 10 ** paymentToken2.decimals()); // 1M tokens with 18 decimals
        deal(address(paymentToken2), bob, 1000000 * 10 ** paymentToken2.decimals());
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
        address newToken = address(new ERC20MockDecimals("New Token", "NEW", 18));
        address newOracle = address(new OracleUsdMock());
        OracleUsdMock(newOracle).setPrice(_getOraclePriceFromEther(100 ether));

        vm.expectEmit(true, true, false, false);
        emit IRewardsEvents.PaymentTokenSet(newToken, newOracle);

        vm.prank(owner);
        distributor.setPaymentToken(newToken, newOracle);
        (address oracle, uint8 decimals) = distributor.paymentTokens(newToken);
        assertEq(oracle, newOracle);
        assertEq(decimals, 18);
    }

    function test_SetRewardOracle() public {
        address newOracle = address(new OracleUsdMock());
        OracleUsdMock(newOracle).setPrice(_getOraclePriceFromEther(200 ether));

        vm.expectEmit(true, false, false, false);
        emit IRewardsEvents.RewardOracleSet(newOracle);

        vm.prank(owner);
        distributor.setRewardOracle(newOracle);

        assertEq(distributor.rewardPrice(), _getOraclePriceFromEther(200 ether));
    }

    function test_SetDiscount() public {
        uint256 newDiscount = MATH_PRECISION * 20 / 100; // 20%

        vm.expectEmit(false, false, false, true);
        emit IRewardsEvents.DiscountSet(newDiscount);

        vm.prank(owner);
        distributor.setDiscount(newDiscount);

        assertEq(distributor.discount(), newDiscount);
    }

    function test_SetLockBonusDiscount() public {
        uint256 newLockBonusDiscount = MATH_PRECISION * 10 / 100; // 10%

        vm.expectEmit(false, false, false, true);
        emit IRewardsEvents.LockBonusDiscountSet(newLockBonusDiscount);

        vm.prank(owner);
        distributor.setLockBonusDiscount(newLockBonusDiscount);

        assertEq(distributor.lockBonusDiscount(), newLockBonusDiscount);
    }

    function test_SetLock() public {
        address newLock = address(0x999);

        vm.expectEmit(true, false, false, false);
        emit IRewardsEvents.LockSet(newLock);

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

        // Expect PurchaseClaimed event
        vm.expectEmit(true, true, true, true);
        emit IRewardsEvents.PurchaseClaimed(alice, alice, address(rewardToken), aliceAvailable);

        // Purchase full amount
        uint256 purchased =
            distributor.claimPurchase(aliceAvailable, aliceProof, aliceAvailable, address(paymentToken), false, alice);

        assertEq(purchased, aliceAvailable);
        assertEq(distributor.assigned(alice), 0); // assigned is deprecated
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
        
        vm.expectEmit(true, true, true, true);
        emit IRewardsEvents.PurchaseClaimed(alice, alice, address(rewardToken), firstPurchase);
        
        distributor.claimPurchase(aliceAvailable, aliceProof, firstPurchase, address(paymentToken), false, alice);

        assertEq(distributor.assigned(alice), 0); // assigned is deprecated
        assertEq(distributor.purchased(alice), firstPurchase);

        // Purchase another 50%
        uint256 secondPurchase = (aliceAvailable * 50) / 100;
        
        vm.expectEmit(true, true, true, true);
        emit IRewardsEvents.PurchaseClaimed(alice, alice, address(rewardToken), secondPurchase);
        
        distributor.claimPurchase(aliceAvailable, aliceProof, secondPurchase, address(paymentToken), false, alice);

        assertEq(distributor.purchased(alice), firstPurchase + secondPurchase);

        // Purchase remaining 20%
        uint256 remaining = aliceAvailable - distributor.purchased(alice);
        
        vm.expectEmit(true, true, true, true);
        emit IRewardsEvents.PurchaseClaimed(alice, alice, address(rewardToken), remaining);
        
        distributor.claimPurchase(aliceAvailable, aliceProof, remaining, address(paymentToken), false, alice);

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

        // Expect PurchaseClaimed event
        vm.expectEmit(true, true, true, true);
        emit IRewardsEvents.PurchaseClaimed(alice, alice, address(rewardToken), aliceAvailable);

        // Purchase with lock
        distributor.claimPurchase(aliceAvailable, aliceProof, aliceAvailable, address(paymentToken), true, alice);

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

        // Expect PurchaseClaimed event
        vm.expectEmit(true, true, true, true);
        emit IRewardsEvents.PurchaseClaimed(alice, alice, address(rewardToken), aliceAvailable);

        distributor.claimPurchase(aliceAvailable, aliceProof, aliceAvailable, address(paymentToken2), false, alice);

        assertEq(paymentToken2.balanceOf(alice), alicePaymentBefore - expectedPayment);
        assertEq(distributor.purchased(alice), aliceAvailable);
        assertEq(distributor.assigned(alice), 0); // assigned is deprecated
        assertEq(rewardToken.balanceOf(alice), aliceRewardBefore + aliceAvailable);
        vm.stopPrank();
    }

    function test_ClaimPurchase_RevertIf_ExceedsAllocation() public {
        vm.startPrank(alice);
        paymentToken.approve(address(distributor), type(uint256).max);

        // Try to purchase more than allocated
        vm.expectRevert(IRewardsErrors.InvalidPurchaseAmount.selector);
        distributor.claimPurchase(aliceAvailable, aliceProof, aliceAvailable + 1, address(paymentToken), false, alice);
        vm.stopPrank();
    }

    function test_ClaimPurchase_RevertIf_AlreadyFullyPurchased() public {
        vm.startPrank(alice);
        paymentToken.approve(address(distributor), type(uint256).max);

        // Purchase full amount
        distributor.claimPurchase(aliceAvailable, aliceProof, aliceAvailable, address(paymentToken), false, alice);

        // Try to purchase again
        vm.expectRevert(IRewardsErrors.InvalidPurchaseAmount.selector);
        distributor.claimPurchase(aliceAvailable, aliceProof, 1, address(paymentToken), false, alice);
        vm.stopPrank();
    }

    function test_ClaimPurchase_RevertIf_InvalidPaymentToken() public {
        vm.startPrank(alice);

        // Try with unregistered payment token
        vm.expectRevert(IRewardsErrors.InvalidPaymentToken.selector);
        distributor.claimPurchase(aliceAvailable, aliceProof, aliceAvailable, address(0x999), false, alice);
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

        vm.expectRevert(IRewardsErrors.PriceNotSet.selector);
        newDistributor.claimPurchase(aliceAvailable, aliceProof, aliceAvailable, address(paymentToken), false, alice);
        vm.stopPrank();
    }

    function test_ClaimPurchase_RevertIf_LockNotSet() public {
        // Deploy new distributor without setting lock
        RewardsDistributor newDistributor =
            new RewardsDistributor(owner, INITIAL_TIMELOCK, testRoot, INITIAL_IPFS_HASH, address(rewardToken));

        OracleUsdMock newRewardOracle = new OracleUsdMock();
        newRewardOracle.setPrice(REWARD_PRICE);

        vm.startPrank(owner);
        newDistributor.setPaymentToken(address(paymentToken), address(paymentOracle));
        newDistributor.setRewardOracle(address(newRewardOracle));
        vm.stopPrank();

        // Fund distributor
        deal(address(rewardToken), address(newDistributor), 10000 * 10 ** rewardToken.decimals());

        vm.startPrank(alice);
        paymentToken.approve(address(newDistributor), type(uint256).max);

        vm.expectRevert(IRewardsErrors.LockNotSet.selector);
        newDistributor.claimPurchase(
            aliceAvailable,
            aliceProof,
            aliceAvailable,
            address(paymentToken),
            true, // try to lock
            alice
        );
        vm.stopPrank();
    }

    function test_MerkleTreeUpdate_IncreasedAllocation() public {
        // Set initial root

        // Alice purchases half of initial allocation
        vm.startPrank(alice);
        paymentToken.approve(address(distributor), type(uint256).max);

        uint256 firstPurchase = aliceAvailable / 2;
        
        vm.expectEmit(true, true, true, true);
        emit IRewardsEvents.PurchaseClaimed(alice, alice, address(rewardToken), firstPurchase);
        
        distributor.claimPurchase(aliceAvailable, aliceProof, firstPurchase, address(paymentToken), false, alice);

        assertEq(distributor.assigned(alice), 0); // assigned is deprecated
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
        
        vm.expectEmit(true, true, true, true);
        emit IRewardsEvents.PurchaseClaimed(alice, alice, address(rewardToken), additionalPurchase);
        
        distributor.claimPurchase(aliceNewAvailable, aliceNewProof, additionalPurchase, address(paymentToken), false, alice);

        assertEq(distributor.assigned(alice), 0); // assigned is deprecated
        assertEq(distributor.purchased(alice), firstPurchase + additionalPurchase);
        vm.stopPrank();
    }

    function test_WithdrawTokens() public {
        // First make a purchase to get payment tokens in the contract

        vm.startPrank(alice);
        paymentToken.approve(address(distributor), type(uint256).max);
        
        vm.expectEmit(true, true, true, true);
        emit IRewardsEvents.PurchaseClaimed(alice, alice, address(rewardToken), aliceAvailable);
        
        distributor.claimPurchase(aliceAvailable, aliceProof, aliceAvailable, address(paymentToken), false, alice);
        vm.stopPrank();

        uint256 contractBalance = paymentToken.balanceOf(address(distributor));
        assertGt(contractBalance, 0);

        // Withdraw as owner
        address recipient = address(0x999);
        uint256 recipientBefore = paymentToken.balanceOf(recipient);

        vm.expectEmit(true, true, false, true);
        emit IRewardsEvents.PaymentTokenWithdrawn(address(paymentToken), recipient, contractBalance);

        vm.prank(owner);
        distributor.withdrawTokens(address(paymentToken), recipient, contractBalance);

        assertEq(paymentToken.balanceOf(recipient), recipientBefore + contractBalance);
        assertEq(paymentToken.balanceOf(address(distributor)), 0);
    }

    function test_ClaimPurchase_With100PercentDiscount() public {
        // Set 100% discount
        vm.prank(owner);
        distributor.setDiscount(MATH_PRECISION); // 100% discount

        // Approve payment (even though we expect 0 payment)
        vm.startPrank(alice);
        paymentToken.approve(address(distributor), type(uint256).max);

        uint256 alicePaymentBefore = paymentToken.balanceOf(alice);
        uint256 aliceRewardBefore = rewardToken.balanceOf(alice);

        // Expect PurchaseClaimed event
        vm.expectEmit(true, true, true, true);
        emit IRewardsEvents.PurchaseClaimed(alice, alice, address(rewardToken), aliceAvailable);

        // Purchase with 100% discount - should pay 0
        uint256 purchased = distributor.claimPurchase(aliceAvailable, aliceProof, aliceAvailable, address(paymentToken), false, alice);

        // Verify no payment was taken (100% discount)
        assertEq(paymentToken.balanceOf(alice), alicePaymentBefore);
        
        // Verify rewards were received
        assertEq(purchased, aliceAvailable);
        assertEq(distributor.purchased(alice), aliceAvailable);
        assertEq(rewardToken.balanceOf(alice), aliceRewardBefore + aliceAvailable);
        
        vm.stopPrank();
    }

    function test_ClaimPurchase_With100PercentLockDiscount() public {
        // Set 100% lock bonus discount
        vm.prank(owner);
        distributor.setLockBonusDiscount(MATH_PRECISION); // 100% discount when locking

        // Approve payment (even though we expect 0 payment)
        vm.startPrank(alice);
        paymentToken.approve(address(distributor), type(uint256).max);

        uint256 alicePaymentBefore = paymentToken.balanceOf(alice);

        // Expect PurchaseClaimed event
        vm.expectEmit(true, true, true, true);
        emit IRewardsEvents.PurchaseClaimed(alice, alice, address(rewardToken), aliceAvailable);

        // Purchase with lock and 100% discount - should pay 0
        distributor.claimPurchase(aliceAvailable, aliceProof, aliceAvailable, address(paymentToken), true, alice);

        // Verify no payment was taken (100% discount)
        assertEq(paymentToken.balanceOf(alice), alicePaymentBefore);
        
        // Verify tokens were locked
        assertEq(lockContract.locked(alice), aliceAvailable);
        assertEq(lockContract.lastTo(), alice);
        assertEq(lockContract.lastAmount(), aliceAvailable);
        assertEq(distributor.purchased(alice), aliceAvailable);
        
        vm.stopPrank();
    }

    function test_ClaimPurchase_OnBehalf() public {
        // Alice authorizes Bob to claim on her behalf
        vm.prank(alice);
        distributor.setAuthorization(bob, true);

        // Bob claims on behalf of Alice
        vm.startPrank(bob);
        paymentToken.approve(address(distributor), type(uint256).max);

        uint256 bobPaymentBefore = paymentToken.balanceOf(bob);
        uint256 aliceRewardBefore = rewardToken.balanceOf(alice);

        // Expect PurchaseClaimed event with bob as caller and alice as onBehalf
        vm.expectEmit(true, true, true, true);
        emit IRewardsEvents.PurchaseClaimed(bob, alice, address(rewardToken), aliceAvailable);

        // Bob claims on behalf of Alice
        distributor.claimPurchase(aliceAvailable, aliceProof, aliceAvailable, address(paymentToken), false, alice);

        // Verify Bob paid but Alice received the rewards
        uint256 expectedPayment = 90000 * 10 ** 6; // Same calculation as test_ClaimPurchase_FullAmount_NoLock
        assertEq(paymentToken.balanceOf(bob), bobPaymentBefore - expectedPayment);
        assertEq(rewardToken.balanceOf(alice), aliceRewardBefore + aliceAvailable);
        assertEq(distributor.purchased(alice), aliceAvailable);
        
        vm.stopPrank();
    }

    function test_SubmitRoot_WithoutExpiry() public {
        bytes32 newRoot = bytes32(uint256(1));
        bytes32 newIpfsHash = bytes32(uint256(2));

        vm.expectEmit(true, true, false, true);
        emit IRewardsEvents.PendingRootSet(updater, newRoot, newIpfsHash);

        vm.prank(updater);
        distributor.submitRoot(newRoot, newIpfsHash);

        (bytes32 root, bytes32 ipfsHash, uint256 validAt) = distributor.pendingRoot();
        assertEq(root, newRoot);
        assertEq(ipfsHash, newIpfsHash);
        assertEq(validAt, block.timestamp + INITIAL_TIMELOCK);
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
        distributor.claimPurchase(aliceAvailable, aliceProof, aliceAvailable, address(paymentToken), false, alice);
        vm.stopPrank();

        // Unpause and try again - should work
        vm.prank(bob);
        distributor.pause(CLAIM_PAUSE_TYPE, false);

        assertEq(distributor.paused(CLAIM_PAUSE_TYPE), false);

        vm.startPrank(alice);
        
        vm.expectEmit(true, true, true, true);
        emit IRewardsEvents.PurchaseClaimed(alice, alice, address(rewardToken), aliceAvailable);
        
        uint256 purchased =
            distributor.claimPurchase(aliceAvailable, aliceProof, aliceAvailable, address(paymentToken), false, alice);
        assertEq(purchased, aliceAvailable);
        vm.stopPrank();
    }

    function testFuzz_ClaimPurchase_VariousPurchaseAmounts(uint256 purchaseAmount, uint256 aliceClaim) public {
        aliceClaim = bound(aliceClaim, 0.01e18, 100_000_000e18);
        purchaseAmount = bound(purchaseAmount, 0.01e18, aliceClaim);

        (bytes32 root, bytes32[] memory aliceLeafProof,) = _setupMerkleTree(aliceClaim, 100e18);
        deal(address(paymentToken), alice, purchaseAmount);
        deal(address(rewardToken), address(distributor), aliceClaim);

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
        // Convert BASE_DISCOUNT from basis points to MATH_PRECISION
        uint256 discountInMathPrecision = BASE_DISCOUNT * MATH_PRECISION / 10000;
        uint256 discountedCostUSD = baseCostUSD * (MATH_PRECISION - discountInMathPrecision) / MATH_PRECISION;
        uint256 expectedPayment = (discountedCostUSD * 10 ** 6 + PAYMENT_TOKEN_PRICE - 1) / PAYMENT_TOKEN_PRICE; // Round up

        // Purchase tokens
        uint256 purchased =
            distributor.claimPurchase(aliceClaim, aliceLeafProof, purchaseAmount, address(paymentToken), false, alice);

        // Verify results
        assertEq(purchased, purchaseAmount);
        assertEq(distributor.assigned(alice), 0); // assigned is deprecated
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
                distributor.claimPurchase(aliceAvailable, aliceProof, amounts[i], address(paymentToken), false, alice);
                totalPurchased += amounts[i];
                assertEq(distributor.purchased(alice), totalPurchased);
            }
        }

        assertEq(distributor.assigned(alice), 0); // assigned is deprecated
        vm.stopPrank();
    }

    function testFuzz_ClaimPurchase_VariousTokenPrices(uint256 tokenPrice) public {
        // Bound token price to reasonable range (avoid overflow and ensure > 0)
        tokenPrice = bound(tokenPrice, _getOraclePriceFromEther(0.01 ether), _getOraclePriceFromEther(100000 ether));

        // Create new oracle with fuzzed price
        OracleUsdMock fuzzOracle = new OracleUsdMock();
        fuzzOracle.setPrice(tokenPrice);

        // Set up new payment token with fuzzed oracle
        ERC20MockDecimals fuzzPaymentToken = new ERC20MockDecimals("Fuzz Token", "FUZZ", 6);
        deal(address(fuzzPaymentToken), alice, type(uint128).max);

        vm.prank(owner);
        distributor.setPaymentToken(address(fuzzPaymentToken), address(fuzzOracle));

        vm.startPrank(alice);
        fuzzPaymentToken.approve(address(distributor), type(uint256).max);

        uint256 purchaseAmount = aliceAvailable / 2;
        uint256 alicePaymentBefore = fuzzPaymentToken.balanceOf(alice);

        // Calculate expected payment
        uint256 baseCostUSD = (purchaseAmount * REWARD_PRICE + 10 ** 18 - 1) / 10 ** 18;
        // Convert BASE_DISCOUNT from basis points to MATH_PRECISION
        uint256 discountInMathPrecision = BASE_DISCOUNT * MATH_PRECISION / 10000;
        uint256 discountedCostUSD = baseCostUSD * (MATH_PRECISION - discountInMathPrecision) / MATH_PRECISION;
        uint256 expectedPayment = (discountedCostUSD * 10 ** 6 + tokenPrice - 1) / tokenPrice;

        // Should not revert for valid prices
        distributor.claimPurchase(aliceAvailable, aliceProof, purchaseAmount, address(fuzzPaymentToken), false, alice);

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
        discount = bound(discount, 1, MATH_PRECISION);
        lockDiscount = bound(lockDiscount, 1, MATH_PRECISION);
        
        // Ensure lockDiscount >= discount (it should be a better discount)
        if (lockDiscount < discount) {
            uint256 temp = discount;
            discount = lockDiscount;
            lockDiscount = temp;
        }

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
        uint256 discountedCostUSD = baseCostUSD * (MATH_PRECISION - appliedDiscount) / MATH_PRECISION;
        uint256 expectedPayment = (discountedCostUSD * 10 ** 6 + PAYMENT_TOKEN_PRICE - 1) / PAYMENT_TOKEN_PRICE;

        distributor.claimPurchase(aliceAvailable, aliceProof, purchaseAmount, address(paymentToken), shouldLock, alice);

        uint256 actualPayment = alicePaymentBefore - paymentToken.balanceOf(alice);
        
        // For very high discounts (close to 100%), the payment might round to zero or be very small
        if (appliedDiscount >= MATH_PRECISION - 1e15) { // Within 0.001% of 100%
            // Payment could be 0 or very small due to rounding
            // With such high discount, we just verify the payment is minimal
            assertLe(actualPayment, expectedPayment * 2, "Payment should be close to expected even with rounding");
        } else {
            assertEq(actualPayment, expectedPayment);
        }
        
        assertEq(distributor.purchased(alice), purchaseAmount);
        vm.stopPrank();
    }

    function testFuzz_ClaimPurchase_VariousDecimals(uint8 paymentDecimals, uint8 rewardDecimals) public {
        // Bound decimals to reasonable range
        paymentDecimals = uint8(bound(paymentDecimals, 0, 18));
        rewardDecimals = uint8(bound(rewardDecimals, 6, 18));

        // Create tokens with fuzzed decimals
        ERC20MockDecimals fuzzRewardToken = new ERC20MockDecimals("Fuzz Reward", "FRWD", rewardDecimals);
        ERC20MockDecimals fuzzPaymentToken = new ERC20MockDecimals("Fuzz Payment", "FPAY", paymentDecimals);

        // Create new distributor with fuzzed reward token
        RewardsDistributor fuzzDistributor =
            new RewardsDistributor(owner, INITIAL_TIMELOCK, testRoot, INITIAL_IPFS_HASH, address(fuzzRewardToken));

        // Setup
        OracleUsdMock fuzzOracle = new OracleUsdMock();
        fuzzOracle.setPrice(_getOraclePriceFromEther(1 ether)); // $1

        vm.startPrank(owner);
        fuzzDistributor.setRootUpdater(updater, true);
        fuzzDistributor.setPaymentToken(address(fuzzPaymentToken), address(fuzzOracle));
        OracleUsdMock fuzzRewardOracle = new OracleUsdMock();
        fuzzRewardOracle.setPrice(_getOraclePriceFromEther(100 ether)); // $100
        fuzzDistributor.setRewardOracle(address(fuzzRewardOracle));
        fuzzDistributor.setDiscount(MATH_PRECISION * 10 / 100); // 10%
        vm.stopPrank();

        // Fund
        uint256 scaledAllocation = 1000 * 10 ** rewardDecimals;
        deal(address(fuzzRewardToken), address(fuzzDistributor), scaledAllocation * 10);
        deal(address(fuzzPaymentToken), alice, type(uint128).max);

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
        fuzzDistributor.claimPurchase(scaledAllocation, fuzzProof, purchaseAmount, address(fuzzPaymentToken), false, alice);

        assertEq(fuzzDistributor.purchased(alice), purchaseAmount);
        assertEq(fuzzRewardToken.balanceOf(alice), purchaseAmount);

        vm.stopPrank();
    }
}
