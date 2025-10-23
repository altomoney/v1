// SPDX-License-Identifier: MIT
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
        bytes32 aliceLeaf =
            keccak256(bytes.concat(keccak256(abi.encode(ALICE, aliceAvailable, BASE_DISCOUNT, 0, expirationTimestamp))));
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
            _setupMerkleTreeWithDiscount(aliceAvailable, maxDiscount, bobAvailable, maxDiscount);
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
        bytes32 aliceLeaf =
            keccak256(bytes.concat(keccak256(abi.encode(ALICE, aliceAvailable, BASE_DISCOUNT, 0, expirationTimestamp))));
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
}
