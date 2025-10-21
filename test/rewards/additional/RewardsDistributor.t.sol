// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {AltoRewardsDistributor} from "@alto/rewards/AltoRewardsDistributor.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {IRewardsEvents, IRewardsErrors} from "@alto/rewards/interfaces/IRewardsDistributor.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20MockDecimals} from "@alto-test/helpers/ERC20MockDecimals.sol";
import {USD_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IUsdOracle.sol";
import {MATH_PRECISION, FixedPointMath} from "@alto/utils/FixedPointMath.sol";
import {OracleMock} from "@alto/oracles/mocks/OracleMock.sol";
import {IOracle} from "@alto/oracles/interfaces/IOracle.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {IMerkleRootManagerEvents} from "@alto/utils/interfaces/IMerkleRootManager.sol";

contract MockLock {
    mapping(address => uint256) public locked;
    address public lastTo;
    uint256 public lastAmount;
    IERC20 public rewardToken;
    uint256 public lastContainerId;
    bool public lastIsReuse;
    uint256 public lastMaxEpochsToLockFor;

    uint256 public maxMultiplierStakingContainerId = 1;

    constructor(address _rewardToken) {
        rewardToken = IERC20(_rewardToken);
    }

    function lock(address onBehalf, uint256 amount, uint256 containerId, bool isReuse, uint256 maxEpochsToLockFor)
        external
        returns (uint256)
    {
        locked[onBehalf] += amount;
        lastTo = onBehalf;
        lastAmount = amount;
        lastContainerId = containerId;
        lastIsReuse = isReuse;
        lastMaxEpochsToLockFor = maxEpochsToLockFor;
        // Pull tokens from caller (RewardsDistributor)
        /// forge-lint: disable-next-line(erc20-unchecked-transfer)
        rewardToken.transferFrom(msg.sender, address(this), amount);
        return amount;
    }
}

contract RewardsDistributorTest is Test {
    using FixedPointMath for uint256;

    AltoRewardsDistributor public distributor;
    ERC20MockDecimals public rewardToken;
    ERC20MockDecimals public paymentToken;
    ERC20MockDecimals public paymentToken2;
    OracleMock public paymentOracle;
    OracleMock public paymentOracle2;
    MockLock public lockContract;

    address public owner = address(0x1);
    address public updater = address(0x2);
    address public alice = address(0x3);
    address public bob = address(0x4);

    uint256 public constant INITIAL_TIMELOCK = 1 days;

    // Test merkle tree data
    bytes32 public testRoot;
    bytes32[] public aliceProof;
    bytes32[] public bobProof;
    uint256 public aliceAvailable = 1000 ether;
    uint256 public bobAvailable = 2000 ether;

    // Pricing constants
    uint256 public REWARD_PRICE = _getOraclePriceFromEther(100 ether); // $100 per token
    uint256 public PAYMENT_TOKEN_PRICE = _getOraclePriceFromEther(1 ether); // $1 per payment token
    uint256 public constant BASE_DISCOUNT = 0.25 ether; // 25%
    uint256 public constant LOCK_DISCOUNT = 0.15 ether; // 50%

    function _getOraclePriceFromEther(uint256 etherPrice) internal pure returns (uint256) {
        return etherPrice * USD_ORACLE_PRICE_PRECISION / 1 ether;
    }

    function setUp() public {
        // Deploy tokens
        rewardToken = new ERC20MockDecimals("Reward Token", "RWD", 18);
        paymentToken = new ERC20MockDecimals("Payment Token", "PAY", 6);
        paymentToken2 = new ERC20MockDecimals("Payment Token 2", "PAY2", 18);

        // Deploy oracles
        paymentOracle = new OracleMock();
        paymentOracle2 = new OracleMock();
        paymentOracle.setPrice(PAYMENT_TOKEN_PRICE);
        paymentOracle2.setPrice(_getOraclePriceFromEther(2 ether)); // $2 per token

        // Deploy reward oracle
        OracleMock rewardOracle = new OracleMock();
        rewardOracle.setPrice(REWARD_PRICE);

        // Deploy lock contract
        lockContract = new MockLock(address(rewardToken));

        // Setup merkle tree
        _setupMerkleTree();

        // Deploy distributor
        distributor = new AltoRewardsDistributor(owner, INITIAL_TIMELOCK, address(rewardToken));

        // Setup distributor
        vm.startPrank(owner);
        distributor.setMerkleRootUpdater(updater, true);
        distributor.setPaymentToken(address(paymentToken), address(paymentOracle));
        distributor.setPaymentToken(address(paymentToken2), address(paymentOracle2));
        distributor.setRewardTokenUsdOracle(address(rewardOracle));
        distributor.setLockBonusDiscount(LOCK_DISCOUNT);
        distributor.setLockContract(address(lockContract));
        distributor.submitNewPendingRoot(testRoot, bytes32(0));
        distributor.acceptPendingRoot(testRoot);
        vm.stopPrank();

        // Fund distributor with reward tokens
        deal(address(rewardToken), address(distributor), 10000 * 10 ** rewardToken.decimals());

        // Fund users with payment tokens
        deal(address(paymentToken), alice, 1000000 * 10 ** paymentToken.decimals()); // 1M tokens with 6 decimals
        deal(address(paymentToken), bob, 1000000 * 10 ** paymentToken.decimals());
        deal(address(paymentToken2), alice, 1000000 * 10 ** paymentToken2.decimals()); // 1M tokens with 18 decimals
        deal(address(paymentToken2), bob, 1000000 * 10 ** paymentToken2.decimals());
    }

    function _getExpectedPayment(bool isAlice, uint8 paymentTokenId, bool isLockDiscount)
        internal
        view
        returns (uint256)
    {
        ERC20MockDecimals token = paymentTokenId == 0 ? paymentToken : paymentToken2;
        uint256 discount = isLockDiscount ? BASE_DISCOUNT + LOCK_DISCOUNT : BASE_DISCOUNT;
        uint256 purchaseAmount = isAlice ? aliceAvailable : bobAvailable;
        uint256 baseCostUSD = (purchaseAmount * REWARD_PRICE + 10 ** 18 - 1) / 10 ** 18;
        uint256 discountedCostUSD = baseCostUSD * (MATH_PRECISION - discount) / MATH_PRECISION;
        uint256 expectedPayment =
            (discountedCostUSD * 10 ** token.decimals() + PAYMENT_TOKEN_PRICE - 1) / PAYMENT_TOKEN_PRICE; // Round up
        return expectedPayment;
    }

    function _getExpectedPaymentWithDiscount(bool isAlice, uint8 paymentTokenId, uint256 discount)
        internal
        view
        returns (uint256)
    {
        ERC20MockDecimals token = paymentTokenId == 0 ? paymentToken : paymentToken2;
        uint256 purchaseAmount = isAlice ? aliceAvailable : bobAvailable;
        uint256 baseCostUSD = (purchaseAmount * REWARD_PRICE + 10 ** 18 - 1) / 10 ** 18;
        uint256 discountedCostUSD = baseCostUSD * (MATH_PRECISION - discount) / MATH_PRECISION;
        uint256 expectedPayment =
            (discountedCostUSD * 10 ** token.decimals() + PAYMENT_TOKEN_PRICE - 1) / PAYMENT_TOKEN_PRICE; // Round up
        return expectedPayment;
    }

    function _setupMerkleTree() internal {
        // Include BASE_DISCOUNT in leaves
        bytes32 aliceLeaf = keccak256(bytes.concat(keccak256(abi.encode(alice, aliceAvailable, BASE_DISCOUNT))));
        bytes32 bobLeaf = keccak256(bytes.concat(keccak256(abi.encode(bob, bobAvailable, BASE_DISCOUNT))));

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

    function _setupMerkleTree(uint256 aliceClaim, uint256 bobClaim)
        internal
        returns (bytes32 root, bytes32[] memory aliceProofResult, bytes32[] memory bobProofResult)
    {
        return _setupMerkleTreeWithDiscount(aliceClaim, BASE_DISCOUNT, bobClaim, BASE_DISCOUNT);
    }

    function _setupMerkleTreeWithDiscount(
        uint256 aliceClaim,
        uint256 aliceDiscount,
        uint256 bobClaim,
        uint256 bobDiscount
    ) internal returns (bytes32 root, bytes32[] memory aliceProofResult, bytes32[] memory bobProofResult) {
        bytes32 aliceLeaf = keccak256(bytes.concat(keccak256(abi.encode(alice, aliceClaim, aliceDiscount))));
        bytes32 bobLeaf = keccak256(bytes.concat(keccak256(abi.encode(bob, bobClaim, bobDiscount))));

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

        return (testRoot, aliceProof, bobProof);
    }

    function test_Constructor() public {
        assertEq(distributor.owner(), owner);
        assertEq(distributor.merkleRootTimelock(), INITIAL_TIMELOCK);
        assertEq(distributor.merkleRoot(), testRoot);
        (address token, uint8 decimals) = distributor.REWARD_TOKEN();
        assertEq(token, address(rewardToken));
        assertEq(uint256(decimals), rewardToken.decimals());
    }

    function test_SetPaymentToken() public {
        address newToken = address(new ERC20MockDecimals("New Token", "NEW", 18));
        address newOracle = address(new OracleMock());
        OracleMock(newOracle).setPrice(_getOraclePriceFromEther(100 ether));

        vm.expectEmit(true, true, false, false);
        emit IRewardsEvents.SetPaymentToken(newToken, newOracle);

        vm.prank(owner);
        distributor.setPaymentToken(newToken, newOracle);
        (address oracle, uint8 decimals) = distributor.paymentTokens(newToken);
        assertEq(oracle, newOracle);
        assertEq(decimals, 18);
    }

    function test_SetRewardOracle() public {
        address newOracle = address(new OracleMock());
        OracleMock(newOracle).setPrice(_getOraclePriceFromEther(200 ether));

        vm.expectEmit(true, false, false, false);
        emit IRewardsEvents.SetRewardTokenUsdOracle(newOracle);

        vm.prank(owner);
        distributor.setRewardTokenUsdOracle(newOracle);

        assertEq(IOracle(distributor.rewardTokenUsdOracle()).getPrice(), _getOraclePriceFromEther(200 ether));
    }

    // Removed global discount setter tests; discount is now per-user via Merkle

    function test_SetLockBonusDiscount() public {
        uint256 newLockBonusDiscount = MATH_PRECISION * 10 / 100; // 10%

        vm.expectEmit(false, false, false, true);
        emit IRewardsEvents.SetLockBonusDiscount(newLockBonusDiscount);

        vm.prank(owner);
        distributor.setLockBonusDiscount(newLockBonusDiscount);

        assertEq(distributor.lockBonusDiscount(), newLockBonusDiscount);
    }

    function test_SetLockBonusDiscount_RevertIf_InvalidInput() public {
        uint256 invalidDiscount = distributor.MAX_DISCOUNT() + 1;
        vm.expectRevert(IRewardsErrors.AltoRewardsDistributorInvalidInput.selector);
        vm.prank(owner);
        distributor.setLockBonusDiscount(invalidDiscount);
    }

    function test_SetLock() public {
        address newLock = address(0x999);

        vm.expectEmit(true, false, false, false);
        emit IRewardsEvents.SetLockContract(newLock);

        vm.prank(owner);
        distributor.setLockContract(newLock);

        assertEq(distributor.lockContract(), newLock);
    }

    function test_ClaimPurchase_FullAmount_NoLock() public {
        // Approve payment
        vm.startPrank(alice);
        paymentToken.approve(address(distributor), type(uint256).max);

        uint256 expectedPayment = _getExpectedPayment(true, 0, false);

        uint256 alicePaymentBefore = paymentToken.balanceOf(alice);
        uint256 aliceRewardBefore = rewardToken.balanceOf(alice);

        // Expect PurchaseClaimed event
        vm.expectEmit(true, true, true, true);
        emit IRewardsEvents.ClaimRewardTokens(
            alice, alice, address(paymentToken), expectedPayment, aliceAvailable, BASE_DISCOUNT
        );

        // Purchase full amount
        uint256 paymentAmountReturn = distributor.claimRewardTokens(
            aliceAvailable, aliceProof, aliceAvailable, BASE_DISCOUNT, address(paymentToken), false, 0, alice
        );

        assertEq(paymentAmountReturn, expectedPayment);
        assertEq(distributor.purchasedRewardTokenUser(alice), aliceAvailable);
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

        uint256 expectedPayment = _getExpectedPayment(true, 0, false);

        vm.expectEmit(true, true, true, true);
        emit IRewardsEvents.ClaimRewardTokens(
            alice, alice, address(paymentToken), expectedPayment * 30 / 100, firstPurchase, BASE_DISCOUNT
        );

        distributor.claimRewardTokens(
            aliceAvailable, aliceProof, firstPurchase, BASE_DISCOUNT, address(paymentToken), false, 0, alice
        );

        assertEq(distributor.purchasedRewardTokenUser(alice), firstPurchase);

        // Purchase another 50%
        uint256 secondPurchase = (aliceAvailable * 50) / 100;

        vm.expectEmit(true, true, true, true);
        emit IRewardsEvents.ClaimRewardTokens(
            alice, alice, address(paymentToken), expectedPayment * 50 / 100, secondPurchase, BASE_DISCOUNT
        );

        distributor.claimRewardTokens(
            aliceAvailable, aliceProof, secondPurchase, BASE_DISCOUNT, address(paymentToken), false, 0, alice
        );

        assertEq(distributor.purchasedRewardTokenUser(alice), firstPurchase + secondPurchase);

        // Purchase remaining 20%
        uint256 remaining = aliceAvailable - distributor.purchasedRewardTokenUser(alice);

        vm.expectEmit(true, true, true, true);
        emit IRewardsEvents.ClaimRewardTokens(
            alice, alice, address(paymentToken), expectedPayment * 20 / 100, remaining, BASE_DISCOUNT
        );

        distributor.claimRewardTokens(
            aliceAvailable, aliceProof, remaining, BASE_DISCOUNT, address(paymentToken), false, 0, alice
        );

        assertEq(distributor.purchasedRewardTokenUser(alice), aliceAvailable);
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
        uint256 expectedPayment = _getExpectedPayment(true, 0, true);

        uint256 alicePaymentBefore = paymentToken.balanceOf(alice);

        // Expect PurchaseClaimed event
        vm.expectEmit(true, true, true, true);
        emit IRewardsEvents.ClaimRewardTokens(
            alice, alice, address(paymentToken), expectedPayment, aliceAvailable, BASE_DISCOUNT + LOCK_DISCOUNT
        );

        // Purchase with lock
        distributor.claimRewardTokens(
            aliceAvailable, aliceProof, aliceAvailable, BASE_DISCOUNT, address(paymentToken), true, 1, alice
        );

        assertEq(paymentToken.balanceOf(alice), alicePaymentBefore - expectedPayment);
        assertEq(lockContract.locked(alice), aliceAvailable);
        assertEq(lockContract.lastTo(), alice);
        assertEq(lockContract.lastAmount(), aliceAvailable);
        assertEq(lockContract.lastContainerId(), 1);
        assertEq(lockContract.lastIsReuse(), false);
        assertEq(lockContract.lastMaxEpochsToLockFor(), 1);
        vm.stopPrank();
    }

    function test_ClaimPurchase_DifferentPaymentToken() public {
        // Use payment token 2 ($2 per token)
        vm.startPrank(alice);
        paymentToken2.approve(address(distributor), type(uint256).max);

        uint256 expectedPayment = _getExpectedPayment(true, 1, false) / 2;

        uint256 alicePaymentBefore = paymentToken2.balanceOf(alice);
        uint256 aliceRewardBefore = rewardToken.balanceOf(alice);

        // Expect ClaimRewardTokens event
        vm.expectEmit(true, true, true, true);
        emit IRewardsEvents.ClaimRewardTokens(
            alice, alice, address(paymentToken2), expectedPayment, aliceAvailable, BASE_DISCOUNT
        );

        distributor.claimRewardTokens(
            aliceAvailable, aliceProof, aliceAvailable, BASE_DISCOUNT, address(paymentToken2), false, 0, alice
        );

        assertEq(paymentToken2.balanceOf(alice), alicePaymentBefore - expectedPayment);
        assertEq(distributor.purchasedRewardTokenUser(alice), aliceAvailable);
        assertEq(rewardToken.balanceOf(alice), aliceRewardBefore + aliceAvailable);
        vm.stopPrank();
    }

    function test_ClaimPurchase_RevertIf_ExceedsAllocation() public {
        vm.startPrank(alice);
        paymentToken.approve(address(distributor), type(uint256).max);

        // Try to purchase more than allocated
        vm.expectRevert(IRewardsErrors.AltoRewardsDistributorInvalidInput.selector);
        distributor.claimRewardTokens(
            aliceAvailable, aliceProof, aliceAvailable + 1, BASE_DISCOUNT, address(paymentToken), false, 0, alice
        );
        vm.stopPrank();
    }

    function test_ClaimPurchase_RevertIf_AlreadyFullyPurchased() public {
        vm.startPrank(alice);
        paymentToken.approve(address(distributor), type(uint256).max);

        // Purchase full amount
        distributor.claimRewardTokens(
            aliceAvailable, aliceProof, aliceAvailable, BASE_DISCOUNT, address(paymentToken), false, 0, alice
        );

        // Try to purchase again
        vm.expectRevert(IRewardsErrors.AltoRewardsDistributorInvalidInput.selector);
        distributor.claimRewardTokens(
            aliceAvailable, aliceProof, 1, BASE_DISCOUNT, address(paymentToken), false, 0, alice
        );
        vm.stopPrank();
    }

    function test_ClaimPurchase_RevertIf_InvalidPaymentToken() public {
        vm.startPrank(alice);

        // Try with unregistered payment token
        vm.expectRevert(IRewardsErrors.AltoRewardsDistributorInvalidInput.selector);
        distributor.claimRewardTokens(
            aliceAvailable, aliceProof, aliceAvailable, BASE_DISCOUNT, address(0x999), false, 0, alice
        );
        vm.stopPrank();
    }

    function test_ClaimPurchase_RevertIf_PriceNotSet() public {
        // Deploy new distributor without setting price
        AltoRewardsDistributor newDistributor =
            new AltoRewardsDistributor(owner, INITIAL_TIMELOCK, address(rewardToken));

        vm.startPrank(owner);
        newDistributor.setPaymentToken(address(paymentToken), address(paymentOracle));
        newDistributor.submitNewPendingRoot(testRoot, bytes32(0));
        newDistributor.acceptPendingRoot(testRoot);
        vm.stopPrank();

        vm.startPrank(alice);
        paymentToken.approve(address(newDistributor), type(uint256).max);

        vm.expectRevert(IRewardsErrors.AltoRewardsDistributorLockRewardsOracleNotSet.selector);
        newDistributor.claimRewardTokens(
            aliceAvailable, aliceProof, aliceAvailable, BASE_DISCOUNT, address(paymentToken), false, 0, alice
        );
        vm.stopPrank();
    }

    function test_ClaimPurchase_RevertIf_LockNotSet() public {
        // Deploy new distributor without setting lock
        AltoRewardsDistributor newDistributor =
            new AltoRewardsDistributor(owner, INITIAL_TIMELOCK, address(rewardToken));

        OracleMock newRewardOracle = new OracleMock();
        newRewardOracle.setPrice(REWARD_PRICE);

        vm.startPrank(owner);
        newDistributor.setPaymentToken(address(paymentToken), address(paymentOracle));
        newDistributor.setRewardTokenUsdOracle(address(newRewardOracle));
        newDistributor.submitNewPendingRoot(testRoot, bytes32(0));
        newDistributor.acceptPendingRoot(testRoot);
        vm.stopPrank();

        // Fund distributor
        deal(address(rewardToken), address(newDistributor), 10000 * 10 ** rewardToken.decimals());

        vm.startPrank(alice);
        paymentToken.approve(address(newDistributor), type(uint256).max);

        vm.expectRevert(IRewardsErrors.AltoRewardsDistributorLockContractNotSet.selector);
        newDistributor.claimRewardTokens(
            aliceAvailable,
            aliceProof,
            aliceAvailable,
            BASE_DISCOUNT,
            address(paymentToken),
            true, // try to lock
            1,
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

        uint256 expectedPayment = _getExpectedPayment(true, 0, false);

        vm.expectEmit(true, true, true, true);
        emit IRewardsEvents.ClaimRewardTokens(
            alice, alice, address(paymentToken), expectedPayment / 2, firstPurchase, BASE_DISCOUNT
        );

        distributor.claimRewardTokens(
            aliceAvailable, aliceProof, firstPurchase, BASE_DISCOUNT, address(paymentToken), false, 0, alice
        );

        assertEq(distributor.purchasedRewardTokenUser(alice), firstPurchase);
        vm.stopPrank();

        // Create new merkle tree with increased allocation
        uint256 aliceNewAvailable = 1500 * 10 ** 18;
        bytes32 aliceNewLeaf = keccak256(bytes.concat(keccak256(abi.encode(alice, aliceNewAvailable, BASE_DISCOUNT))));
        bytes32 bobLeaf = keccak256(bytes.concat(keccak256(abi.encode(bob, bobAvailable, BASE_DISCOUNT))));

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
        distributor.submitNewPendingRoot(newRoot, bytes32(0));

        vm.warp(block.timestamp + INITIAL_TIMELOCK);
        distributor.acceptPendingRoot(newRoot);

        // Alice can now purchase from the increased allocation
        vm.startPrank(alice);
        uint256 additionalPurchase = 700 * 10 ** 18; // More than original allocation allows

        vm.expectEmit(true, true, true, true);
        emit IRewardsEvents.ClaimRewardTokens(
            alice, alice, address(paymentToken), expectedPayment * 70 / 100, additionalPurchase, BASE_DISCOUNT
        );

        distributor.claimRewardTokens(
            aliceNewAvailable, aliceNewProof, additionalPurchase, BASE_DISCOUNT, address(paymentToken), false, 0, alice
        );

        assertEq(distributor.purchasedRewardTokenUser(alice), firstPurchase + additionalPurchase);
        vm.stopPrank();
    }

    function test_WithdrawTokens() public {
        // First make a purchase to get payment tokens in the contract

        vm.startPrank(alice);
        paymentToken.approve(address(distributor), type(uint256).max);

        uint256 expectedPayment = _getExpectedPayment(true, 0, false);

        vm.expectEmit(true, true, true, true);
        emit IRewardsEvents.ClaimRewardTokens(
            alice, alice, address(paymentToken), expectedPayment, aliceAvailable, BASE_DISCOUNT
        );

        distributor.claimRewardTokens(
            aliceAvailable, aliceProof, aliceAvailable, BASE_DISCOUNT, address(paymentToken), false, 0, alice
        );
        vm.stopPrank();

        uint256 contractBalance = paymentToken.balanceOf(address(distributor));
        assertGt(contractBalance, 0);

        // Withdraw as owner
        uint256 ownerBefore = paymentToken.balanceOf(owner);

        vm.expectEmit(true, true, false, true);
        emit IRewardsEvents.WithdrawContractTokens(address(paymentToken), owner, contractBalance);

        vm.prank(owner);
        distributor.withdrawContractTokens(address(paymentToken), contractBalance);

        assertEq(paymentToken.balanceOf(owner), ownerBefore + contractBalance);
        assertEq(paymentToken.balanceOf(address(distributor)), 0);
    }

    function test_ClaimPurchase_WithMaxDiscount() public {
        // Update tree with max discount for users
        uint256 maxDiscount = distributor.MAX_DISCOUNT();
        vm.startPrank(owner);
        (bytes32 root,,) = _setupMerkleTreeWithDiscount(aliceAvailable, maxDiscount, bobAvailable, maxDiscount);
        distributor.submitNewPendingRoot(root, bytes32(0));
        vm.warp(block.timestamp + INITIAL_TIMELOCK);
        distributor.acceptPendingRoot(root);
        vm.stopPrank();

        // Approve payment
        vm.startPrank(alice);
        paymentToken.approve(address(distributor), type(uint256).max);

        uint256 alicePaymentBefore = paymentToken.balanceOf(alice);
        uint256 aliceRewardBefore = rewardToken.balanceOf(alice);

        uint256 expectedPayment = _getExpectedPaymentWithDiscount(true, 0, maxDiscount);

        // Expect PurchaseClaimed event
        vm.expectEmit(true, true, true, true);
        emit IRewardsEvents.ClaimRewardTokens(
            alice, alice, address(paymentToken), expectedPayment, aliceAvailable, maxDiscount
        );

        uint256 paymentAmountReturn = distributor.claimRewardTokens(
            aliceAvailable, aliceProof, aliceAvailable, maxDiscount, address(paymentToken), false, 0, alice
        );

        assertEq(paymentToken.balanceOf(alice), alicePaymentBefore - expectedPayment);

        assertEq(paymentAmountReturn, expectedPayment);
        assertEq(distributor.purchasedRewardTokenUser(alice), aliceAvailable);
        assertEq(rewardToken.balanceOf(alice), aliceRewardBefore + aliceAvailable);

        vm.stopPrank();
    }

    function test_ClaimPurchase_WithMaxLockDiscount() public {
        uint256 maxDiscount = distributor.MAX_DISCOUNT();
        vm.prank(owner);
        distributor.setLockBonusDiscount(maxDiscount); // max discount when locking

        // Approve payment
        vm.startPrank(alice);
        paymentToken.approve(address(distributor), type(uint256).max);

        uint256 alicePaymentBefore = paymentToken.balanceOf(alice);
        uint256 expectedPayment = _getExpectedPaymentWithDiscount(true, 0, maxDiscount);
        // Expect PurchaseClaimed event
        vm.expectEmit(true, true, true, true);
        emit IRewardsEvents.ClaimRewardTokens(
            alice, alice, address(paymentToken), expectedPayment, aliceAvailable, maxDiscount
        );

        // Purchase with lock and max discount
        distributor.claimRewardTokens(
            aliceAvailable, aliceProof, aliceAvailable, BASE_DISCOUNT, address(paymentToken), true, 1, alice
        );

        assertEq(paymentToken.balanceOf(alice), alicePaymentBefore - expectedPayment);
        // Verify tokens were locked
        assertEq(lockContract.locked(alice), aliceAvailable);
        assertEq(lockContract.lastTo(), alice);
        assertEq(lockContract.lastAmount(), aliceAvailable);
        assertEq(lockContract.lastContainerId(), 1);
        assertEq(lockContract.lastIsReuse(), false);
        assertEq(lockContract.lastMaxEpochsToLockFor(), 1);
        assertEq(distributor.purchasedRewardTokenUser(alice), aliceAvailable);

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

        uint256 expectedPayment = _getExpectedPayment(true, 0, false);
        // Expect PurchaseClaimed event with bob as caller and alice as onBehalf
        vm.expectEmit(true, true, true, true);
        emit IRewardsEvents.ClaimRewardTokens(
            bob, alice, address(paymentToken), expectedPayment, aliceAvailable, BASE_DISCOUNT
        );

        // Bob claims on behalf of Alice
        distributor.claimRewardTokens(
            aliceAvailable, aliceProof, aliceAvailable, BASE_DISCOUNT, address(paymentToken), false, 0, alice
        );

        // Verify Bob paid but Alice received the rewards
        assertEq(paymentToken.balanceOf(bob), bobPaymentBefore - expectedPayment);
        assertEq(rewardToken.balanceOf(alice), aliceRewardBefore + aliceAvailable);
        assertEq(distributor.purchasedRewardTokenUser(alice), aliceAvailable);

        vm.stopPrank();
    }

    function test_SubmitRoot_WithoutExpiry() public {
        bytes32 newRoot = bytes32(uint256(1));
        bytes32 newIpfsHash = bytes32(uint256(2));

        vm.expectEmit(true, true, false, true);
        emit IMerkleRootManagerEvents.SubmitPendingMerkleRoot(updater, newRoot, bytes32(0));

        vm.prank(updater);
        distributor.submitNewPendingRoot(newRoot, bytes32(0));

        (bytes32 root, uint256 validAt, bytes32 ipfsHash) = distributor.pendingMerkleRoot();
        assertEq(root, newRoot);
        assertEq(validAt, block.timestamp + INITIAL_TIMELOCK);
    }

    function test_Pause_BlocksClaims() public {
        // Pause the contract
        vm.prank(distributor.owner());
        distributor.setPauser(bob, PAUSE_TYPE, true);

        vm.prank(bob);
        distributor.pause(PAUSE_TYPE, true);

        assertEq(distributor.paused(PAUSE_TYPE), true);

        // Try to purchase while paused - should fail
        vm.startPrank(alice);
        paymentToken.approve(address(distributor), type(uint256).max);

        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSE_TYPE));
        distributor.claimRewardTokens(
            aliceAvailable, aliceProof, aliceAvailable, BASE_DISCOUNT, address(paymentToken), false, 0, alice
        );
        vm.stopPrank();

        // Unpause and try again - should work
        vm.prank(bob);
        distributor.pause(PAUSE_TYPE, false);

        assertEq(distributor.paused(PAUSE_TYPE), false);

        vm.startPrank(alice);

        uint256 expectedPayment = _getExpectedPayment(true, 0, false);

        vm.expectEmit(true, true, true, true);
        emit IRewardsEvents.ClaimRewardTokens(
            alice, alice, address(paymentToken), expectedPayment, aliceAvailable, BASE_DISCOUNT
        );

        uint256 paymentAmountReturn = distributor.claimRewardTokens(
            aliceAvailable, aliceProof, aliceAvailable, BASE_DISCOUNT, address(paymentToken), false, 0, alice
        );
        assertEq(paymentAmountReturn, expectedPayment);
        vm.stopPrank();
    }

    function testFuzz_ClaimPurchase_VariousPurchaseAmounts(uint256 purchaseAmount, uint256 aliceClaim) public {
        aliceClaim = bound(aliceClaim, 0.01e18, 100_000_000e18);
        purchaseAmount = bound(purchaseAmount, 0.01e18, aliceClaim);

        (bytes32 root, bytes32[] memory aliceLeafProof,) =
            _setupMerkleTreeWithDiscount(aliceClaim, BASE_DISCOUNT, 100e18, BASE_DISCOUNT);
        deal(address(paymentToken), alice, purchaseAmount);
        deal(address(rewardToken), address(distributor), aliceClaim);

        vm.prank(owner);
        distributor.submitNewPendingRoot(root, bytes32(0));

        vm.warp(block.timestamp + INITIAL_TIMELOCK);
        distributor.acceptPendingRoot(root);

        vm.startPrank(alice);
        paymentToken.approve(address(distributor), type(uint256).max);

        uint256 alicePaymentBefore = paymentToken.balanceOf(alice);
        uint256 aliceRewardBefore = rewardToken.balanceOf(alice);

        // Calculate expected payment
        uint256 expectedPayment =
            _calculateExpectedPayment(purchaseAmount, BASE_DISCOUNT, REWARD_PRICE, PAYMENT_TOKEN_PRICE);

        // Purchase tokens
        uint256 paymentAmountReturn = distributor.claimRewardTokens(
            aliceClaim, aliceLeafProof, purchaseAmount, BASE_DISCOUNT, address(paymentToken), false, 0, alice
        );

        // Verify results
        assertEq(paymentAmountReturn, expectedPayment);
        assertEq(distributor.purchasedRewardTokenUser(alice), purchaseAmount);

        // Check payment was taken (allow for rounding)
        uint256 actualPayment = alicePaymentBefore - paymentToken.balanceOf(alice);
        assertEq(actualPayment, expectedPayment);

        // Check rewards were received
        assertEq(rewardToken.balanceOf(alice), aliceRewardBefore + purchaseAmount);

        vm.stopPrank();
    }

    function _calculateExpectedPayment(
        uint256 purchaseAmount,
        uint256 discount,
        uint256 rewardTokenPrice,
        uint256 paymentTokenPrice
    ) internal view returns (uint256) {
        // Calculate reward requested to purchase in USD
        uint256 rewardToPurchaseCostUsd = purchaseAmount.divideWithRounding(
            rewardTokenPrice,
            10 ** rewardToken.decimals(),
            true // round up to avoid zero payment
        );

        // Convert to payment token amount
        // Result should have paymentDecimals decimals
        uint256 paymentAmount = rewardToPurchaseCostUsd.divideWithRounding(
            10 ** paymentToken.decimals(),
            paymentTokenPrice,
            true // round up to ensure we never underpay
        );

        // Apply discount using MATH_PRECISION
        paymentAmount = paymentAmount.multiplyWithPrecisionUp(MATH_PRECISION - discount);

        return paymentAmount;
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
                distributor.claimRewardTokens(
                    aliceAvailable, aliceProof, amounts[i], BASE_DISCOUNT, address(paymentToken), false, 0, alice
                );
                totalPurchased += amounts[i];
                assertEq(distributor.purchasedRewardTokenUser(alice), totalPurchased);
            }
        }

        vm.stopPrank();
    }

    function testFuzz_ClaimPurchase_VariousTokenPrices(uint256 tokenPrice) public {
        // Bound token price to reasonable range (avoid overflow and ensure > 0)
        tokenPrice = bound(tokenPrice, _getOraclePriceFromEther(0.01 ether), _getOraclePriceFromEther(100000 ether));

        // Create new oracle with fuzzed price
        OracleMock fuzzOracle = new OracleMock();
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

        uint256 expectedPayment = _calculateExpectedPayment(purchaseAmount, BASE_DISCOUNT, REWARD_PRICE, tokenPrice);

        // Should not revert for valid prices
        distributor.claimRewardTokens(
            aliceAvailable, aliceProof, purchaseAmount, BASE_DISCOUNT, address(fuzzPaymentToken), false, 0, alice
        );

        uint256 actualPayment = alicePaymentBefore - fuzzPaymentToken.balanceOf(alice);

        // Verify payment is never zero for non-zero purchase
        assertGt(actualPayment, 0);

        // Verify payment is within expected range (allowing for rounding)
        assertGe(actualPayment, expectedPayment - 1);
        assertLe(actualPayment, expectedPayment + 1);

        vm.stopPrank();
    }

    function testFuzz_ClaimPurchase_VariousDiscounts(uint256 discount, uint256 lockDiscount, bool shouldLock) public {
        // Bound discounts to valid range (0-MAX_DISCOUNT)
        discount = bound(discount, 1, distributor.MAX_DISCOUNT());
        lockDiscount = bound(lockDiscount, 1, distributor.MAX_DISCOUNT());

        // Ensure lockDiscount >= discount (it should be a better discount)
        if (lockDiscount < discount) {
            uint256 temp = discount;
            discount = lockDiscount;
            lockDiscount = temp;
        }

        // Set new lock bonus and update root to carry user discount in Merkle
        vm.startPrank(owner);
        distributor.setLockBonusDiscount(lockDiscount);
        (bytes32 dRoot, bytes32[] memory aProof,) =
            _setupMerkleTreeWithDiscount(aliceAvailable, discount, bobAvailable, discount);
        distributor.submitNewPendingRoot(dRoot, bytes32(0));
        vm.warp(block.timestamp + INITIAL_TIMELOCK);
        distributor.acceptPendingRoot(dRoot);
        vm.stopPrank();

        vm.startPrank(alice);
        paymentToken.approve(address(distributor), type(uint256).max);

        uint256 purchaseAmount = aliceAvailable / 2;
        uint256 alicePaymentBefore = paymentToken.balanceOf(alice);

        // Calculate expected payment with appropriate discount
        uint256 appliedDiscount = shouldLock
            ? discount + lockDiscount > distributor.MAX_DISCOUNT() ? distributor.MAX_DISCOUNT() : discount + lockDiscount
            : discount;
        uint256 expectedPayment =
            _calculateExpectedPayment(purchaseAmount, appliedDiscount, REWARD_PRICE, PAYMENT_TOKEN_PRICE);

        distributor.claimRewardTokens(
            aliceAvailable, aProof, purchaseAmount, discount, address(paymentToken), shouldLock, 1, alice
        );

        uint256 actualPayment = alicePaymentBefore - paymentToken.balanceOf(alice);

        // For very high discounts (close to 100%), the payment might round to zero or be very small
        if (appliedDiscount >= MATH_PRECISION - 1e15) {
            // Within 0.001% of 100%
            // Payment could be 0 or very small due to rounding
            // With such high discount, we just verify the payment is minimal
            assertLe(actualPayment, expectedPayment * 2, "Payment should be close to expected even with rounding");
        } else {
            assertEq(actualPayment, expectedPayment);
        }

        assertEq(distributor.purchasedRewardTokenUser(alice), purchaseAmount);
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
        AltoRewardsDistributor fuzzDistributor =
            new AltoRewardsDistributor(owner, INITIAL_TIMELOCK, address(fuzzRewardToken));

        // Setup
        OracleMock fuzzOracle = new OracleMock();
        fuzzOracle.setPrice(_getOraclePriceFromEther(1 ether)); // $1

        vm.startPrank(owner);
        fuzzDistributor.submitNewPendingRoot(testRoot, bytes32(0));
        fuzzDistributor.acceptPendingRoot(testRoot);
        fuzzDistributor.setMerkleRootUpdater(updater, true);
        fuzzDistributor.setPaymentToken(address(fuzzPaymentToken), address(fuzzOracle));
        OracleMock fuzzRewardOracle = new OracleMock();
        fuzzRewardOracle.setPrice(_getOraclePriceFromEther(100 ether)); // $100
        fuzzDistributor.setRewardTokenUsdOracle(address(fuzzRewardOracle));
        vm.stopPrank();

        // Fund
        uint256 scaledAllocation = 1000 * 10 ** rewardDecimals;
        deal(address(fuzzRewardToken), address(fuzzDistributor), scaledAllocation * 10);
        deal(address(fuzzPaymentToken), alice, type(uint128).max);

        // Create new merkle tree for fuzzed allocation
        //uint256 fuzzDiscount = MATH_PRECISION * 10 / 100; // 10%
        bytes32 aliceFuzzLeaf =
            keccak256(bytes.concat(keccak256(abi.encode(alice, scaledAllocation, MATH_PRECISION * 10 / 100))));
        bytes32 bobFuzzLeaf =
            keccak256(bytes.concat(keccak256(abi.encode(bob, scaledAllocation, MATH_PRECISION * 10 / 100))));

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
        fuzzDistributor.submitNewPendingRoot(fuzzRoot, bytes32(0));
        vm.warp(block.timestamp + INITIAL_TIMELOCK);
        fuzzDistributor.acceptPendingRoot(fuzzRoot);

        // Test claim
        vm.startPrank(alice);
        fuzzPaymentToken.approve(address(fuzzDistributor), type(uint256).max);

        uint256 purchaseAmount = scaledAllocation / 2;

        // Should not revert for any valid decimal combination
        fuzzDistributor.claimRewardTokens(
            scaledAllocation,
            fuzzProof,
            purchaseAmount,
            MATH_PRECISION * 10 / 100,
            address(fuzzPaymentToken),
            false,
            0,
            alice
        );

        assertEq(fuzzDistributor.purchasedRewardTokenUser(alice), purchaseAmount);
        assertEq(fuzzRewardToken.balanceOf(alice), purchaseAmount);

        vm.stopPrank();
    }
}
