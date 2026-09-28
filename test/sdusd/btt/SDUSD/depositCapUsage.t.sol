// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {SDUSDCommon} from "./SDUSDCommon.t.sol";

/// @dev Shared custody with separate user balances, reproducing the principal averaging attack path.
contract AssetCapSharePool {
    using SafeERC20 for IERC20;

    IERC20 internal immutable shares;
    mapping(address => uint256) public balanceOf;

    constructor(IERC20 shares_) {
        shares = shares_;
    }

    function deposit(uint256 amount) external {
        balanceOf[msg.sender] += amount;
        shares.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint256 amount) external {
        balanceOf[msg.sender] -= amount;
        shares.safeTransfer(msg.sender, amount);
    }
}

contract SDUSD_DepositCapUsage_Test is SDUSDCommon {
    function test_ExactInitialSeedMintIsExempt() public {
        _useEmptyVault();
        dusd.mint(USER, SEED_SHARES);
        vm.startPrank(USER);
        dusd.approve(address(vault), SEED_SHARES);
        vault.mint(SEED_SHARES, SEED_LOCK);
        vm.stopPrank();

        assertEq(vault.totalAssets(), SEED_SHARES);
        assertEq(vault.depositCapUsage(), 0);
        assertEq(vault.maxDeposit(USER), INITIAL_DEPOSIT_CAP);
    }

    function test_LaterLockDepositsAndTransfersDoNotExpandSeedExemption() public {
        uint256 usageBefore = vault.depositCapUsage();
        dusd.mint(address(this), SEED_SHARES);
        dusd.approve(address(vault), SEED_SHARES);
        vault.deposit(SEED_SHARES, SEED_LOCK);
        uint256 shares = vault.balanceOf(USER);
        vm.prank(USER);
        vault.transfer(SEED_LOCK, shares);

        assertEq(vault.depositCapUsage(), usageBefore + SEED_SHARES);
        assertEq(vault.maxDeposit(USER), INITIAL_DEPOSIT_CAP - usageBefore - SEED_SHARES);
    }

    function test_RewardsCanReleaseAboveCapAndNewPeriodsRemainAvailable() public {
        uint256 usageBefore = vault.depositCapUsage();
        _setDepositCap(usageBefore + REWARD_AMOUNT / 2);
        _notifyRewards(REWARD_AMOUNT);
        assertEq(vault.depositCapUsage(), usageBefore);
        assertEq(vault.maxDeposit(USER), REWARD_AMOUNT / 2);

        vm.warp(vault.periodStart() + REWARD_DURATION / 2);
        assertEq(vault.depositCapUsage(), vault.depositCap());
        assertEq(vault.maxDeposit(USER), 0);
        assertEq(vault.maxMint(USER), 0);

        _finishRewardPeriod();
        assertEq(vault.depositCapUsage(), usageBefore + REWARD_AMOUNT);
        assertGt(vault.depositCapUsage(), vault.depositCap());
        _notifyRewards(REWARD_AMOUNT);
        _finishRewardPeriod();
        assertEq(vault.depositCapUsage(), usageBefore + 2 * REWARD_AMOUNT);
        assertEq(vault.maxDeposit(USER), 0);
        assertEq(vault.maxMint(USER), 0);
    }

    function test_WithdrawalsOnlyReopenHeadroomOnceAssetsFallBelowCap() public {
        _depositFor(USER, 99 ether);
        _setDepositCap(150 ether);
        _notifyRewards(REWARD_AMOUNT);
        _finishRewardPeriod();
        assertEq(vault.depositCapUsage(), 170 ether);

        vm.prank(USER);
        vault.withdraw(10 ether, USER, USER);
        assertEq(vault.depositCapUsage(), 160 ether);
        assertEq(vault.maxDeposit(USER), 0);

        uint256 shares = vault.previewWithdraw(20 ether);
        vm.prank(USER);
        uint256 assets = vault.redeem(shares, USER, USER);
        assertEq(vault.depositCapUsage(), 160 ether - assets);
        assertEq(vault.maxDeposit(USER), assets - 10 ether);
        assertGt(vault.maxDeposit(USER), 0);
    }

    function test_SeedRewardsStillConsumeCapacityAfterLastUserExit() public {
        _notifyRewards(REWARD_AMOUNT);
        _finishRewardPeriod();
        uint256 shares = vault.balanceOf(USER);
        vm.prank(USER);
        vault.redeem(shares, USER, USER);

        assertEq(vault.totalSupply(), SEED_SHARES);
        assertGt(vault.depositCapUsage(), 0);
        assertEq(vault.depositCapUsage(), vault.totalAssets() - SEED_SHARES);
    }

    function test_RepeatedRoundTripsOnlyConsumeCapacityForAssetsLeftBehind() public {
        _depositFor(USER, 449 ether);
        _notifyRewards(100 ether);
        _finishRewardPeriod();
        _setDepositCap(600 ether);
        assertEq(vault.maxDeposit(RECEIVER), 50 ether);

        uint256 usageBefore = vault.depositCapUsage();
        dusd.mint(RECEIVER, 50 ether);
        vm.startPrank(RECEIVER);
        dusd.approve(address(vault), type(uint256).max);
        for (uint256 i; i < 128; ++i) {
            uint256 shares = vault.deposit(vault.maxDeposit(RECEIVER), RECEIVER);
            vault.redeem(shares, RECEIVER, RECEIVER);
            uint256 loss = 50 ether - dusd.balanceOf(RECEIVER);
            assertEq(vault.depositCapUsage(), usageBefore + loss);
            assertEq(vault.maxDeposit(RECEIVER), 50 ether - loss);
        }
        vm.stopPrank();

        assertEq(vault.balanceOf(RECEIVER), 0);
        assertLe(50 ether - dusd.balanceOf(RECEIVER), 256);
    }

    function test_SharedWrapperRoundTripCannotReassignCapUsage() public {
        AssetCapSharePool pool = new AssetCapSharePool(IERC20(address(vault)));
        // Include the virtual asset/share pair to make the exchange rate exactly 2 DUSD per share.
        _notifyRewards(vault.totalSupply() + 1);
        _finishRewardPeriod();
        vm.startPrank(USER);
        vault.approve(address(pool), 1 ether);
        pool.deposit(1 ether);
        vm.stopPrank();

        uint256 usageBefore = vault.depositCapUsage();
        uint256 headroomBefore = vault.maxDeposit(RECEIVER);
        uint256 shares = _depositFor(RECEIVER, 2 ether);
        vm.startPrank(RECEIVER);
        vault.approve(address(pool), shares);
        pool.deposit(shares);
        pool.withdraw(shares);
        uint256 assets = vault.redeem(shares, RECEIVER, RECEIVER);
        vm.stopPrank();

        assertEq(assets, 2 ether);
        assertEq(vault.balanceOf(RECEIVER), 0);
        assertEq(pool.balanceOf(RECEIVER), 0);
        assertEq(pool.balanceOf(USER), 1 ether);
        assertEq(vault.balanceOf(address(pool)), 1 ether);
        assertEq(vault.depositCapUsage(), usageBefore);
        assertEq(vault.maxDeposit(RECEIVER), headroomBefore);
    }

    function testFuzz_RoundTripsAtDifferentEntryPricesOnlyConsumeRetainedAssets(
        uint256 amount,
        uint256 reward,
        bool existingHolder,
        bool mintShares
    ) public {
        amount = bound(amount, 1 ether, 10_000 ether);
        reward = bound(reward, 1, 1_000 ether);
        _notifyRewards(reward);
        _finishRewardPeriod();
        address holder = existingHolder ? USER : RECEIVER;
        uint256 usageBefore = vault.depositCapUsage();
        uint256 sharesBefore = vault.balanceOf(holder);
        uint256 shares;
        uint256 assets;
        if (mintShares) {
            shares = vault.previewDeposit(amount);
            assets = _mintFor(holder, shares);
        } else {
            assets = amount;
            shares = _depositFor(holder, assets);
        }

        // Changing owners must not change how much capacity the eventual redemption releases.
        vm.prank(holder);
        vault.transfer(SPENDER, shares);
        vm.prank(SPENDER);
        uint256 returnedAssets = vault.redeem(shares, holder, SPENDER);

        assertEq(vault.balanceOf(holder), sharesBefore);
        assertEq(vault.balanceOf(SPENDER), 0);
        assertEq(vault.depositCapUsage(), usageBefore + assets - returnedAssets);
        assertLe(assets - returnedAssets, vault.previewMint(1));
    }
}
