// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {EndpointV2Mock} from "@layerzerolabs/test-devtools-evm-foundry/contracts/mocks/EndpointV2Mock.sol";

import {AltoConvexCreditLineMarket} from "@alto/lending/credit-market/AltoConvexCreditLineMarket.sol";
import {
    IAltoConvexCreditLineMarketErrors,
    ConvexCreditLineInitParams
} from "@alto/lending/interfaces/IAltoConvexCreditLineMarket.sol";
import {IIrm} from "@alto/lending/interfaces/IIrm.sol";
import {IMarketErrors, IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";
import {ILendingOracle, LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {DUSD} from "@alto/tokens/DUSD.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";
import {PAUSE_TYPE, FROZEN_TYPE} from "@alto/utils/Constants.sol";
import {MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";

import {ConvexCreditLineCommon} from "./ConvexCreditLineCommon.t.sol";

contract AltoConvexCreditLineMarketBorrowTest is ConvexCreditLineCommon {
    function test_RevertWhenPausedOrFrozen() external {
        _pause(PAUSE_TYPE);
        _assertPausedRevert(PAUSE_TYPE);
        market.borrow(1, 0, CREDIT_ACCOUNT, RECEIVER, "");

        _unpause(PAUSE_TYPE);
        _pause(FROZEN_TYPE);
        _assertPausedRevert(FROZEN_TYPE);
        market.borrow(1, 0, CREDIT_ACCOUNT, RECEIVER, "");
    }

    function test_CreditAccountAndSwapParamsChecksPrecedeBaseValidationAndAuthorization() external {
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketUnauthorizedAccount.selector);
        market.borrow(0, 0, USER, address(0), hex"01");

        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketUnauthorizedAccount.selector);
        market.borrow(0, 0, address(0), address(0), hex"01");

        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketCallbacksUnsupported.selector);
        market.borrow(0, 0, CREDIT_ACCOUNT, address(0), hex"01");
    }

    function test_RevertForInvalidBaseInputsAndUnauthorizedCaller() external {
        vm.startPrank(CREDIT_ACCOUNT);
        vm.expectRevert(IMarketErrors.AltoBaseMarketInvalidInput.selector);
        market.borrow(0, 0, CREDIT_ACCOUNT, RECEIVER, "");
        vm.expectRevert(IMarketErrors.AltoBaseMarketInvalidInput.selector);
        market.borrow(1, 1, CREDIT_ACCOUNT, RECEIVER, "");
        vm.expectRevert(IMarketErrors.AltoBaseMarketInvalidInput.selector);
        market.borrow(1, 0, CREDIT_ACCOUNT, address(0), "");
        vm.stopPrank();

        vm.prank(USER);
        vm.expectRevert(IMarketErrors.AltoBaseMarketUnauthorized.selector);
        market.borrow(1, 0, CREDIT_ACCOUNT, RECEIVER, "");
    }

    function test_AccruesOldDebtBeforeCalculatingDraw() external {
        _openPosition(1_000 ether, 100 ether);
        _mockAccrual(10 ether, 45);
        vm.expectCall(address(irm), abi.encodeCall(IIrm.updateInterestRate, (CREDIT_LIMIT, 100 ether)));
        vm.prank(CREDIT_ACCOUNT);
        (uint256 assets, uint256 shares,) = market.borrow(10 ether, 0, CREDIT_ACCOUNT, RECEIVER, "");

        assertEq(assets, 10 ether);
        assertGt(shares, 0);
        (uint128 debtAssets,) = market.totalBorrowed();
        assertEq(debtAssets, 120 ether);
        assertEq(market.claimableFeesAssets(), 10 ether);
    }

    function test_IrmFailureAndAccruedCapacityFailureRollBackAtomically() external {
        _openPosition(1_000 ether, 100 ether);
        AccountingState memory beforeState = _state();
        _mockIrmUpdateRevert();
        vm.prank(CREDIT_ACCOUNT);
        vm.expectRevert(bytes("UPDATE_REVERTED"));
        market.borrow(1, 0, CREDIT_ACCOUNT, RECEIVER, "");
        _assertUnchanged(beforeState);

        vm.clearMockedCalls();
        _mockAccrual(CREDIT_LIMIT - 100 ether, 1);
        vm.prank(CREDIT_ACCOUNT);
        vm.expectRevert(IMarketErrors.AltoBaseMarketInsufficientMarketLiquidity.selector);
        market.borrow(1, 0, CREDIT_ACCOUNT, RECEIVER, "");
        _assertUnchanged(beforeState);
    }

    function test_BorrowByAssetsRoundsFeeUpAndMintsOnlyNetAssets() external {
        _addCollateral(100 ether);
        _setOpeningFee(0.1 ether);

        vm.prank(CREDIT_ACCOUNT);
        (uint256 grossAssets, uint256 shares, uint256 fee) = market.borrow(101, 0, CREDIT_ACCOUNT, RECEIVER, "");

        assertEq(fee, 11);
        assertEq(grossAssets, 112);
        assertEq(shares, 112_000_000);
        assertEq(borrowToken.balanceOf(RECEIVER), 101);
        assertEq(market.claimableFeesAssets(), 11);
        (, uint128 debtShares,) = market.position(CREDIT_ACCOUNT);
        assertEq(debtShares, shares);
    }

    function test_BorrowBySharesRoundsFeeAndGrossAssetsAsSpecified() external {
        _addCollateral(1_000 ether);
        _setOpeningFee(0.1 ether);

        vm.prank(CREDIT_ACCOUNT);
        (uint256 grossAssets, uint256 shares, uint256 fee) = market.borrow(0, 101_000_001, CREDIT_ACCOUNT, RECEIVER, "");

        assertEq(shares, 111_100_002);
        assertEq(grossAssets, 111);
        assertEq(fee, 11);
        assertEq(borrowToken.balanceOf(RECEIVER), 100);
        assertEq(market.claimableFeesAssets(), 11);
    }

    function test_MinimumPositiveOpeningFeeRoundsUpForAssetAndShareDraws() external {
        _addCollateral(1 ether);
        _setOpeningFee(0.1 ether);

        vm.prank(CREDIT_ACCOUNT);
        (uint256 grossAssets, uint256 shares, uint256 fee) = market.borrow(1, 0, CREDIT_ACCOUNT, RECEIVER, "");

        assertEq(grossAssets, 2);
        assertEq(shares, 2_000_000);
        assertEq(fee, 1);
        assertEq(borrowToken.balanceOf(RECEIVER), 1);
        assertEq(market.claimableFeesAssets(), 1);

        setUp();
        _addCollateral(1 ether);
        vm.prank(CREDIT_ACCOUNT);
        market.borrow(1, 0, CREDIT_ACCOUNT, RECEIVER, "");
        _mockAccrual(199_999, 0);
        market.accrueInterest();
        _mockAccrual(0, 0);
        _setOpeningFee(0.1 ether);
        uint256 feesBefore = market.claimableFeesAssets();
        uint256 receiverBalanceBefore = borrowToken.balanceOf(RECEIVER);

        vm.prank(CREDIT_ACCOUNT);
        (grossAssets, shares, fee) = market.borrow(0, 10, CREDIT_ACCOUNT, RECEIVER, "");

        assertEq(grossAssets, 1);
        assertEq(shares, 11);
        assertEq(fee, 1);
        assertEq(borrowToken.balanceOf(RECEIVER), receiverBalanceBefore);
        assertEq(market.claimableFeesAssets(), feesBefore + 1);
    }

    function test_ZeroOpeningFeeLeavesClaimableFeesUnchanged() external {
        _addCollateral(100 ether);
        uint256 feesBefore = market.claimableFeesAssets();

        vm.prank(CREDIT_ACCOUNT);
        (uint256 grossAssets,, uint256 fee) = market.borrow(10 ether, 0, CREDIT_ACCOUNT, RECEIVER, "");

        assertEq(grossAssets, 10 ether);
        assertEq(fee, 0);
        assertEq(market.claimableFeesAssets(), feesBefore);
    }

    function test_CreditLimitCheckedBeforeOracleAndEqualitySucceeds() external {
        _addCollateral(1_000 ether);
        vm.prank(OWNER);
        market.setCreditLimit(750 ether);
        vm.mockCallRevert(address(oracle), abi.encodeCall(ILendingOracle.getPrice, ()), "ORACLE_REVERTED");

        vm.prank(CREDIT_ACCOUNT);
        vm.expectRevert(IMarketErrors.AltoBaseMarketInsufficientMarketLiquidity.selector);
        market.borrow(750 ether + 1, 0, CREDIT_ACCOUNT, RECEIVER, "");
        vm.clearMockedCalls();

        vm.prank(CREDIT_ACCOUNT);
        market.borrow(750 ether, 0, CREDIT_ACCOUNT, RECEIVER, "");
        (uint128 debtAssets,) = market.totalBorrowed();
        assertEq(debtAssets, 750 ether);
    }

    function test_BadDebtReducesCapacityAndPostMintFailureRollsBackAtomically() external {
        vm.prank(OWNER);
        market.setCreditLimit(200 ether);
        _openPosition(1_000 ether, 100 ether);
        oracle.setPrice(100 ether);
        vm.prank(OWNER);
        market.governanceLiquidate(CREDIT_ACCOUNT, false);

        assertEq(market.badDebtAssets(), 100 ether);

        oracle.setPrice(LENDING_ORACLE_PRICE_PRECISION);
        _addCollateral(1_000 ether);
        _mockAccrual(0, 0);
        _borrow(100 ether);

        (uint128 debtAssets,) = market.totalBorrowed();
        assertEq(debtAssets, 100 ether);
        assertEq(uint256(debtAssets) + market.badDebtAssets(), _creditLimit());

        AccountingState memory beforeState = _state();
        vm.prank(CREDIT_ACCOUNT);
        vm.expectRevert(IMarketErrors.AltoBaseMarketInsufficientMarketLiquidity.selector);
        market.borrow(1, 0, CREDIT_ACCOUNT, RECEIVER, "");

        _assertUnchanged(beforeState);
        assertEq(borrowToken.balanceOf(RECEIVER), 0);
    }

    function test_RevertForZeroOracleInsolvencyAndNoCollateral() external {
        _addCollateral(1_000 ether);
        oracle.setPrice(0);
        vm.prank(CREDIT_ACCOUNT);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketInvalidOraclePrice.selector);
        market.borrow(1, 0, CREDIT_ACCOUNT, RECEIVER, "");

        oracle.setPrice(LENDING_ORACLE_PRICE_PRECISION);
        vm.prank(CREDIT_ACCOUNT);
        vm.expectRevert(IMarketErrors.AltoBaseMarketBorrowingTooMuch.selector);
        market.borrow(750 ether + 1, 0, CREDIT_ACCOUNT, RECEIVER, "");

        (,, uint128 recordedCollateral) = market.position(CREDIT_ACCOUNT);
        vm.store(address(market), bytes32(uint256(_positionSlot(CREDIT_ACCOUNT)) + 1), bytes32(0));
        vm.prank(CREDIT_ACCOUNT);
        vm.expectRevert(IMarketErrors.AltoBaseMarketBorrowingTooMuch.selector);
        market.borrow(1, 0, CREDIT_ACCOUNT, RECEIVER, "");
        assertEq(recordedCollateral, 1_000 ether);
    }

    function test_OracleRevertRollsBackMintAndDebtAccounting() external {
        _addCollateral(1_000 ether);
        AccountingState memory beforeState = _state();
        vm.mockCallRevert(address(oracle), abi.encodeCall(ILendingOracle.getPrice, ()), "ORACLE_REVERTED");

        vm.prank(CREDIT_ACCOUNT);
        vm.expectRevert(bytes("ORACLE_REVERTED"));
        market.borrow(100 ether, 0, CREDIT_ACCOUNT, RECEIVER, "");
        vm.clearMockedCalls();

        _assertUnchanged(beforeState);
        assertEq(borrowToken.totalSupply(), 0);
    }

    function test_MintFailureAndPostMintSolvencyFailureAreAtomic() external {
        _addCollateral(100 ether);
        AccountingState memory beforeState = _state();
        vm.mockCallRevert(address(borrowToken), borrowToken.mint.selector, bytes("MINT_REVERTED"));
        vm.prank(CREDIT_ACCOUNT);
        vm.expectRevert(bytes("MINT_REVERTED"));
        market.borrow(1 ether, 0, CREDIT_ACCOUNT, RECEIVER, "");
        _assertUnchanged(beforeState);

        vm.clearMockedCalls();
        oracle.setPrice(10 ether);
        vm.prank(CREDIT_ACCOUNT);
        vm.expectRevert(IMarketErrors.AltoBaseMarketBorrowingTooMuch.selector);
        market.borrow(20 ether, 0, CREDIT_ACCOUNT, RECEIVER, "");
        _assertUnchanged(beforeState);
    }

    function test_ActualDusdEnforcesMinterCeilingAndPauseRestrictionsAtomically() external {
        DUSD dusd = new DUSD(address(new EndpointV2Mock(1, address(this))), OWNER);
        ConvexCreditLineInitParams memory params = _validInitParams();
        params.creditMarketInitParams.baseMarketInitParams.borrowToken = address(dusd);
        AltoConvexCreditLineMarket dusdMarket = _initialize(params);
        deal(address(collateralToken), CREDIT_ACCOUNT, 1_000 ether);
        vm.startPrank(CREDIT_ACCOUNT);
        collateralToken.approve(address(dusdMarket), type(uint256).max);
        dusdMarket.addCollateral(1_000 ether, CREDIT_ACCOUNT);

        vm.expectRevert(IDUSD.DUSDNotAuthorized.selector);
        dusdMarket.borrow(100 ether, 0, CREDIT_ACCOUNT, CREDIT_ACCOUNT, "");
        vm.stopPrank();
        (uint128 debtAssets, uint128 debtShares) = dusdMarket.totalBorrowed();
        assertEq(debtAssets, 0);
        assertEq(debtShares, 0);

        vm.startPrank(OWNER);
        dusd.setMinterStatus(address(dusdMarket), true);
        dusd.setMinterCeiling(address(dusdMarket), 99 ether);
        vm.stopPrank();
        vm.prank(CREDIT_ACCOUNT);
        vm.expectRevert(IDUSD.DUSDInvalidInput.selector);
        dusdMarket.borrow(100 ether, 0, CREDIT_ACCOUNT, CREDIT_ACCOUNT, "");

        vm.startPrank(OWNER);
        dusd.setMinterCeiling(address(dusdMarket), 100 ether);
        dusd.pause(PAUSE_TYPE, true);
        vm.stopPrank();
        vm.prank(CREDIT_ACCOUNT);
        _assertPausedRevert(PAUSE_TYPE);
        dusdMarket.borrow(100 ether, 0, CREDIT_ACCOUNT, CREDIT_ACCOUNT, "");

        (debtAssets, debtShares) = dusdMarket.totalBorrowed();
        assertEq(debtAssets, 0);
        assertEq(debtShares, 0);
        (uint256 minted,) = dusd.minterConfig(address(dusdMarket));
        assertEq(minted, 0);
    }

    function test_BadDebtReservesActualDusdCapacityForUnclaimedFees() external {
        DUSD dusd = new DUSD(address(new EndpointV2Mock(1, address(this))), OWNER);
        ConvexCreditLineInitParams memory params = _validInitParams();
        params.creditMarketInitParams.baseMarketInitParams.borrowToken = address(dusd);
        params.creditMarketInitParams.creditLimit = 300 ether;
        params.creditMarketInitParams.initialBorrowOpeningFee = MATH_PRECISION;
        AltoConvexCreditLineMarket dusdMarket = _initialize(params);

        vm.startPrank(OWNER);
        dusd.setMinterStatus(address(dusdMarket), true);
        dusd.setMinterCeiling(address(dusdMarket), 300 ether);
        vm.stopPrank();

        deal(address(collateralToken), CREDIT_ACCOUNT, 1_000 ether);
        vm.startPrank(CREDIT_ACCOUNT);
        collateralToken.approve(address(dusdMarket), type(uint256).max);
        dusdMarket.addCollateral(1_000 ether, CREDIT_ACCOUNT);
        dusdMarket.borrow(100 ether, 0, CREDIT_ACCOUNT, CREDIT_ACCOUNT, "");
        vm.stopPrank();

        oracle.setPrice(100 ether);
        vm.prank(OWNER);
        dusdMarket.governanceLiquidate(CREDIT_ACCOUNT, false);
        assertEq(dusdMarket.badDebtAssets(), 200 ether);
        assertEq(dusdMarket.claimableFeesAssets(), 100 ether);

        oracle.setPrice(LENDING_ORACLE_PRICE_PRECISION);
        deal(address(collateralToken), CREDIT_ACCOUNT, 1_000 ether);
        vm.startPrank(CREDIT_ACCOUNT);
        dusdMarket.addCollateral(1_000 ether, CREDIT_ACCOUNT);
        dusdMarket.borrow(50 ether, 0, CREDIT_ACCOUNT, CREDIT_ACCOUNT, "");
        vm.stopPrank();

        (uint128 debtAssets, uint128 debtShares) = dusdMarket.totalBorrowed();
        (uint256 mintedBefore,) = dusd.minterConfig(address(dusdMarket));
        uint256 balanceBefore = dusd.balanceOf(CREDIT_ACCOUNT);
        uint256 feesBefore = dusdMarket.claimableFeesAssets();
        assertEq(debtAssets, 100 ether);
        assertGt(debtShares, 0);
        assertEq(uint256(debtAssets) + dusdMarket.badDebtAssets(), 300 ether);
        assertEq(mintedBefore + feesBefore, 300 ether);

        vm.prank(CREDIT_ACCOUNT);
        vm.expectRevert(IMarketErrors.AltoBaseMarketInsufficientMarketLiquidity.selector);
        dusdMarket.borrow(1 ether, 0, CREDIT_ACCOUNT, CREDIT_ACCOUNT, "");

        (uint128 debtAssetsAfter, uint128 debtSharesAfter) = dusdMarket.totalBorrowed();
        (uint256 mintedAfter,) = dusd.minterConfig(address(dusdMarket));
        assertEq(debtAssetsAfter, debtAssets);
        assertEq(debtSharesAfter, debtShares);
        assertEq(dusd.balanceOf(CREDIT_ACCOUNT), balanceBefore);
        assertEq(dusdMarket.claimableFeesAssets(), feesBefore);
        assertEq(dusdMarket.badDebtAssets(), 200 ether);
        assertEq(mintedAfter, mintedBefore);
    }

    function test_SuccessForCreditAccountAndDelegateWithFullFeeAndExpectedEvents() external {
        _addCollateral(1_000 ether);
        _setOpeningFee(MATH_PRECISION);
        AccountingState memory beforeState = _state();
        address[] memory rewardsBefore = _configuredRewards(2);
        uint256 depositsBefore = booster.depositCalls();
        uint256 withdrawalsBefore = rewardPool.withdrawCalls();
        uint256 rewardClaimsBefore = rewardPool.getRewardCalls();

        vm.expectEmit(address(market));
        emit IMarketEvents.AccrueInterest(BORROW_RATE, 0, 0, uint128(CREDIT_LIMIT));
        vm.expectEmit(address(market));
        emit IMarketEvents.Borrow(DELEGATE, CREDIT_ACCOUNT, RECEIVER, 100 ether, 200_000_000 ether, 100 ether, 0);
        vm.prank(DELEGATE);
        (uint256 assets, uint256 shares, uint256 fee) = market.borrow(100 ether, 0, CREDIT_ACCOUNT, RECEIVER, "");

        assertEq(assets, 200 ether);
        assertEq(shares, 200_000_000 ether);
        assertEq(fee, 100 ether);
        assertEq(borrowToken.balanceOf(RECEIVER), 100 ether);
        assertEq(market.claimableFeesAssets(), 100 ether);
        assertEq(collateralToken.balanceOf(address(market)), 0);
        assertEq(_stakedCollateralAssets(), beforeState.stakedCollateral);
        (uint128 supplyAssets, uint128 supplyShares) = market.totalSupply();
        assertEq(supplyAssets, beforeState.totalSupply.assets);
        assertEq(supplyShares, beforeState.totalSupply.shares);
        (uint128 positionSupplyShares, uint128 positionBorrowShares, uint128 positionCollateral) =
            market.position(CREDIT_ACCOUNT);
        assertEq(positionSupplyShares, beforeState.creditPosition.supplyShares);
        assertEq(positionBorrowShares, shares);
        assertEq(positionCollateral, beforeState.creditPosition.collateralAssets);
        assertEq(market.badDebtAssets(), beforeState.badDebt);
        assertEq(booster.depositCalls(), depositsBefore);
        assertEq(rewardPool.withdrawCalls(), withdrawalsBefore);
        assertEq(rewardPool.getRewardCalls(), rewardClaimsBefore);
        _assertRewardList(rewardsBefore);
        assertEq(primaryRewardToken.balanceOf(REWARD_RECIPIENT), 0);
        assertEq(extraRewardToken.balanceOf(REWARD_RECIPIENT), 0);
    }

    function test_SingleDrawAddsAccruedInterestAndOpeningFeeToClaimableFees() external {
        _openPosition(1_000 ether, 100 ether);
        _setOpeningFee(0.1 ether);
        _mockAccrual(5 ether, 1);
        uint256 beforeFees = market.claimableFeesAssets();

        vm.prank(CREDIT_ACCOUNT);
        (uint256 grossAssets,, uint256 openingFee) = market.borrow(10 ether, 0, CREDIT_ACCOUNT, RECEIVER, "");

        assertEq(grossAssets, 11 ether);
        assertEq(openingFee, 1 ether);
        assertEq(market.claimableFeesAssets(), beforeFees + 6 ether);
    }

    function _positionSlot(address account) private pure returns (bytes32) {
        // `position` is slot 8 in the direct-inheritance layout.
        return keccak256(abi.encode(account, uint256(8)));
    }
}
