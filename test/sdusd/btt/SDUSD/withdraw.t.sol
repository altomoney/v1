// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {SDUSDCommon} from "./SDUSDCommon.t.sol";

contract SDUSD_Withdraw_Test is SDUSDCommon {
    function test_RevertWhen_AssetsExceedMaxWithdraw() public {
        uint256 maximum = vault.maxWithdraw(USER);
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxWithdraw.selector, USER, maximum + 1, maximum));
        vault.withdraw(maximum + 1, RECEIVER, USER);
    }

    function test_RevertWhen_DelegatedCallerHasInsufficientAllowance() public {
        uint256 assets = vault.maxWithdraw(USER) / 2;
        uint256 shares = vault.previewWithdraw(assets);
        vm.prank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, shares));
        vault.withdraw(assets, RECEIVER, USER);
    }

    function test_RevertWhen_ReceiverIsZeroAddress() public {
        uint256 assets = vault.maxWithdraw(USER) / 2;
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vault.withdraw(assets, address(0), USER);
    }

    function test_OwnerWithdrawsAssetsBurnsRoundedUpSharesAndEmits() public {
        uint256 assets = vault.maxWithdraw(USER) / 2 + 1;
        uint256 expectedShares = _expectedShares(assets, Math.Rounding.Ceil);
        ExchangeRateSnapshot memory rateBefore = _snapshotExchangeRate();
        uint256 accountedBefore = vault.accountedAssets();
        uint256 usageBefore = vault.depositCapUsage();
        uint256 expectedPrincipalRemoved = Math.mulDiv(vault.principalOf(USER), expectedShares, vault.balanceOf(USER));
        uint256 ownerSharesBefore = vault.balanceOf(USER);
        uint256 receiverAssetsBefore = dusd.balanceOf(RECEIVER);

        vm.expectEmit(true, true, true, true, address(vault));
        emit IERC4626.Withdraw(USER, RECEIVER, USER, assets, expectedShares);
        vm.prank(USER);
        uint256 burnedShares = vault.withdraw(assets, RECEIVER, USER);

        assertEq(burnedShares, expectedShares);
        assertEq(vault.accountedAssets(), accountedBefore - assets);
        assertEq(vault.depositCapUsage(), usageBefore - expectedPrincipalRemoved);
        assertEq(vault.balanceOf(USER), ownerSharesBefore - expectedShares);
        assertEq(dusd.balanceOf(RECEIVER), receiverAssetsBefore + assets);
        assertEq(vault.allowance(USER, USER), 0);
        _assertExchangeRateNotDecreased(rateBefore);
    }

    function test_DelegatedWithdrawDecreasesFiniteAllowance() public {
        uint256 assets = vault.maxWithdraw(USER) / 2;
        uint256 shares = vault.previewWithdraw(assets);
        vm.prank(USER);
        vault.approve(SPENDER, shares + 1);
        vm.prank(SPENDER);
        vault.withdraw(assets, RECEIVER, USER);
        assertEq(vault.allowance(USER, SPENDER), 1);
    }

    function test_DelegatedWithdrawLeavesMaximumAllowanceUnchanged() public {
        uint256 assets = vault.maxWithdraw(USER) / 2;
        vm.prank(USER);
        vault.approve(SPENDER, type(uint256).max);
        vm.prank(SPENDER);
        vault.withdraw(assets, RECEIVER, USER);
        assertEq(vault.allowance(USER, SPENDER), type(uint256).max);
    }

    function test_ZeroAssetWithdrawDoesNotChangeStateAndEmitsZeroWithdraw() public {
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
        uint256 shares = vault.withdraw(0, RECEIVER, USER);

        assertEq(shares, 0);
        assertEq(vault.accountedAssets(), accountedBefore);
        assertEq(vault.depositCapUsage(), usageBefore);
        assertEq(vault.totalSupply(), supplyBefore);
        assertEq(vault.balanceOf(USER), ownerSharesBefore);
        assertEq(dusd.balanceOf(address(vault)), vaultAssetsBefore);
        assertEq(dusd.balanceOf(RECEIVER), receiverAssetsBefore);
        _assertExchangeRateUnchanged(rateBefore);
    }

    function test_WithdrawRemainsAvailableWhilePaused() public {
        _pauseVault();
        uint256 assets = vault.maxWithdraw(USER) / 2;
        vm.prank(USER);
        vault.withdraw(assets, RECEIVER, USER);
        assertEq(dusd.balanceOf(RECEIVER), assets);
    }

    function test_ActiveRewardLimitsWithdrawalToUnlockedAssetsAndPreservesRewardState() public {
        _notifyRewards(REWARD_AMOUNT);
        vm.warp(vault.periodStart() + REWARD_DURATION / 2);
        ExchangeRateSnapshot memory rateBefore = _snapshotExchangeRate();
        uint256 lockedBefore = vault.lockedRewardsRemaining();
        uint256 rewardAmountBefore = vault.rewardsForPeriod();
        uint256 startBefore = vault.periodStart();
        uint256 finishBefore = vault.rewardPeriodFinish();
        uint256 maximum = vault.maxWithdraw(USER);
        uint256 shares = vault.previewWithdraw(maximum);
        uint256 usageBefore = vault.depositCapUsage();
        uint256 expectedPrincipalRemoved = Math.mulDiv(vault.principalOf(USER), shares, vault.balanceOf(USER));
        assertEq(maximum, vault.convertToAssets(vault.balanceOf(USER)));
        assertGt(maximum, expectedPrincipalRemoved);

        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxWithdraw.selector, USER, maximum + 1, maximum));
        vault.withdraw(maximum + 1, RECEIVER, USER);

        vm.prank(USER);
        vault.withdraw(maximum, RECEIVER, USER);

        assertEq(vault.lockedRewardsRemaining(), lockedBefore);
        assertEq(vault.rewardsForPeriod(), rewardAmountBefore);
        assertEq(vault.periodStart(), startBefore);
        assertEq(vault.rewardPeriodFinish(), finishBefore);
        assertEq(vault.depositCapUsage(), usageBefore - expectedPrincipalRemoved);
        assertEq(dusd.balanceOf(RECEIVER), maximum);
        _assertExchangeRateNotDecreased(rateBefore);
    }

    function test_WithdrawAllAvailableAssetsLeavesPermanentSeedShares() public {
        uint256 maximum = vault.maxWithdraw(USER);
        vm.prank(USER);
        vault.withdraw(maximum, RECEIVER, USER);
        assertEq(vault.balanceOf(USER), 0);
        assertEq(vault.totalSupply(), SEED_SHARES);
        assertEq(vault.balanceOf(SEED_LOCK), SEED_SHARES);
        assertEq(vault.depositCapUsage(), 0);
    }

    function test_RawDonationDoesNotIncreaseWithdrawableAssets() public {
        uint256 maximumBefore = vault.maxWithdraw(USER);
        ExchangeRateSnapshot memory rateBeforeDonation = _snapshotExchangeRate();
        _donate(100 ether);

        assertEq(vault.maxWithdraw(USER), maximumBefore);
        _assertExchangeRateUnchanged(rateBeforeDonation);

        ExchangeRateSnapshot memory rateBeforeWithdraw = _snapshotExchangeRate();
        vm.prank(USER);
        vault.withdraw(maximumBefore / 2, RECEIVER, USER);
        _assertExchangeRateNotDecreased(rateBeforeWithdraw);
    }
}
