// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {SDUSDCommon} from "./SDUSDCommon.t.sol";

contract SDUSD_Redeem_Test is SDUSDCommon {
    function test_RevertWhen_SharesExceedMaxRedeem() public {
        uint256 maximum = vault.maxRedeem(USER);
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxRedeem.selector, USER, maximum + 1, maximum));
        vault.redeem(maximum + 1, RECEIVER, USER);
    }

    function test_RevertWhen_DelegatedCallerHasInsufficientAllowance() public {
        uint256 shares = vault.maxRedeem(USER) / 2;
        vm.prank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, shares));
        vault.redeem(shares, RECEIVER, USER);
    }

    function test_RevertWhen_ReceiverIsZeroAddress() public {
        uint256 shares = vault.maxRedeem(USER) / 2;
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vault.redeem(shares, address(0), USER);
    }

    function test_OwnerRedeemsSharesReturnsRoundedDownAssetsAndEmits() public {
        uint256 shares = vault.maxRedeem(USER) / 2 + 1;
        uint256 expectedAssets = _expectedAssets(shares, Math.Rounding.Floor);
        ExchangeRateSnapshot memory rateBefore = _snapshotExchangeRate();
        uint256 accountedBefore = vault.accountedAssets();
        uint256 usageBefore = vault.depositCapUsage();
        uint256 ownerSharesBefore = vault.balanceOf(USER);
        uint256 receiverAssetsBefore = dusd.balanceOf(RECEIVER);

        vm.expectEmit(true, true, true, true, address(vault));
        emit IERC4626.Withdraw(USER, RECEIVER, USER, expectedAssets, shares);
        vm.prank(USER);
        uint256 returnedAssets = vault.redeem(shares, RECEIVER, USER);

        assertEq(returnedAssets, expectedAssets);
        assertEq(vault.accountedAssets(), accountedBefore - expectedAssets);
        assertEq(vault.depositCapUsage(), usageBefore - expectedAssets);
        assertEq(vault.balanceOf(USER), ownerSharesBefore - shares);
        assertEq(dusd.balanceOf(RECEIVER), receiverAssetsBefore + expectedAssets);
        assertEq(vault.allowance(USER, USER), 0);
        _assertExchangeRateNotDecreased(rateBefore);
    }

    function test_DelegatedRedeemDecreasesFiniteAllowance() public {
        uint256 shares = vault.maxRedeem(USER) / 2;
        vm.prank(USER);
        vault.approve(SPENDER, shares + 1);
        vm.prank(SPENDER);
        vault.redeem(shares, RECEIVER, USER);
        assertEq(vault.allowance(USER, SPENDER), 1);
    }

    function test_DelegatedRedeemLeavesMaximumAllowanceUnchanged() public {
        uint256 shares = vault.maxRedeem(USER) / 2;
        vm.prank(USER);
        vault.approve(SPENDER, type(uint256).max);
        vm.prank(SPENDER);
        vault.redeem(shares, RECEIVER, USER);
        assertEq(vault.allowance(USER, SPENDER), type(uint256).max);
    }

    function test_ZeroShareRedeemDoesNotChangeStateAndEmitsZeroWithdraw() public {
        ExchangeRateSnapshot memory rateBefore = _snapshotExchangeRate();
        uint256 accountedBefore = vault.accountedAssets();
        uint256 usageBefore = vault.depositCapUsage();
        uint256 supplyBefore = vault.totalSupply();
        uint256 ownerSharesBefore = vault.balanceOf(USER);
        uint256 vaultAssetsBefore = dusd.balanceOf(address(vault));
        uint256 receiverAssetsBefore = dusd.balanceOf(RECEIVER);
        vm.expectEmit(true, true, true, true, address(vault));
        emit IERC4626.Withdraw(USER, RECEIVER, USER, 0, 0);
        vm.prank(USER);
        uint256 assets = vault.redeem(0, RECEIVER, USER);

        assertEq(assets, 0);
        assertEq(vault.accountedAssets(), accountedBefore);
        assertEq(vault.depositCapUsage(), usageBefore);
        assertEq(vault.totalSupply(), supplyBefore);
        assertEq(vault.balanceOf(USER), ownerSharesBefore);
        assertEq(dusd.balanceOf(address(vault)), vaultAssetsBefore);
        assertEq(dusd.balanceOf(RECEIVER), receiverAssetsBefore);
        _assertExchangeRateUnchanged(rateBefore);
    }

    function test_RedeemRemainsAvailableWhilePaused() public {
        _pauseVault();
        uint256 shares = vault.maxRedeem(USER) / 2;
        uint256 expectedAssets = vault.previewRedeem(shares);
        vm.prank(USER);
        vault.redeem(shares, RECEIVER, USER);
        assertEq(dusd.balanceOf(RECEIVER), expectedAssets);
    }

    function test_ActiveRewardReturnsOnlyUnlockedShareAndPreservesRewardState() public {
        _notifyRewards(REWARD_AMOUNT);
        vm.warp(vault.periodStart() + REWARD_DURATION / 2);
        ExchangeRateSnapshot memory rateBefore = _snapshotExchangeRate();
        uint256 lockedBefore = vault.lockedRewardsRemaining();
        uint256 rewardAmountBefore = vault.rewardsForPeriod();
        uint256 startBefore = vault.periodStart();
        uint256 finishBefore = vault.rewardPeriodFinish();
        uint256 shares = vault.balanceOf(USER) / 2;
        uint256 usageBefore = vault.depositCapUsage();
        uint256 supplyBefore = vault.totalSupply();
        uint256 expectedAssets =
            Math.mulDiv(shares, vault.accountedAssets() - lockedBefore + 1, supplyBefore + 1, Math.Rounding.Floor);
        uint256 assetsIfLockedRewardsWereIncluded =
            Math.mulDiv(shares, vault.accountedAssets() + 1, supplyBefore + 1, Math.Rounding.Floor);

        assertEq(vault.previewRedeem(shares), expectedAssets);
        assertLt(expectedAssets, assetsIfLockedRewardsWereIncluded);

        vm.prank(USER);
        uint256 returnedAssets = vault.redeem(shares, RECEIVER, USER);

        assertEq(returnedAssets, expectedAssets);
        assertEq(vault.lockedRewardsRemaining(), lockedBefore);
        assertEq(vault.rewardsForPeriod(), rewardAmountBefore);
        assertEq(vault.periodStart(), startBefore);
        assertEq(vault.rewardPeriodFinish(), finishBefore);
        assertEq(vault.depositCapUsage(), usageBefore - returnedAssets);
        assertGe(dusd.balanceOf(address(vault)), lockedBefore);
        _assertExchangeRateNotDecreased(rateBefore);
    }

    function test_RedeemFullOwnerBalanceLeavesPermanentSeedShares() public {
        uint256 shares = vault.balanceOf(USER);
        vm.prank(USER);
        vault.redeem(shares, RECEIVER, USER);
        assertEq(vault.balanceOf(USER), 0);
        assertEq(vault.totalSupply(), SEED_SHARES);
        assertEq(vault.balanceOf(SEED_LOCK), SEED_SHARES);
        assertEq(vault.depositCapUsage(), 0);
    }

    function test_TransferredSharesFreeTheReturnedAssetsWhenRedeemed() public {
        uint256 transferredShares = vault.balanceOf(USER) / 2;
        uint256 usageBefore = vault.depositCapUsage();

        vm.prank(USER);
        vault.transfer(RECEIVER, transferredShares);
        assertEq(vault.depositCapUsage(), usageBefore);

        uint256 expectedAssets = vault.previewRedeem(transferredShares);
        vm.prank(RECEIVER);
        vault.redeem(transferredShares, RECEIVER, RECEIVER);

        assertEq(vault.depositCapUsage(), usageBefore - expectedAssets);
    }

    function test_LaterDepositorAtHigherSharePriceOnlyConsumesHeadroomForRoundingLossOnExit() public {
        _notifyRewards(REWARD_AMOUNT);
        _finishRewardPeriod();

        uint256 usageBeforeDeposit = vault.depositCapUsage();
        uint256 suppliedAssets = 100 ether;
        uint256 mintedShares = _depositFor(RECEIVER, suppliedAssets);
        uint256 usageBeforeRedeem = vault.depositCapUsage();
        vm.prank(RECEIVER);
        uint256 returnedAssets = vault.redeem(mintedShares, RECEIVER, RECEIVER);

        assertEq(vault.depositCapUsage(), usageBeforeRedeem - returnedAssets);
        assertEq(vault.depositCapUsage() - usageBeforeDeposit, suppliedAssets - returnedAssets);
    }

    function test_RawDonationDoesNotIncreaseRedeemedAssets() public {
        uint256 shares = vault.balanceOf(USER) / 2;
        uint256 assetsBefore = vault.previewRedeem(shares);
        ExchangeRateSnapshot memory rateBeforeDonation = _snapshotExchangeRate();
        _donate(100 ether);
        uint256 assetsAfter = vault.previewRedeem(shares);
        assertEq(assetsAfter, assetsBefore);
        _assertExchangeRateUnchanged(rateBeforeDonation);

        ExchangeRateSnapshot memory rateBeforeRedeem = _snapshotExchangeRate();
        vm.prank(USER);
        assertEq(vault.redeem(shares, RECEIVER, USER), assetsBefore);
        _assertExchangeRateNotDecreased(rateBeforeRedeem);
    }
}
