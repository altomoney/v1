// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {EndpointV2Mock} from "@layerzerolabs/test-devtools-evm-foundry/contracts/mocks/EndpointV2Mock.sol";

import {AltoConvexCreditLineMarket} from "@alto/lending/credit-market/AltoConvexCreditLineMarket.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {
    IAltoConvexCreditLineMarketErrors,
    IAltoConvexCreditLineMarketEvents,
    ConvexCreditLineInitParams
} from "@alto/lending/interfaces/IAltoConvexCreditLineMarket.sol";
import {IIrm} from "@alto/lending/interfaces/IIrm.sol";
import {IMarketErrors, IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";
import {ILendingOracle, LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {DUSD} from "@alto/tokens/DUSD.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";
import {PAUSE_TYPE, FROZEN_TYPE} from "@alto/utils/Constants.sol";

import {ConvexCreditLineCommon} from "./ConvexCreditLineCommon.t.sol";

contract AltoConvexCreditLineMarketRepayTest is ConvexCreditLineCommon {
    using AssetShareConversionMath for uint256;

    function test_RevertWhenPausedButRemainAvailableWhenFrozen() external {
        _openPosition(1_000 ether, 100 ether);
        _pause(PAUSE_TYPE);
        _assertPausedRevert(PAUSE_TYPE);
        market.repay(1, 0, CREDIT_ACCOUNT);

        _unpause(PAUSE_TYPE);
        _pause(FROZEN_TYPE);
        _repayAssets(USER, 1 ether);
    }

    function test_CreditAccountCheckPrecedesInheritedAmountValidation() external {
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketUnauthorizedAccount.selector);
        market.repay(0, 0, USER);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketUnauthorizedAccount.selector);
        market.repay(1, 1, USER);

        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketUnauthorizedAccount.selector);
        market.repay(1, 0, USER);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketUnauthorizedAccount.selector);
        market.repay(1, 0, address(0));
    }

    function test_InvalidAmountsRollBackAccrualAndAutomaticFeeMinting() external {
        _openPosition(1_000 ether, 100 ether);
        _mockAccrual(5 ether, 19);
        AccountingState memory beforeState = _state();
        uint256 supplyBefore = borrowToken.totalSupply();
        uint256 recipientBalanceBefore = borrowToken.balanceOf(FEE_RECIPIENT);
        (uint256 mintedBefore,) = borrowToken.minterConfig(address(market));

        for (uint256 amount; amount < 2; ++amount) {
            vm.expectCall(address(irm), abi.encodeCall(IIrm.updateInterestRate, (CREDIT_LIMIT, 100 ether)));
            vm.expectCall(address(borrowToken), abi.encodeCall(borrowToken.mint, (FEE_RECIPIENT, 5 ether)));
            vm.prank(USER);
            vm.expectRevert(IMarketErrors.AltoBaseMarketInvalidInput.selector);
            market.repay(amount, amount, CREDIT_ACCOUNT);

            _assertUnchanged(beforeState);
            assertEq(borrowToken.totalSupply(), supplyBefore);
            assertEq(borrowToken.balanceOf(FEE_RECIPIENT), recipientBalanceBefore);
            (uint256 mintedAfter,) = borrowToken.minterConfig(address(market));
            assertEq(mintedAfter, mintedBefore);
        }

        _mockIrmUpdateRevert();
        vm.prank(USER);
        vm.expectRevert(bytes("UPDATE_REVERTED"));
        market.repay(0, 0, CREDIT_ACCOUNT);
        _assertUnchanged(beforeState);
    }

    function test_AmountsAboveDebtOrPositionSharesRevertAtomically() external {
        _openPosition(1_000 ether, 100 ether);
        deal(address(borrowToken), USER, 1_000 ether);
        AccountingState memory beforeState = _state();

        vm.prank(USER);
        vm.expectRevert();
        market.repay(101 ether, 0, CREDIT_ACCOUNT);
        _assertUnchanged(beforeState);

        (, uint128 shares,) = market.position(CREDIT_ACCOUNT);
        vm.prank(USER);
        vm.expectRevert();
        market.repay(0, uint256(shares) + 1, CREDIT_ACCOUNT);
        _assertUnchanged(beforeState);
    }

    function test_RepayByAssetsRoundsSharesDownAndBurnsExactAssets() external {
        _openPosition(1_000 ether, 100 ether);
        _mockAccrual(10 ether, 1);
        market.accrueInterest();
        _mockAccrual(0, 1);
        (uint128 debtAssets, uint128 debtShares) = market.totalBorrowed();
        uint256 expectedShares = uint256(7 ether).convertToSharesDown(debtAssets, debtShares);
        deal(address(borrowToken), USER, 7 ether);

        vm.prank(USER);
        (uint256 assets, uint256 shares) = market.repay(7 ether, 0, CREDIT_ACCOUNT);

        assertEq(assets, 7 ether);
        assertEq(shares, expectedShares);
        assertEq(borrowToken.balanceOf(USER), 0);
    }

    function test_SmallAssetRepayMayBurnWithoutReducingShares() external {
        _openPosition(10 ether, 1);
        _mockAccrual(1 ether, 1);
        market.accrueInterest();
        _mockAccrual(0, 1);
        deal(address(borrowToken), USER, 1);
        (, uint128 sharesBefore,) = market.position(CREDIT_ACCOUNT);

        vm.prank(USER);
        (uint256 assets, uint256 shares) = market.repay(1, 0, CREDIT_ACCOUNT);

        assertEq(assets, 1);
        assertEq(shares, 0);
        (, uint128 sharesAfter,) = market.position(CREDIT_ACCOUNT);
        assertEq(sharesAfter, sharesBefore);
    }

    function test_RepayBySharesRoundsAssetsUpAndFullRepayEnablesWithdrawal() external {
        _openPosition(1_000 ether, 100 ether);
        _mockAccrual(7 ether, 1);
        market.accrueInterest();
        _mockAccrual(0, 1);
        (uint128 debtAssets, uint128 debtShares) = market.totalBorrowed();
        uint256 expectedAssets = uint256(debtShares).convertToAssetsUp(debtAssets, debtShares);
        deal(address(borrowToken), USER, expectedAssets);

        vm.prank(USER);
        (uint256 assets, uint256 shares) = market.repay(0, debtShares, CREDIT_ACCOUNT);

        assertEq(assets, expectedAssets);
        assertEq(shares, debtShares);
        (, uint128 remainingPositionShares,) = market.position(CREDIT_ACCOUNT);
        assertEq(remainingPositionShares, 0);
        vm.prank(CREDIT_ACCOUNT);
        market.removeCollateral(1 ether, CREDIT_ACCOUNT, RECEIVER, "");
    }

    function test_AnyCallerMayRepayButTokensAreBurnedFromThatCaller() external {
        _openPosition(1_000 ether, 100 ether);
        uint256 debtBefore = borrowToken.totalSupply();
        _repayAssets(CREDIT_ACCOUNT, 10 ether);
        assertEq(borrowToken.totalSupply(), debtBefore - 10 ether);

        _repayAssets(USER, 10 ether);
        assertEq(borrowToken.balanceOf(USER), 0);
        assertEq(borrowToken.totalSupply(), debtBefore - 20 ether);

        _repayAssets(DELEGATE, 10 ether);
        assertEq(borrowToken.balanceOf(DELEGATE), 0);
    }

    function test_RepaymentDoesNotReduceHistoricalBadDebt() external {
        _openPosition(1_000 ether, 100 ether);
        oracle.setPrice(100 ether);
        vm.prank(OWNER);
        market.governanceLiquidate(CREDIT_ACCOUNT, false);
        assertEq(market.badDebtAssets(), 100 ether);

        oracle.setPrice(LENDING_ORACLE_PRICE_PRECISION);
        _addCollateral(1_000 ether);
        _mockAccrual(0, 0);
        _borrow(50 ether);
        _repayAssets(USER, 20 ether);

        assertEq(market.badDebtAssets(), 100 ether);
        (uint128 debtAssets,) = market.totalBorrowed();
        assertEq(debtAssets, 30 ether);
    }

    function test_InsufficientPayerBalanceRevertsAtomically() external {
        _openPosition(1_000 ether, 100 ether);
        AccountingState memory beforeState = _state();
        vm.prank(USER);
        vm.expectRevert();
        market.repay(1 ether, 0, CREDIT_ACCOUNT);
        _assertUnchanged(beforeState);
    }

    function test_FullShareRepayCanLeaveVirtualShareAssetDustButUnlockCollateral() external {
        _openPosition(10 ether, 1);
        _mockAccrual(1 ether, 1);
        market.accrueInterest();
        _mockAccrual(0, 1);
        (, uint128 positionShares,) = market.position(CREDIT_ACCOUNT);
        (uint128 debtAssets, uint128 debtShares) = market.totalBorrowed();
        uint256 burnAssets = uint256(positionShares).convertToAssetsUp(debtAssets, debtShares);
        deal(address(borrowToken), USER, burnAssets);

        vm.prank(USER);
        market.repay(0, positionShares, CREDIT_ACCOUNT);

        (uint128 residualAssets, uint128 residualShares) = market.totalBorrowed();
        assertGt(residualAssets, 0);
        assertEq(residualShares, 0);
        (, uint128 remainingPositionShares,) = market.position(CREDIT_ACCOUNT);
        assertEq(remainingPositionShares, 0);
        vm.prank(CREDIT_ACCOUNT);
        market.removeCollateral(1 ether, CREDIT_ACCOUNT, RECEIVER, "");
    }

    function test_BurnFailureRollsBackAtomically() external {
        _openPosition(1_000 ether, 100 ether);
        deal(address(borrowToken), USER, 10 ether);
        AccountingState memory beforeState = _state();
        vm.mockCallRevert(address(borrowToken), borrowToken.burn.selector, bytes("BURN_REVERTED"));

        vm.prank(USER);
        vm.expectRevert(bytes("BURN_REVERTED"));
        market.repay(10 ether, 0, CREDIT_ACCOUNT);
        _assertUnchanged(beforeState);
    }

    function test_AutomaticFeeClaimFailureRollsBackRepaymentAtomically() external {
        _setOpeningFee(0.1 ether);
        _openPosition(1_000 ether, 100 ether);
        _mockAccrual(0, 1);
        (, uint128 positionShares,) = market.position(CREDIT_ACCOUNT);
        (uint128 debtAssets, uint128 debtShares) = market.totalBorrowed();
        uint256 assets = uint256(positionShares).convertToAssetsUp(debtAssets, debtShares);
        deal(address(borrowToken), USER, assets);
        AccountingState memory beforeState = _state();

        vm.mockCallRevert(address(borrowToken), borrowToken.mint.selector, bytes("MINT_REVERTED"));
        vm.prank(USER);
        vm.expectRevert(bytes("MINT_REVERTED"));
        market.repay(0, positionShares, CREDIT_ACCOUNT);
        _assertUnchanged(beforeState);
    }

    function test_InheritedRepaymentAccrualAfterAutomaticClaimLeavesLaterInterestClaimable() external {
        _openPosition(1_000 ether, 100 ether);
        bytes[] memory accrualResults = new bytes[](2);
        accrualResults[0] = abi.encode(5 ether, 19);
        accrualResults[1] = abi.encode(2 ether, 23);
        vm.mockCalls(address(irm), abi.encodeWithSelector(IIrm.updateInterestRate.selector), accrualResults);
        deal(address(borrowToken), USER, 10 ether);

        vm.expectEmit(address(market));
        emit IMarketEvents.AccrueInterest(19, 5 ether, 105 ether, uint128(CREDIT_LIMIT));
        vm.expectEmit(address(market));
        emit IAltoConvexCreditLineMarketEvents.InterestClaimed(FEE_RECIPIENT, 5 ether);
        vm.expectEmit(address(market));
        emit IMarketEvents.AccrueInterest(23, 2 ether, 107 ether, uint128(CREDIT_LIMIT));
        vm.prank(USER);
        market.repay(10 ether, 0, CREDIT_ACCOUNT);
        vm.clearMockedCalls();

        assertEq(borrowToken.balanceOf(FEE_RECIPIENT), 5 ether);
        assertEq(market.claimableFeesAssets(), 2 ether);
        (uint128 debtAssets,) = market.totalBorrowed();
        assertEq(debtAssets, 97 ether);
    }

    function test_ActualDusdAutomaticallyClaimsFeesAndAllowsFullRepayment() external {
        DUSD dusd = new DUSD(address(new EndpointV2Mock(1, address(this))), OWNER);
        ConvexCreditLineInitParams memory params = _validInitParams();
        params.creditMarketInitParams.baseMarketInitParams.borrowToken = address(dusd);
        params.creditMarketInitParams.initialBorrowOpeningFee = 0.1 ether;
        AltoConvexCreditLineMarket dusdMarket = _initialize(params);
        deal(address(collateralToken), CREDIT_ACCOUNT, 1_000 ether);
        vm.startPrank(CREDIT_ACCOUNT);
        collateralToken.approve(address(dusdMarket), type(uint256).max);
        dusdMarket.addCollateral(1_000 ether, CREDIT_ACCOUNT);
        vm.stopPrank();
        vm.startPrank(OWNER);
        dusd.setMinterStatus(address(dusdMarket), true);
        dusd.setMinterCeiling(address(dusdMarket), 1_000 ether);
        vm.stopPrank();
        vm.prank(CREDIT_ACCOUNT);
        dusdMarket.borrow(100 ether, 0, CREDIT_ACCOUNT, CREDIT_ACCOUNT, "");

        vm.prank(CREDIT_ACCOUNT);
        vm.expectRevert(IDUSD.DUSDNotAuthorized.selector);
        dusdMarket.repay(1 ether, 0, CREDIT_ACCOUNT);

        vm.prank(OWNER);
        dusd.setBurnerStatus(address(dusdMarket), true);

        vm.prank(OWNER);
        dusd.setMinterStatus(address(dusdMarket), false);
        vm.prank(CREDIT_ACCOUNT);
        vm.expectRevert(IDUSD.DUSDNotAuthorized.selector);
        dusdMarket.repay(1 ether, 0, CREDIT_ACCOUNT);

        vm.startPrank(OWNER);
        dusd.setMinterStatus(address(dusdMarket), true);
        dusd.setMinterCeiling(address(dusdMarket), 100 ether);
        vm.stopPrank();
        vm.prank(CREDIT_ACCOUNT);
        vm.expectRevert(IDUSD.DUSDInvalidInput.selector);
        dusdMarket.repay(1 ether, 0, CREDIT_ACCOUNT);

        vm.prank(OWNER);
        dusd.setMinterCeiling(address(dusdMarket), 1_000 ether);
        vm.prank(OWNER);
        dusd.pause(PAUSE_TYPE, true);
        vm.prank(CREDIT_ACCOUNT);
        _assertPausedRevert(PAUSE_TYPE);
        dusdMarket.repay(1 ether, 0, CREDIT_ACCOUNT);

        (uint128 debtBeforeRepay,) = dusdMarket.totalBorrowed();
        (uint256 marketMintedBeforeRepay,) = dusd.minterConfig(address(dusdMarket));
        assertEq(debtBeforeRepay, 110 ether);
        assertEq(dusdMarket.claimableFeesAssets(), 10 ether);
        assertEq(dusd.balanceOf(FEE_RECIPIENT), 0);
        assertEq(marketMintedBeforeRepay, 100 ether);

        vm.startPrank(OWNER);
        dusd.pause(PAUSE_TYPE, false);
        dusd.setMinterStatus(OWNER, true);
        dusd.setMinterCeiling(OWNER, 10 ether);
        dusd.mint(CREDIT_ACCOUNT, 10 ether);
        vm.stopPrank();
        (, uint128 positionShares,) = dusdMarket.position(CREDIT_ACCOUNT);

        vm.prank(CREDIT_ACCOUNT);
        (uint256 repaidAssets, uint256 repaidShares) = dusdMarket.repay(0, positionShares, CREDIT_ACCOUNT);

        assertEq(repaidAssets, 110 ether);
        assertEq(repaidShares, positionShares);
        assertEq(dusdMarket.claimableFeesAssets(), 0);
        assertEq(dusd.balanceOf(FEE_RECIPIENT), 10 ether);
        assertEq(dusd.balanceOf(CREDIT_ACCOUNT), 0);

        (uint128 debtAssets,) = dusdMarket.totalBorrowed();
        assertEq(debtAssets, 0);
        (uint256 minted,) = dusd.minterConfig(address(dusdMarket));
        assertEq(minted, 0);
    }

    function test_ValidRepayAccruesFirstPreservesOtherAccountingAndEmits() external {
        _openPosition(1_000 ether, 100 ether);
        bytes[] memory accrualResults = new bytes[](2);
        accrualResults[0] = abi.encode(5 ether, 19);
        accrualResults[1] = abi.encode(0, 19);
        vm.mockCalls(address(irm), abi.encodeWithSelector(IIrm.updateInterestRate.selector), accrualResults);
        deal(address(borrowToken), USER, 10 ether);
        (uint128 supplyAssetsBefore, uint128 supplySharesBefore) = market.totalSupply();
        uint256 stakedBefore = rewardPool.balanceOf(address(market));
        uint256 claimableBefore = market.claimableFeesAssets();
        (,, uint128 collateralBefore) = market.position(CREDIT_ACCOUNT);
        uint256 depositsBefore = booster.depositCalls();
        uint256 rewardClaimsBefore = rewardPool.getRewardCalls();

        vm.mockCallRevert(address(oracle), abi.encodeCall(ILendingOracle.getPrice, ()), "ORACLE_MUST_NOT_BE_CALLED");
        vm.expectEmit(address(market));
        emit IMarketEvents.AccrueInterest(19, 5 ether, 105 ether, uint128(CREDIT_LIMIT));
        vm.expectEmit(address(market));
        emit IAltoConvexCreditLineMarketEvents.InterestClaimed(FEE_RECIPIENT, claimableBefore + 5 ether);
        vm.expectEmit(false, true, false, false, address(market));
        emit IMarketEvents.Repay(USER, CREDIT_ACCOUNT, 0, 0);
        vm.prank(USER);
        (uint256 assets, uint256 shares) = market.repay(10 ether, 0, CREDIT_ACCOUNT);
        vm.clearMockedCalls();

        assertEq(assets, 10 ether);
        assertGt(shares, 0);
        assertEq(market.claimableFeesAssets(), 0);
        assertEq(borrowToken.balanceOf(FEE_RECIPIENT), claimableBefore + 5 ether);
        (,, uint128 collateralAfter) = market.position(CREDIT_ACCOUNT);
        assertEq(collateralAfter, collateralBefore);
        (uint128 supplyAssetsAfter, uint128 supplySharesAfter) = market.totalSupply();
        assertEq(supplyAssetsAfter, supplyAssetsBefore);
        assertEq(supplySharesAfter, supplySharesBefore);
        assertEq(rewardPool.balanceOf(address(market)), stakedBefore);
        assertEq(booster.depositCalls(), depositsBefore);
        assertEq(rewardPool.withdrawCalls(), 0);
        assertEq(rewardPool.getRewardCalls(), rewardClaimsBefore);
    }
}
