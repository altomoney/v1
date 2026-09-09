// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {EndpointV2Mock} from "@layerzerolabs/test-devtools-evm-foundry/contracts/mocks/EndpointV2Mock.sol";

import {AltoConvexCreditLineMarket} from "@alto/lending/credit-market/AltoConvexCreditLineMarket.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {IAltoCreditMarketErrors} from "@alto/lending/interfaces/IAltoCreditMarket.sol";
import {ConvexCreditLineInitParams} from "@alto/lending/interfaces/IAltoConvexCreditLine.sol";
import {IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";
import {ILendingOracle} from "@alto/oracles/interfaces/IOracle.sol";
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

    function test_InvalidAmountSelectionPrecedesCreditAccountCheck() external {
        vm.expectRevert(IAltoCreditMarketErrors.AltoCreditMarketInvalidInput.selector);
        market.repay(0, 0, USER);
        vm.expectRevert(IAltoCreditMarketErrors.AltoCreditMarketInvalidInput.selector);
        market.repay(1, 1, USER);

        vm.expectRevert(IAltoCreditMarketErrors.AltoCreditMarketUnauthorizedAccount.selector);
        market.repay(1, 0, USER);
        vm.expectRevert(IAltoCreditMarketErrors.AltoCreditMarketUnauthorizedAccount.selector);
        market.repay(1, 0, address(0));
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

    function test_BurnFailureAndReentrancyRollBackAtomically() external {
        _openPosition(1_000 ether, 100 ether);
        deal(address(borrowToken), USER, 10 ether);
        AccountingState memory beforeState = _state();
        borrowToken.setMintBurnFailure(false, true);

        vm.prank(USER);
        vm.expectRevert(bytes("BURN_REVERTED"));
        market.repay(10 ether, 0, CREDIT_ACCOUNT);
        _assertUnchanged(beforeState);

        borrowToken.setMintBurnFailure(false, false);
        borrowToken.setCallback(address(market), abi.encodeCall(market.repay, (1, 0, CREDIT_ACCOUNT)), 2);
        vm.prank(USER);
        vm.expectRevert(ReentrancyGuardUpgradeable.ReentrancyGuardReentrantCall.selector);
        market.repay(10 ether, 0, CREDIT_ACCOUNT);
        _assertUnchanged(beforeState);
    }

    function test_ActualDusdEnforcesBurnerMinterAccountingAndPauseRestrictions() external {
        DUSD dusd = new DUSD(address(new EndpointV2Mock(1, address(this))), OWNER);
        ConvexCreditLineInitParams memory params = _validInitParams();
        params.creditMarketInitParams.baseMarketInitParams.borrowToken = address(dusd);
        AltoConvexCreditLineMarket dusdMarket = _initialize(params);
        FixedRateIrm dusdIrm = FixedRateIrm(dusdMarket.irm());
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
        _mockAccrual(dusdIrm, 10 ether, 1);
        dusdMarket.accrueInterest();
        _mockAccrual(dusdIrm, 0, 1);
        vm.startPrank(OWNER);
        dusd.setMinterStatus(OWNER, true);
        dusd.setMinterCeiling(OWNER, 10 ether);
        dusd.mint(CREDIT_ACCOUNT, 10 ether);
        vm.stopPrank();
        (, uint128 positionShares,) = dusdMarket.position(CREDIT_ACCOUNT);

        vm.prank(CREDIT_ACCOUNT);
        vm.expectRevert(IDUSD.DUSDInvalidInput.selector);
        dusdMarket.repay(0, positionShares, CREDIT_ACCOUNT);

        vm.prank(OWNER);
        dusd.pause(PAUSE_TYPE, true);
        vm.prank(CREDIT_ACCOUNT);
        _assertPausedRevert(PAUSE_TYPE);
        dusdMarket.repay(1 ether, 0, CREDIT_ACCOUNT);

        (uint128 debtAssets,) = dusdMarket.totalBorrowed();
        assertEq(debtAssets, 110 ether);
        (uint256 minted,) = dusd.minterConfig(address(dusdMarket));
        assertEq(minted, 100 ether);
    }

    function test_ValidRepayAccruesFirstPreservesOtherAccountingAndEmits() external {
        _openPosition(1_000 ether, 100 ether);
        _mockAccrual(5 ether, 19);
        deal(address(borrowToken), USER, 10 ether);
        uint256 stakedBefore = market.stakedCollateralAssets();
        uint256 claimableBefore = market.claimableFeesAssets();
        (,, uint128 collateralBefore) = market.position(CREDIT_ACCOUNT);

        vm.mockCallRevert(address(oracle), abi.encodeCall(ILendingOracle.getPrice, ()), "ORACLE_MUST_NOT_BE_CALLED");
        vm.expectEmit(address(market));
        emit IMarketEvents.AccrueInterest(19, 5 ether, 105 ether, uint128(CREDIT_LIMIT));
        vm.expectEmit(false, true, false, false, address(market));
        emit IMarketEvents.Repay(USER, CREDIT_ACCOUNT, 0, 0);
        vm.prank(USER);
        (uint256 assets, uint256 shares) = market.repay(10 ether, 0, CREDIT_ACCOUNT);
        vm.clearMockedCalls();

        assertEq(assets, 10 ether);
        assertGt(shares, 0);
        assertEq(market.claimableFeesAssets(), claimableBefore + 5 ether);
        (,, uint128 collateralAfter) = market.position(CREDIT_ACCOUNT);
        assertEq(collateralAfter, collateralBefore);
        assertEq(market.stakedCollateralAssets(), stakedBefore);
        assertEq(rewardPool.withdrawCalls(), 0);
    }
}
