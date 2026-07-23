// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {SDUSDCommon} from "./SDUSDCommon.t.sol";

contract SDUSD_Mint_Test is SDUSDCommon {
    function test_RevertWhen_Paused() public {
        _pauseVault();
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSE_TYPE));
        vault.mint(1, USER);
    }

    function test_RevertWhen_ReceiverIsZeroAddress() public {
        uint256 assets = vault.previewMint(1 ether);
        dusd.mint(USER, assets);
        vm.startPrank(USER);
        dusd.approve(address(vault), assets);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vault.mint(1 ether, address(0));
        vm.stopPrank();
    }

    function test_RevertWhen_AllowanceIsInsufficientAndLeavesStateUnchanged() public {
        uint256 assets = vault.previewMint(1 ether);
        dusd.mint(USER, assets);
        uint256 accountedBefore = vault.accountedAssets();
        uint256 supplyBefore = vault.totalSupply();

        vm.prank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(vault), 0, assets)
        );
        vault.mint(1 ether, USER);

        assertEq(vault.accountedAssets(), accountedBefore);
        assertEq(vault.totalSupply(), supplyBefore);
    }

    function test_RevertWhen_BalanceIsInsufficientAndLeavesStateUnchanged() public {
        uint256 assets = vault.previewMint(1 ether);
        uint256 accountedBefore = vault.accountedAssets();
        uint256 supplyBefore = vault.totalSupply();
        vm.prank(USER);
        dusd.approve(address(vault), assets);

        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, USER, 0, assets));
        vault.mint(1 ether, USER);

        assertEq(vault.accountedAssets(), accountedBefore);
        assertEq(vault.totalSupply(), supplyBefore);
    }

    function test_EmptyVaultMintsAllRequestedSharesToReceiver() public {
        _useEmptyVault();
        uint256 shares = SEED_SHARES + 1;
        uint256 requiredAssets = vault.previewMint(shares);
        assertEq(requiredAssets, _expectedAssets(shares, Math.Rounding.Ceil));
        ExchangeRateSnapshot memory exchangeRateBefore = _snapshotExchangeRate();
        dusd.mint(USER, requiredAssets);

        vm.startPrank(USER);
        dusd.approve(address(vault), requiredAssets);
        vm.expectEmit(true, true, false, true, address(vault));
        emit IERC4626.Deposit(USER, USER, requiredAssets, shares);
        uint256 returnedAssets = vault.mint(shares, USER);
        vm.stopPrank();

        assertEq(returnedAssets, requiredAssets);
        assertEq(dusd.balanceOf(address(vault)), requiredAssets);
        assertEq(vault.accountedAssets(), requiredAssets);
        assertEq(vault.balanceOf(USER), shares);
        assertEq(vault.balanceOf(SEED_LOCK), 0);
        assertEq(vault.totalSupply(), shares);
        _assertExchangeRateNotDecreased(exchangeRateBefore);
    }

    function test_SubsequentMintRoundsUpTransfersAssetsMintsSharesAndEmits() public {
        uint256 shares = 10 ether + 1;
        uint256 requiredAssets = vault.previewMint(shares);
        assertEq(requiredAssets, _expectedAssets(shares, Math.Rounding.Ceil));
        uint256 accountedBefore = vault.accountedAssets();
        uint256 seedBefore = vault.balanceOf(SEED_LOCK);
        uint256 vaultDusdBefore = dusd.balanceOf(address(vault));
        ExchangeRateSnapshot memory exchangeRateBefore = _snapshotExchangeRate();
        dusd.mint(USER, requiredAssets);
        uint256 userDusdBefore = dusd.balanceOf(USER);

        vm.startPrank(USER);
        dusd.approve(address(vault), requiredAssets);
        vm.expectEmit(true, true, false, true, address(vault));
        emit IERC4626.Deposit(USER, RECEIVER, requiredAssets, shares);
        uint256 returnedAssets = vault.mint(shares, RECEIVER);
        vm.stopPrank();

        assertEq(returnedAssets, requiredAssets);
        assertEq(dusd.balanceOf(USER), userDusdBefore - requiredAssets);
        assertEq(dusd.balanceOf(address(vault)), vaultDusdBefore + requiredAssets);
        assertEq(vault.accountedAssets(), accountedBefore + requiredAssets);
        assertEq(vault.balanceOf(RECEIVER), shares);
        assertEq(vault.balanceOf(SEED_LOCK), seedBefore);
        _assertExchangeRateNotDecreased(exchangeRateBefore);
    }

    function test_ZeroShareMintDoesNotChangeStateAndEmitsZeroDeposit() public {
        uint256 accountedBefore = vault.accountedAssets();
        uint256 supplyBefore = vault.totalSupply();
        uint256 callerDusdBefore = dusd.balanceOf(address(this));
        uint256 vaultDusdBefore = dusd.balanceOf(address(vault));
        uint256 receiverSharesBefore = vault.balanceOf(RECEIVER);
        uint256 seedSharesBefore = vault.balanceOf(SEED_LOCK);
        ExchangeRateSnapshot memory exchangeRateBefore = _snapshotExchangeRate();
        vm.expectEmit(true, true, false, true, address(vault));
        emit IERC4626.Deposit(address(this), RECEIVER, 0, 0);
        uint256 assets = vault.mint(0, RECEIVER);

        assertEq(assets, 0);
        assertEq(vault.accountedAssets(), accountedBefore);
        assertEq(vault.totalSupply(), supplyBefore);
        assertEq(dusd.balanceOf(address(this)), callerDusdBefore);
        assertEq(dusd.balanceOf(address(vault)), vaultDusdBefore);
        assertEq(vault.balanceOf(RECEIVER), receiverSharesBefore);
        assertEq(vault.balanceOf(SEED_LOCK), seedSharesBefore);
        _assertExchangeRateUnchanged(exchangeRateBefore);
    }

    function test_PricesMintUsingOnlyUnlockedAssetsDuringRewardPeriod() public {
        _notifyRewards(REWARD_AMOUNT);
        vm.warp(vault.periodStart() + REWARD_DURATION / 2);
        uint256 shares = 10 ether;
        uint256 expectedAssets = _expectedAssets(shares, Math.Rounding.Ceil);
        ExchangeRateSnapshot memory exchangeRateBefore = _snapshotExchangeRate();

        uint256 returned = _mintFor(RECEIVER, shares);

        assertEq(returned, expectedAssets);
        assertEq(vault.balanceOf(RECEIVER), shares);
        _assertExchangeRateNotDecreased(exchangeRateBefore);
    }

    function test_IgnoresRawDonationWhenCalculatingRequiredAssets() public {
        uint256 shares = 10 ether;
        uint256 previewBefore = vault.previewMint(shares);
        ExchangeRateSnapshot memory beforeDonation = _snapshotExchangeRate();
        _donate(100 ether);
        uint256 previewAfter = vault.previewMint(shares);

        assertEq(previewAfter, previewBefore);
        _assertExchangeRateUnchanged(beforeDonation);

        ExchangeRateSnapshot memory beforeMint = _snapshotExchangeRate();
        assertEq(_mintFor(RECEIVER, shares), previewBefore);
        _assertExchangeRateNotDecreased(beforeMint);
    }
}
