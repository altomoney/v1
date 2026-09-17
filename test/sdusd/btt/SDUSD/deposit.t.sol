// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {ISDUSDVaultErrors} from "@alto/sdusd/interfaces/ISDUSDVault.sol";
import {SDUSDCommon} from "./SDUSDCommon.t.sol";

contract SDUSD_Deposit_Test is SDUSDCommon {
    function test_RevertWhen_Paused() public {
        _pauseVault();
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSE_TYPE));
        vault.deposit(1, USER);
    }

    function test_RevertWhen_ReceiverIsZeroAddress() public {
        uint256 capUsageBefore = vault.depositCapUsage();
        dusd.mint(USER, 1 ether);
        vm.startPrank(USER);
        dusd.approve(address(vault), 1 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vault.deposit(1 ether, address(0));
        vm.stopPrank();

        assertEq(vault.depositCapUsage(), capUsageBefore);
    }

    function test_RevertWhen_AllowanceIsInsufficientAndLeavesStateUnchanged() public {
        dusd.mint(USER, 1 ether);
        uint256 accountedBefore = vault.accountedAssets();
        uint256 capUsageBefore = vault.depositCapUsage();
        uint256 supplyBefore = vault.totalSupply();

        vm.prank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(vault), 0, 1 ether)
        );
        vault.deposit(1 ether, USER);

        assertEq(vault.accountedAssets(), accountedBefore);
        assertEq(vault.depositCapUsage(), capUsageBefore);
        assertEq(vault.totalSupply(), supplyBefore);
    }

    function test_RevertWhen_BalanceIsInsufficientAndLeavesStateUnchanged() public {
        uint256 accountedBefore = vault.accountedAssets();
        uint256 capUsageBefore = vault.depositCapUsage();
        uint256 supplyBefore = vault.totalSupply();
        vm.prank(USER);
        dusd.approve(address(vault), 1 ether);

        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, USER, 0, 1 ether));
        vault.deposit(1 ether, USER);

        assertEq(vault.accountedAssets(), accountedBefore);
        assertEq(vault.depositCapUsage(), capUsageBefore);
        assertEq(vault.totalSupply(), supplyBefore);
    }

    function test_RevertWhen_AssetsExceedRemainingCapAndLeavesStateUnchanged() public {
        uint256 capUsageBefore = vault.depositCapUsage();
        uint256 accountedBefore = vault.accountedAssets();
        uint256 supplyBefore = vault.totalSupply();
        uint256 headroom = 10 ether;
        _setDepositCap(capUsageBefore + headroom);
        dusd.mint(USER, headroom + 1);

        vm.startPrank(USER);
        dusd.approve(address(vault), headroom + 1);
        vm.expectRevert(
            abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxDeposit.selector, RECEIVER, headroom + 1, headroom)
        );
        vault.deposit(headroom + 1, RECEIVER);
        vm.stopPrank();

        assertEq(vault.depositCapUsage(), capUsageBefore);
        assertEq(vault.accountedAssets(), accountedBefore);
        assertEq(vault.totalSupply(), supplyBefore);
        assertEq(vault.balanceOf(RECEIVER), 0);
    }

    function test_EmptyVaultMintsAllPreviewedSharesToReceiver() public {
        _useEmptyVault();
        uint256 assets = SEED_SHARES;
        uint256 preview = vault.previewDeposit(assets);
        ExchangeRateSnapshot memory exchangeRateBefore = _snapshotExchangeRate();
        dusd.mint(USER, assets);
        vm.startPrank(USER);
        dusd.approve(address(vault), assets);
        vm.expectEmit(true, true, false, true, address(vault));
        emit IERC4626.Deposit(USER, USER, assets, preview);
        uint256 returnedShares = vault.deposit(assets, USER);
        vm.stopPrank();

        assertEq(dusd.balanceOf(USER), 0);
        assertEq(dusd.balanceOf(address(vault)), assets);
        assertEq(vault.accountedAssets(), assets);
        assertEq(vault.depositCapUsage(), 0);
        assertEq(vault.balanceOf(USER), preview);
        assertEq(vault.balanceOf(SEED_LOCK), 0);
        assertEq(vault.totalSupply(), preview);
        assertEq(returnedShares, preview);
        _assertExchangeRateNotDecreased(exchangeRateBefore);
    }

    function test_SubsequentDepositTransfersAssetsMintsPreviewedSharesAndEmits() public {
        uint256 assets = 10 ether;
        uint256 preview = vault.previewDeposit(assets);
        uint256 accountedBefore = vault.accountedAssets();
        uint256 capUsageBefore = vault.depositCapUsage();
        uint256 userSharesBefore = vault.balanceOf(USER);
        uint256 seedBefore = vault.balanceOf(SEED_LOCK);
        uint256 vaultDusdBefore = dusd.balanceOf(address(vault));
        ExchangeRateSnapshot memory exchangeRateBefore = _snapshotExchangeRate();
        dusd.mint(USER, assets);

        vm.startPrank(USER);
        dusd.approve(address(vault), assets);
        vm.expectEmit(true, true, false, true, address(vault));
        emit IERC4626.Deposit(USER, RECEIVER, assets, preview);
        uint256 returnedShares = vault.deposit(assets, RECEIVER);
        vm.stopPrank();

        assertEq(dusd.balanceOf(USER), 0);
        assertEq(dusd.balanceOf(address(vault)), vaultDusdBefore + assets);
        assertEq(vault.accountedAssets(), accountedBefore + assets);
        assertEq(vault.depositCapUsage(), capUsageBefore + assets);
        assertEq(vault.balanceOf(RECEIVER), preview);
        assertEq(vault.balanceOf(USER), userSharesBefore);
        assertEq(vault.balanceOf(SEED_LOCK), seedBefore);
        assertEq(returnedShares, preview);
        _assertExchangeRateNotDecreased(exchangeRateBefore);
    }

    function test_ZeroAssetDepositDoesNotChangeStateAndEmitsZeroDeposit() public {
        uint256 accountedBefore = vault.accountedAssets();
        uint256 capUsageBefore = vault.depositCapUsage();
        uint256 supplyBefore = vault.totalSupply();
        uint256 callerDusdBefore = dusd.balanceOf(address(this));
        uint256 vaultDusdBefore = dusd.balanceOf(address(vault));
        uint256 receiverSharesBefore = vault.balanceOf(RECEIVER);
        uint256 seedSharesBefore = vault.balanceOf(SEED_LOCK);
        ExchangeRateSnapshot memory exchangeRateBefore = _snapshotExchangeRate();
        vm.expectEmit(true, true, false, true, address(vault));
        emit IERC4626.Deposit(address(this), RECEIVER, 0, 0);
        uint256 shares = vault.deposit(0, RECEIVER);

        assertEq(shares, 0);
        assertEq(vault.accountedAssets(), accountedBefore);
        assertEq(vault.depositCapUsage(), capUsageBefore);
        assertEq(vault.totalSupply(), supplyBefore);
        assertEq(dusd.balanceOf(address(this)), callerDusdBefore);
        assertEq(dusd.balanceOf(address(vault)), vaultDusdBefore);
        assertEq(vault.balanceOf(RECEIVER), receiverSharesBefore);
        assertEq(vault.balanceOf(SEED_LOCK), seedSharesBefore);
        _assertExchangeRateUnchanged(exchangeRateBefore);
    }

    function test_RevertWhen_NonZeroAssetsRoundDownToZeroSharesAndLeavesStateUnchanged() public {
        _notifyRewards(REWARD_AMOUNT);
        _finishRewardPeriod();

        uint256 assets = 1;
        assertEq(vault.previewDeposit(assets), 0);

        uint256 accountedBefore = vault.accountedAssets();
        uint256 capUsageBefore = vault.depositCapUsage();
        uint256 supplyBefore = vault.totalSupply();
        uint256 vaultDusdBefore = dusd.balanceOf(address(vault));
        uint256 receiverSharesBefore = vault.balanceOf(RECEIVER);
        dusd.mint(USER, assets);

        vm.startPrank(USER);
        dusd.approve(address(vault), assets);
        vm.expectRevert(ISDUSDVaultErrors.SDUSDZeroShares.selector);
        vault.deposit(assets, RECEIVER);
        vm.stopPrank();

        assertEq(dusd.balanceOf(USER), assets);
        assertEq(dusd.balanceOf(address(vault)), vaultDusdBefore);
        assertEq(vault.accountedAssets(), accountedBefore);
        assertEq(vault.depositCapUsage(), capUsageBefore);
        assertEq(vault.totalSupply(), supplyBefore);
        assertEq(vault.balanceOf(RECEIVER), receiverSharesBefore);
    }

    function test_PricesDepositUsingOnlyUnlockedAssetsDuringRewardPeriod() public {
        _notifyRewards(REWARD_AMOUNT);
        vm.warp(vault.periodStart() + REWARD_DURATION / 2);
        uint256 assets = 10 ether;
        uint256 expected = _expectedShares(assets, Math.Rounding.Floor);
        uint256 capUsageBefore = vault.depositCapUsage();
        ExchangeRateSnapshot memory exchangeRateBefore = _snapshotExchangeRate();

        uint256 returned = _depositFor(RECEIVER, assets);

        assertEq(returned, expected);
        assertEq(vault.balanceOf(RECEIVER), expected);
        assertEq(vault.depositCapUsage(), capUsageBefore + assets);
        _assertExchangeRateNotDecreased(exchangeRateBefore);
    }

    function test_DepositExactlyRemainingHeadroomConsumesCap() public {
        uint256 usageBefore = vault.depositCapUsage();
        uint256 headroom = 10 ether;
        _setDepositCap(usageBefore + headroom);

        _depositFor(RECEIVER, headroom);

        assertEq(vault.depositCapUsage(), vault.depositCap());
        assertEq(vault.maxDeposit(USER), 0);
        assertEq(vault.maxMint(USER), 0);
    }

    function test_IgnoresRawDonationWhenCalculatingDepositShares() public {
        uint256 assets = 10 ether;
        uint256 previewBefore = vault.previewDeposit(assets);
        ExchangeRateSnapshot memory beforeDonation = _snapshotExchangeRate();
        _donate(100 ether);
        uint256 previewAfter = vault.previewDeposit(assets);

        assertEq(previewAfter, previewBefore);
        _assertExchangeRateUnchanged(beforeDonation);

        ExchangeRateSnapshot memory beforeDeposit = _snapshotExchangeRate();
        assertEq(_depositFor(RECEIVER, assets), previewBefore);
        _assertExchangeRateNotDecreased(beforeDeposit);
    }
}
