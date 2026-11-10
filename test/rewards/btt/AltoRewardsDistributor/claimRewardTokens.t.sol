// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {RewardsDistributorCommon} from "./RewardsDistributorCommon.t.sol";
import {AltoRewardsDistributor} from "@alto/rewards/AltoRewardsDistributor.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {IRewardsEvents, IRewardsErrors, ClaimData} from "@alto/rewards/interfaces/IRewardsDistributor.sol";
import {MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";
import {IMerkleRootManagerErrors} from "@alto/utils/interfaces/IMerkleRootManager.sol";

contract AltoRewardsDistributorClaimRewardTokens is RewardsDistributorCommon {
    function test_RevertWhen_ContractIsPaused() external {
        vm.prank(PAUSER);
        distributor.pause(PAUSE_TYPE, true);

        vm.startPrank(ALICE);
        paymentToken.approve(address(distributor), type(uint256).max);

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSE_TYPE));
        distributor.claimRewardTokens(
            _getClaimData(aliceAvailable, BASE_DISCOUNT, 0, 0),
            aliceProof,
            aliceAvailable,
            address(paymentToken),
            false,
            0,
            ALICE
        );
        vm.stopPrank();
    }

    function test_RevertWhen_CallerIsNotAuthorizedForOnBehalf() external {
        vm.startPrank(BOB);
        paymentToken.approve(address(distributor), type(uint256).max);

        // it should revert
        vm.expectRevert(IRewardsErrors.AltoRewardsDistributorUnauthorized.selector);
        distributor.claimRewardTokens(
            _getClaimData(aliceAvailable, BASE_DISCOUNT, 0, 0),
            aliceProof,
            aliceAvailable,
            address(paymentToken),
            false,
            0,
            ALICE
        );
        vm.stopPrank();
    }

    function test_RevertWhen_MerkleRootIsNotSet() external {
        // Deploy new distributor without setting merkle root
        AltoRewardsDistributor newDistributor =
            new AltoRewardsDistributor(OWNER, INITIAL_TIMELOCK, address(rewardToken));

        vm.startPrank(OWNER);
        newDistributor.setPaymentToken(address(paymentToken), address(paymentOracle));
        newDistributor.setRewardTokenUsdOracle(address(rewardOracle));
        vm.stopPrank();

        vm.startPrank(ALICE);
        paymentToken.approve(address(newDistributor), type(uint256).max);

        // it should revert
        vm.expectRevert(IMerkleRootManagerErrors.MerkleRootManagerRootNotSet.selector);
        newDistributor.claimRewardTokens(
            _getClaimData(aliceAvailable, BASE_DISCOUNT, 0, 0),
            aliceProof,
            aliceAvailable,
            address(paymentToken),
            false,
            0,
            ALICE
        );
        vm.stopPrank();
    }

    function test_RevertWhen_LockPurchasedRewardsIsTrueAndLockContractIsNotSet() external {
        // Deploy new distributor without setting lock contract
        AltoRewardsDistributor newDistributor =
            new AltoRewardsDistributor(OWNER, INITIAL_TIMELOCK, address(rewardToken));

        vm.startPrank(OWNER);
        newDistributor.setPaymentToken(address(paymentToken), address(paymentOracle));
        newDistributor.setRewardTokenUsdOracle(address(rewardOracle));
        newDistributor.submitNewPendingRoot(testRoot, bytes32(0));
        newDistributor.acceptPendingRoot(testRoot);
        vm.stopPrank();

        vm.startPrank(ALICE);
        paymentToken.approve(address(newDistributor), type(uint256).max);

        // it should revert
        vm.expectRevert(IRewardsErrors.AltoRewardsDistributorLockContractNotSet.selector);
        newDistributor.claimRewardTokens(
            _getClaimData(aliceAvailable, BASE_DISCOUNT, 0, 0),
            aliceProof,
            aliceAvailable,
            address(paymentToken),
            true,
            1,
            ALICE
        );
        vm.stopPrank();
    }

    modifier givenInvalidMerkleProof() {
        _;
    }

    function test_RevertGiven_InvalidMerkleProof() external givenInvalidMerkleProof {
        vm.startPrank(ALICE);
        paymentToken.approve(address(distributor), type(uint256).max);

        // Use Bob's proof with Alice's data
        // it should revert
        vm.expectRevert(IRewardsErrors.AltoRewardsDistributorInvalidInput.selector);
        distributor.claimRewardTokens(
            _getClaimData(aliceAvailable, BASE_DISCOUNT, 0, 0),
            bobProof,
            aliceAvailable,
            address(paymentToken),
            false,
            0,
            ALICE
        );
        vm.stopPrank();
    }

    modifier givenInvalidInputs() {
        _;
    }

    function test_RevertWhen_RewardsPurchaseAmountIsZero() external givenInvalidInputs {
        vm.startPrank(ALICE);
        paymentToken.approve(address(distributor), type(uint256).max);

        // it should revert
        vm.expectRevert(IRewardsErrors.AltoRewardsDistributorInvalidInput.selector);
        distributor.claimRewardTokens(
            _getClaimData(aliceAvailable, BASE_DISCOUNT, 0, 0), aliceProof, 0, address(paymentToken), false, 0, ALICE
        );
        vm.stopPrank();
    }

    function test_RevertWhen_RewardsPurchaseAmountExceedsAvailableAmount() external givenInvalidInputs {
        vm.startPrank(ALICE);
        paymentToken.approve(address(distributor), type(uint256).max);

        // it should revert
        vm.expectRevert(IRewardsErrors.AltoRewardsDistributorInvalidInput.selector);
        distributor.claimRewardTokens(
            _getClaimData(aliceAvailable, BASE_DISCOUNT, 0, 0),
            aliceProof,
            aliceAvailable + 1,
            address(paymentToken),
            false,
            0,
            ALICE
        );
        vm.stopPrank();
    }

    function test_RevertWhen_OnBehalfIsZeroAddress() external givenInvalidInputs {
        vm.startPrank(ALICE);
        paymentToken.approve(address(distributor), type(uint256).max);

        // it should revert (authorization check happens first)
        vm.expectRevert(IRewardsErrors.AltoRewardsDistributorUnauthorized.selector);
        distributor.claimRewardTokens(
            _getClaimData(aliceAvailable, BASE_DISCOUNT, 0, 0),
            aliceProof,
            aliceAvailable,
            address(paymentToken),
            false,
            0,
            address(0)
        );
        vm.stopPrank();
    }

    function test_RevertWhen_ClaimHasExpired() external givenInvalidInputs {
        // Set a proper timestamp first
        vm.warp(1000);

        // Create a new merkle tree with expiration timestamp
        uint256 expirationTimestamp = block.timestamp - 1; // Expired 1 second ago

        // Build new merkle tree with expiration
        bytes32 aliceLeaf = keccak256(
            bytes.concat(keccak256(abi.encode(ALICE, aliceAvailable, BASE_DISCOUNT, 0, expirationTimestamp)))
        );
        bytes32 bobLeaf = keccak256(bytes.concat(keccak256(abi.encode(BOB, bobAvailable, BASE_DISCOUNT, 0, 0))));

        bytes32 root;
        bytes32[] memory newAliceProof = new bytes32[](1);

        if (uint256(aliceLeaf) < uint256(bobLeaf)) {
            root = keccak256(abi.encodePacked(aliceLeaf, bobLeaf));
            newAliceProof[0] = bobLeaf;
        } else {
            root = keccak256(abi.encodePacked(bobLeaf, aliceLeaf));
            newAliceProof[0] = bobLeaf;
        }

        // Update merkle root
        vm.startPrank(OWNER);
        distributor.submitNewPendingRoot(root, bytes32(0));
        vm.warp(block.timestamp + INITIAL_TIMELOCK);
        distributor.acceptPendingRoot(root);
        vm.stopPrank();

        vm.startPrank(ALICE);
        paymentToken.approve(address(distributor), type(uint256).max);

        // it should revert
        vm.expectRevert(IRewardsErrors.AltoRewardsDistributorInvalidInput.selector);

        distributor.claimRewardTokens(
            _getClaimData(aliceAvailable, BASE_DISCOUNT, 0, expirationTimestamp),
            newAliceProof,
            aliceAvailable,
            address(paymentToken),
            false,
            0,
            ALICE
        );
        vm.stopPrank();
    }

    function test_RevertWhen_PaymentTokenIsNotConfigured() external {
        vm.startPrank(ALICE);

        // Try with unregistered payment token
        // it should revert
        vm.expectRevert(IRewardsErrors.AltoRewardsDistributorInvalidInput.selector);
        distributor.claimRewardTokens(
            _getClaimData(aliceAvailable, BASE_DISCOUNT, 0, 0),
            aliceProof,
            aliceAvailable,
            address(0x999),
            false,
            0,
            ALICE
        );
        vm.stopPrank();
    }

    function test_RevertWhen_RewardTokenUsdOracleIsNotSet() external {
        // Deploy new distributor without setting reward oracle
        AltoRewardsDistributor newDistributor =
            new AltoRewardsDistributor(OWNER, INITIAL_TIMELOCK, address(rewardToken));

        vm.startPrank(OWNER);
        newDistributor.setPaymentToken(address(paymentToken), address(paymentOracle));
        newDistributor.submitNewPendingRoot(testRoot, bytes32(0));
        newDistributor.acceptPendingRoot(testRoot);
        vm.stopPrank();

        vm.startPrank(ALICE);
        paymentToken.approve(address(newDistributor), type(uint256).max);

        // it should revert
        vm.expectRevert(IRewardsErrors.AltoRewardsDistributorLockRewardsOracleNotSet.selector);
        newDistributor.claimRewardTokens(
            _getClaimData(aliceAvailable, BASE_DISCOUNT, 0, 0),
            aliceProof,
            aliceAvailable,
            address(paymentToken),
            false,
            0,
            ALICE
        );
        vm.stopPrank();
    }

    function test_RevertWhen_OracleReturnsInvalidPriceZero() external {
        // Set reward oracle price to zero
        rewardOracle.setPrice(0);

        vm.startPrank(ALICE);
        paymentToken.approve(address(distributor), type(uint256).max);

        // it should revert
        vm.expectRevert(IRewardsErrors.AltoRewardsDistributorLockInvalidOraclePrice.selector);
        distributor.claimRewardTokens(
            _getClaimData(aliceAvailable, BASE_DISCOUNT, 0, 0),
            aliceProof,
            aliceAvailable,
            address(paymentToken),
            false,
            0,
            ALICE
        );
        vm.stopPrank();

        // Reset price for other tests
        rewardOracle.setPrice(REWARD_PRICE);
    }

    modifier givenValidInputs() {
        _;
    }

    function test_WhenPurchasingPartialAmount() external givenValidInputs {
        uint256 partialAmount = aliceAvailable / 2;
        uint256 expectedPayment = _getExpectedPayment(true, 0, false) / 2;

        vm.startPrank(ALICE);
        paymentToken.approve(address(distributor), type(uint256).max);

        uint256 alicePaymentBefore = paymentToken.balanceOf(ALICE);
        uint256 aliceRewardBefore = rewardToken.balanceOf(ALICE);

        // it should emit ClaimRewardTokens event with correct id
        vm.expectEmit(true, true, true, true);
        emit IRewardsEvents.ClaimRewardTokens(
            ALICE, ALICE, 0, partialAmount, address(paymentToken), expectedPayment, BASE_DISCOUNT
        );

        uint256 paymentAmountReturn = distributor.claimRewardTokens(
            _getClaimData(aliceAvailable, BASE_DISCOUNT, 0, 0),
            aliceProof,
            partialAmount,
            address(paymentToken),
            false,
            0,
            ALICE
        );

        // it should return payment amount
        assertEq(paymentAmountReturn, expectedPayment);

        // it should update purchased amount for user with correct id
        assertEq(distributor.purchasedRewardTokenUser(ALICE, 0), partialAmount);

        // it should transfer payment tokens from caller
        assertEq(paymentToken.balanceOf(ALICE), alicePaymentBefore - expectedPayment);

        // it should transfer reward tokens to onBehalf
        assertEq(rewardToken.balanceOf(ALICE), aliceRewardBefore + partialAmount);

        vm.stopPrank();
    }

    function test_WhenPurchasingFullAvailableAmount() external givenValidInputs {
        uint256 expectedPayment = _getExpectedPayment(true, 0, false);

        vm.startPrank(ALICE);
        paymentToken.approve(address(distributor), type(uint256).max);

        uint256 alicePaymentBefore = paymentToken.balanceOf(ALICE);
        uint256 aliceRewardBefore = rewardToken.balanceOf(ALICE);

        // it should emit ClaimRewardTokens event with correct id
        vm.expectEmit(true, true, true, true);
        emit IRewardsEvents.ClaimRewardTokens(
            ALICE, ALICE, 0, aliceAvailable, address(paymentToken), expectedPayment, BASE_DISCOUNT
        );

        uint256 paymentAmountReturn = distributor.claimRewardTokens(
            _getClaimData(aliceAvailable, BASE_DISCOUNT, 0, 0),
            aliceProof,
            aliceAvailable,
            address(paymentToken),
            false,
            0,
            ALICE
        );

        // it should return payment amount
        assertEq(paymentAmountReturn, expectedPayment);

        // it should update purchased amount for user with correct id
        assertEq(distributor.purchasedRewardTokenUser(ALICE, 0), aliceAvailable);

        // it should transfer payment tokens from caller
        assertEq(paymentToken.balanceOf(ALICE), alicePaymentBefore - expectedPayment);

        // it should transfer reward tokens to onBehalf
        assertEq(rewardToken.balanceOf(ALICE), aliceRewardBefore + aliceAvailable);

        vm.stopPrank();
    }

    function test_WhenLockPurchasedRewardsIsTrue() external givenValidInputs {
        uint256 expectedPayment = _getExpectedPayment(true, 0, true);

        vm.startPrank(ALICE);
        paymentToken.approve(address(distributor), type(uint256).max);

        uint256 alicePaymentBefore = paymentToken.balanceOf(ALICE);

        // it should emit ClaimRewardTokens event with combined discount and correct id
        vm.expectEmit(true, true, true, true);
        emit IRewardsEvents.ClaimRewardTokens(
            ALICE, ALICE, 0, aliceAvailable, address(paymentToken), expectedPayment, BASE_DISCOUNT + LOCK_DISCOUNT
        );

        uint256 paymentAmountReturn = distributor.claimRewardTokens(
            _getClaimData(aliceAvailable, BASE_DISCOUNT, 0, 0),
            aliceProof,
            aliceAvailable,
            address(paymentToken),
            true,
            1,
            ALICE
        );

        // it should return payment amount
        assertEq(paymentAmountReturn, expectedPayment);

        // it should update purchased amount for user with correct id
        assertEq(distributor.purchasedRewardTokenUser(ALICE, 0), aliceAvailable);

        // it should apply lock bonus discount
        assertEq(paymentToken.balanceOf(ALICE), alicePaymentBefore - expectedPayment);

        // it should call lock contract with reward amount and onBehalf
        assertEq(lockContract.locked(ALICE), aliceAvailable);
        assertEq(lockContract.lastTo(), ALICE);
        assertEq(lockContract.lastAmount(), aliceAvailable);

        vm.stopPrank();
    }

    function test_WhenDiscountReachesMAX_DISCOUNT() external givenValidInputs {
        uint256 maxDiscount = distributor.MAX_DISCOUNT();

        // Update merkle tree with max discount
        vm.startPrank(OWNER);
        (bytes32 root, bytes32[] memory newAliceProof,) =
            _setupMerkleTreeWithDiscount(0, aliceAvailable, maxDiscount, 0, bobAvailable, maxDiscount);
        distributor.submitNewPendingRoot(root, bytes32(0));
        vm.warp(block.timestamp + INITIAL_TIMELOCK);
        distributor.acceptPendingRoot(root);
        vm.stopPrank();

        uint256 expectedPayment = _getExpectedPaymentWithDiscount(true, 0, maxDiscount);

        vm.startPrank(ALICE);
        paymentToken.approve(address(distributor), type(uint256).max);

        uint256 alicePaymentBefore = paymentToken.balanceOf(ALICE);

        // it should emit ClaimRewardTokens event with correct id
        vm.expectEmit(true, true, true, true);
        emit IRewardsEvents.ClaimRewardTokens(
            ALICE, ALICE, 0, aliceAvailable, address(paymentToken), expectedPayment, maxDiscount
        );

        uint256 paymentAmountReturn = distributor.claimRewardTokens(
            _getClaimData(aliceAvailable, maxDiscount, 0, 0),
            newAliceProof,
            aliceAvailable,
            address(paymentToken),
            false,
            0,
            ALICE
        );

        // it should return payment amount
        assertEq(paymentAmountReturn, expectedPayment);

        // it should update purchased amount for user with correct id
        assertEq(distributor.purchasedRewardTokenUser(ALICE, 0), aliceAvailable);

        // it should calculate payment with capped discount
        assertEq(paymentToken.balanceOf(ALICE), alicePaymentBefore - expectedPayment);

        vm.stopPrank();
    }

    function test_WhenUsingDifferentPaymentTokens() external givenValidInputs {
        // Calculate payment for paymentToken2 ($2 per token, 18 decimals)
        uint256 purchaseAmount = aliceAvailable;
        uint256 baseCostUSD = (purchaseAmount * REWARD_PRICE + 10 ** 18 - 1) / 10 ** 18;
        uint256 discountedCostUSD = baseCostUSD * (MATH_PRECISION - BASE_DISCOUNT) / MATH_PRECISION;
        uint256 token2Price = _getOraclePriceFromEther(2 ether);
        uint256 expectedPayment = (discountedCostUSD * 10 ** 18 + token2Price - 1) / token2Price;

        vm.startPrank(ALICE);
        paymentToken2.approve(address(distributor), type(uint256).max);

        uint256 alicePaymentBefore = paymentToken2.balanceOf(ALICE);
        uint256 aliceRewardBefore = rewardToken.balanceOf(ALICE);

        // it should emit ClaimRewardTokens event with correct id
        vm.expectEmit(true, true, true, true);
        emit IRewardsEvents.ClaimRewardTokens(
            ALICE, ALICE, 0, aliceAvailable, address(paymentToken2), expectedPayment, BASE_DISCOUNT
        );

        uint256 paymentAmountReturn = distributor.claimRewardTokens(
            _getClaimData(aliceAvailable, BASE_DISCOUNT, 0, 0),
            aliceProof,
            aliceAvailable,
            address(paymentToken2),
            false,
            0,
            ALICE
        );

        // it should update purchased amount for user with correct id
        assertEq(distributor.purchasedRewardTokenUser(ALICE, 0), aliceAvailable);

        // it should return payment amount
        assertEq(paymentAmountReturn, expectedPayment);

        // it should calculate payment amount based on token price
        assertEq(paymentToken2.balanceOf(ALICE), alicePaymentBefore - expectedPayment);

        // it should handle different decimal precisions
        assertEq(rewardToken.balanceOf(ALICE), aliceRewardBefore + aliceAvailable);

        vm.stopPrank();
    }

    function test_WhenCallerIsDifferentFromOnBehalfAuthorized() external givenValidInputs {
        // Alice authorizes Bob to claim on her behalf
        vm.prank(ALICE);
        distributor.setAuthorization(BOB, true);

        uint256 expectedPayment = _getExpectedPayment(true, 0, false);

        vm.startPrank(BOB);
        paymentToken.approve(address(distributor), type(uint256).max);

        uint256 bobPaymentBefore = paymentToken.balanceOf(BOB);
        uint256 aliceRewardBefore = rewardToken.balanceOf(ALICE);

        // it should emit ClaimRewardTokens event with correct addresses and id
        vm.expectEmit(true, true, true, true);
        emit IRewardsEvents.ClaimRewardTokens(
            BOB, ALICE, 0, aliceAvailable, address(paymentToken), expectedPayment, BASE_DISCOUNT
        );

        uint256 paymentAmountReturn = distributor.claimRewardTokens(
            _getClaimData(aliceAvailable, BASE_DISCOUNT, 0, 0),
            aliceProof,
            aliceAvailable,
            address(paymentToken),
            false,
            0,
            ALICE
        );

        // it should update purchased amount for onBehalf with correct id
        assertEq(distributor.purchasedRewardTokenUser(ALICE, 0), aliceAvailable);

        // it should return payment amount
        assertEq(paymentAmountReturn, expectedPayment);

        // it should transfer payment tokens from caller
        assertEq(paymentToken.balanceOf(BOB), bobPaymentBefore - expectedPayment);

        // it should transfer reward tokens to onBehalf
        assertEq(rewardToken.balanceOf(ALICE), aliceRewardBefore + aliceAvailable);

        // it should update purchased amount for onBehalf with correct id
        assertEq(distributor.purchasedRewardTokenUser(ALICE, 0), aliceAvailable);

        vm.stopPrank();
    }

    function test_WhenClaimHasNoExpiration() external givenValidInputs {
        uint256 expectedPayment = _getExpectedPayment(true, 0, false);

        vm.startPrank(ALICE);
        paymentToken.approve(address(distributor), type(uint256).max);

        uint256 alicePaymentBefore = paymentToken.balanceOf(ALICE);
        uint256 aliceRewardBefore = rewardToken.balanceOf(ALICE);

        // it should emit ClaimRewardTokens event with correct id
        vm.expectEmit(true, true, true, true);
        emit IRewardsEvents.ClaimRewardTokens(
            ALICE, ALICE, 0, aliceAvailable, address(paymentToken), expectedPayment, BASE_DISCOUNT
        );

        uint256 paymentAmountReturn = distributor.claimRewardTokens(
            _getClaimData(aliceAvailable, BASE_DISCOUNT, 0, 0), // expirationTimestamp = 0
            aliceProof,
            aliceAvailable,
            address(paymentToken),
            false,
            0,
            ALICE
        );

        // it should update purchased amount for user with correct id
        assertEq(distributor.purchasedRewardTokenUser(ALICE, 0), aliceAvailable);

        // it should return payment amount
        assertEq(paymentAmountReturn, expectedPayment);

        // it should not check expiration timestamp
        // (implicitly verified by successful execution)

        // it should process claim successfully
        assertEq(paymentToken.balanceOf(ALICE), alicePaymentBefore - expectedPayment);
        assertEq(rewardToken.balanceOf(ALICE), aliceRewardBefore + aliceAvailable);
        assertEq(distributor.purchasedRewardTokenUser(ALICE, 0), aliceAvailable);

        vm.stopPrank();
    }

    function test_WhenClaimHasNotExpired() external givenValidInputs {
        uint256 expirationTimestamp = block.timestamp + 30 days; // Expires in 1 hour
        uint256 expectedPayment = _getExpectedPayment(true, 0, false);

        // Build new merkle tree with expiration
        bytes32 aliceLeaf = keccak256(
            bytes.concat(keccak256(abi.encode(ALICE, aliceAvailable, BASE_DISCOUNT, 0, expirationTimestamp)))
        );
        bytes32 bobLeaf = keccak256(bytes.concat(keccak256(abi.encode(BOB, bobAvailable, BASE_DISCOUNT, 0, 0))));

        bytes32 root;
        bytes32[] memory newAliceProof = new bytes32[](1);

        if (uint256(aliceLeaf) < uint256(bobLeaf)) {
            root = keccak256(abi.encodePacked(aliceLeaf, bobLeaf));
            newAliceProof[0] = bobLeaf;
        } else {
            root = keccak256(abi.encodePacked(bobLeaf, aliceLeaf));
            newAliceProof[0] = bobLeaf;
        }

        // Update merkle root
        vm.startPrank(OWNER);
        distributor.submitNewPendingRoot(root, bytes32(0));
        vm.warp(block.timestamp + INITIAL_TIMELOCK);
        distributor.acceptPendingRoot(root);
        vm.stopPrank();

        vm.startPrank(ALICE);
        paymentToken.approve(address(distributor), type(uint256).max);

        uint256 alicePaymentBefore = paymentToken.balanceOf(ALICE);
        uint256 aliceRewardBefore = rewardToken.balanceOf(ALICE);

        // it should emit ClaimRewardTokens event with correct id
        vm.expectEmit(true, true, true, true);
        emit IRewardsEvents.ClaimRewardTokens(
            ALICE, ALICE, 0, aliceAvailable, address(paymentToken), expectedPayment, BASE_DISCOUNT
        );

        uint256 paymentAmountReturn = distributor.claimRewardTokens(
            _getClaimData(aliceAvailable, BASE_DISCOUNT, 0, expirationTimestamp),
            newAliceProof,
            aliceAvailable,
            address(paymentToken),
            false,
            0,
            ALICE
        );

        // it should return payment amount
        assertEq(paymentAmountReturn, expectedPayment);

        // it should update purchased amount for user with correct id
        assertEq(distributor.purchasedRewardTokenUser(ALICE, 0), aliceAvailable);

        // it should process claim successfully
        assertEq(paymentToken.balanceOf(ALICE), alicePaymentBefore - expectedPayment);
        assertEq(rewardToken.balanceOf(ALICE), aliceRewardBefore + aliceAvailable);
        assertEq(distributor.purchasedRewardTokenUser(ALICE, 0), aliceAvailable);

        vm.stopPrank();
    }

    function test_WhenChangingAmountAfterClaimForSameId_AmountIncreased() external givenValidInputs {
        uint256 initialAmount = aliceAvailable;
        uint256 increasedAmount = 2 * initialAmount;

        // First claim with initial amount
        vm.startPrank(ALICE);
        paymentToken.approve(address(distributor), type(uint256).max);

        uint256 firstPayment = distributor.claimRewardTokens(
            _getClaimData(initialAmount, BASE_DISCOUNT, 0, 0),
            aliceProof,
            initialAmount,
            address(paymentToken),
            false,
            0,
            ALICE
        );

        assertEq(distributor.purchasedRewardTokenUser(ALICE, 0), initialAmount);
        vm.stopPrank();

        // Submit new merkle tree with increased amount for same ID
        vm.startPrank(OWNER);
        (bytes32 newRoot, bytes32[] memory newAliceProof,) =
            _setupMerkleTreeWithDiscount(0, increasedAmount, BASE_DISCOUNT, 0, bobAvailable, BASE_DISCOUNT);
        distributor.submitNewPendingRoot(newRoot, bytes32(0));
        vm.warp(block.timestamp + INITIAL_TIMELOCK);
        distributor.acceptPendingRoot(newRoot);
        vm.stopPrank();

        // Second claim with increased amount
        vm.startPrank(ALICE);
        uint256 additionalAmount = increasedAmount - initialAmount;
        uint256 expectedAdditionalPayment = _getExpectedPayment(true, 0, false);

        uint256 alicePaymentBefore = paymentToken.balanceOf(ALICE);
        uint256 aliceRewardBefore = rewardToken.balanceOf(ALICE);

        // it should emit ClaimRewardTokens event with correct id
        vm.expectEmit(true, true, true, true);
        emit IRewardsEvents.ClaimRewardTokens(
            ALICE, ALICE, 0, additionalAmount, address(paymentToken), expectedAdditionalPayment, BASE_DISCOUNT
        );

        uint256 secondPayment = distributor.claimRewardTokens(
            _getClaimData(increasedAmount, BASE_DISCOUNT, 0, 0),
            newAliceProof,
            additionalAmount,
            address(paymentToken),
            false,
            0,
            ALICE
        );

        // it should return payment amount
        assertEq(secondPayment, expectedAdditionalPayment);

        // it should update purchased amount for user with correct id
        assertEq(distributor.purchasedRewardTokenUser(ALICE, 0), increasedAmount);

        // it should transfer payment tokens from caller
        assertEq(paymentToken.balanceOf(ALICE), alicePaymentBefore - expectedAdditionalPayment);

        // it should transfer reward tokens to onBehalf
        assertEq(rewardToken.balanceOf(ALICE), aliceRewardBefore + additionalAmount);

        vm.stopPrank();
    }

    function test_WhenChangingAmountAfterClaimForSameId_AmountDecreased() external givenValidInputs {
        uint256 initialAmount = aliceAvailable;
        uint256 decreasedAmount = aliceAvailable / 2;

        // First claim with full amount
        vm.startPrank(ALICE);
        paymentToken.approve(address(distributor), type(uint256).max);

        distributor.claimRewardTokens(
            _getClaimData(aliceAvailable, BASE_DISCOUNT, 0, 0),
            aliceProof,
            initialAmount,
            address(paymentToken),
            false,
            0,
            ALICE
        );

        assertEq(distributor.purchasedRewardTokenUser(ALICE, 0), initialAmount);
        vm.stopPrank();

        // Submit new merkle tree with decreased amount for same ID
        vm.startPrank(OWNER);
        (bytes32 newRoot, bytes32[] memory newAliceProof,) =
            _setupMerkleTreeWithDiscount(0, decreasedAmount, BASE_DISCOUNT, 0, bobAvailable, BASE_DISCOUNT);
        distributor.submitNewPendingRoot(newRoot, bytes32(0));
        vm.warp(block.timestamp + INITIAL_TIMELOCK);
        distributor.acceptPendingRoot(newRoot);
        vm.stopPrank();

        vm.startPrank(ALICE);

        // it should revert with AltoRewardsDistributorInvalidInput
        vm.expectRevert(IRewardsErrors.AltoRewardsDistributorInvalidInput.selector);
        distributor.claimRewardTokens(
            _getClaimData(decreasedAmount, BASE_DISCOUNT, 0, 0),
            newAliceProof,
            decreasedAmount,
            address(paymentToken),
            false,
            0,
            ALICE
        );

        vm.stopPrank();
    }

    function test_WhenChangingAmountAfterClaimForSameId_SubmittingMerkleWithDifferentId() external givenValidInputs {
        uint256 initialAmount = aliceAvailable;
        uint256 newIdAmount = aliceAvailable;

        // First claim with ID 0
        vm.startPrank(ALICE);
        paymentToken.approve(address(distributor), type(uint256).max);

        distributor.claimRewardTokens(
            _getClaimData(aliceAvailable, BASE_DISCOUNT, 0, 0),
            aliceProof,
            initialAmount,
            address(paymentToken),
            false,
            0,
            ALICE
        );

        vm.stopPrank();

        assertEq(distributor.purchasedRewardTokenUser(ALICE, 0), initialAmount);
        assertEq(distributor.purchasedRewardTokenUser(ALICE, 1), 0);

        // Submit new merkle tree with different ID (ID 1)
        vm.startPrank(OWNER);
        (bytes32 newRoot, bytes32[] memory newAliceProof,) =
            _setupMerkleTreeWithDiscount(1, newIdAmount, BASE_DISCOUNT, 0, bobAvailable, BASE_DISCOUNT);
        distributor.submitNewPendingRoot(newRoot, bytes32(0));
        vm.warp(block.timestamp + INITIAL_TIMELOCK);
        distributor.acceptPendingRoot(newRoot);
        vm.stopPrank();

        // Claim with different ID (should work)
        vm.startPrank(ALICE);
        uint256 expectedPayment = _getExpectedPayment(true, 0, false);

        uint256 alicePaymentBefore = paymentToken.balanceOf(ALICE);
        uint256 aliceRewardBefore = rewardToken.balanceOf(ALICE);

        assertEq(distributor.purchasedRewardTokenUser(ALICE, 1), 0);

        // it should emit ClaimRewardTokens event with new id
        vm.expectEmit(true, true, true, true);
        emit IRewardsEvents.ClaimRewardTokens(
            ALICE, ALICE, 1, newIdAmount, address(paymentToken), expectedPayment, BASE_DISCOUNT
        );

        uint256 paymentAmountReturn = distributor.claimRewardTokens(
            _getClaimData(newIdAmount, BASE_DISCOUNT, 1, 0),
            newAliceProof,
            newIdAmount,
            address(paymentToken),
            false,
            0,
            ALICE
        );

        // it should return payment amount
        assertEq(paymentAmountReturn, expectedPayment);

        // it should update purchased amount for user with new id
        assertEq(distributor.purchasedRewardTokenUser(ALICE, 1), newIdAmount);

        // it should transfer payment tokens from caller
        assertEq(paymentToken.balanceOf(ALICE), alicePaymentBefore - expectedPayment);

        // it should transfer reward tokens to onBehalf
        assertEq(rewardToken.balanceOf(ALICE), aliceRewardBefore + newIdAmount);

        // Verify both IDs are tracked separately
        assertEq(distributor.purchasedRewardTokenUser(ALICE, 0), initialAmount);
        assertEq(distributor.purchasedRewardTokenUser(ALICE, 1), newIdAmount);

        vm.stopPrank();
    }

    function test_WhenUserHasMultipleClaimsWithDifferentIds() external givenValidInputs {
        vm.startPrank(OWNER);

        // Create leaves for Alice with different IDs
        bytes32 aliceLeaf1 = keccak256(bytes.concat(keccak256(abi.encode(ALICE, aliceAvailable, BASE_DISCOUNT, 1, 0))));
        bytes32 aliceLeaf2 =
            keccak256(bytes.concat(keccak256(abi.encode(ALICE, 2 * aliceAvailable, BASE_DISCOUNT, 2, 0))));

        bytes32 root;
        bytes32[] memory aliceProof1 = new bytes32[](1);
        bytes32[] memory aliceProof2 = new bytes32[](1);

        // Build merkle tree with two Alice leaves
        if (uint256(aliceLeaf1) < uint256(aliceLeaf2)) {
            root = keccak256(abi.encodePacked(aliceLeaf1, aliceLeaf2));
            aliceProof1[0] = aliceLeaf2;
            aliceProof2[0] = aliceLeaf1;
        } else {
            root = keccak256(abi.encodePacked(aliceLeaf2, aliceLeaf1));
            aliceProof1[0] = aliceLeaf2;
            aliceProof2[0] = aliceLeaf1;
        }

        distributor.submitNewPendingRoot(root, bytes32(0));
        vm.warp(block.timestamp + INITIAL_TIMELOCK);
        distributor.acceptPendingRoot(root);
        vm.stopPrank();

        vm.startPrank(ALICE);
        paymentToken.approve(address(distributor), type(uint256).max);

        uint256 expectedPayment1 = _getExpectedPayment(true, 0, false);
        uint256 expectedPayment2 = 2 * _getExpectedPayment(true, 0, false);

        vm.expectEmit(true, true, true, true);
        emit IRewardsEvents.ClaimRewardTokens(
            ALICE, ALICE, 1, aliceAvailable, address(paymentToken), expectedPayment1, BASE_DISCOUNT
        );

        // Claim for ID 1
        uint256 payment1 = distributor.claimRewardTokens(
            _getClaimData(aliceAvailable, BASE_DISCOUNT, 1, 0),
            aliceProof1,
            aliceAvailable,
            address(paymentToken),
            false,
            0,
            ALICE
        );

        assertEq(payment1, expectedPayment1);
        assertEq(distributor.purchasedRewardTokenUser(ALICE, 1), aliceAvailable);

        vm.expectEmit(true, true, true, true);
        emit IRewardsEvents.ClaimRewardTokens(
            ALICE, ALICE, 2, 2 * aliceAvailable, address(paymentToken), expectedPayment2, BASE_DISCOUNT
        );

        // Claim for ID 2
        uint256 payment2 = distributor.claimRewardTokens(
            _getClaimData(2 * aliceAvailable, BASE_DISCOUNT, 2, 0),
            aliceProof2,
            2 * aliceAvailable,
            address(paymentToken),
            false,
            0,
            ALICE
        );

        assertEq(payment2, expectedPayment2);
        assertEq(distributor.purchasedRewardTokenUser(ALICE, 2), 2 * aliceAvailable);

        vm.stopPrank();
    }
}
