// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {SDUSD} from "@alto/sdusd/SDUSD.sol";
import {SDUSDInitParams} from "@alto/sdusd/interfaces/ISDUSDVault.sol";
import {ERC20MockMintableDecimals} from "@alto-test/helpers/ERC20MockMintableDecimals.sol";

/// @dev Verifies the seed-share sizing boundary against the real SDUSD reward and ERC-4626 flows.
///
/// Once the last live holder withdraws while a reward batch is still locked, the completed period leaves:
///
///     totalSupply = S
///     totalAssets = S + R
///
/// OpenZeppelin ERC-4626 then previews a deposit as:
///
///     shares = floor(D * (S + 1) / (S + R + 1))
///
/// Therefore a minimum deposit D continues to mint at least one share iff:
///
///     R <= (D - 1) * (S + 1)
contract SDUSD_SeedSharesRewardBoundary_Test is Test {
    uint256 internal constant SEED_SHARES = 1 ether; // 1 sDUSD (1e18 share-wei), funded by 1 DUSD at 1:1.
    uint256 internal constant MIN_SUPPORTED_DEPOSIT = 0.0001 ether; // 0.0001 DUSD (1e14 asset-wei).
    uint256 internal constant MAX_REWARD_BATCH = (MIN_SUPPORTED_DEPOSIT - 1) * (SEED_SHARES + 1); // 99,999,999,999,999.000099999999999999 DUSD.
    uint256 internal constant REWARD_DURATION = 7 days; // 604,800 seconds.

    address internal constant ADMIN = address(0xA11CE);
    address internal constant PAUSER = address(0xFEEE);
    address internal constant REWARDER = address(0xBEEF);
    address internal constant TREASURY = address(0x7E45);
    address internal constant NEW_DEPOSITOR = address(0xD09);
    address internal constant NEW_MINTER = address(0xA117);
    address internal constant SEED_LOCK = address(1);

    ERC20MockMintableDecimals internal dusd;
    SDUSD internal vault;

    function setUp() public {
        dusd = new ERC20MockMintableDecimals("DUSD", "DUSD", 18);
        SDUSD implementation = new SDUSD();
        SDUSDInitParams memory params = SDUSDInitParams({
            admin: ADMIN,
            pauser: PAUSER,
            dusd: address(dusd),
            rewarder: REWARDER,
            seedShares: SEED_SHARES,
            rewardDuration: REWARD_DURATION
        });
        vault = SDUSD(address(new ERC1967Proxy(address(implementation), abi.encodeCall(SDUSD.initialize, (params)))));

        dusd.mint(address(this), SEED_SHARES);
        dusd.approve(address(vault), SEED_SHARES);
        vault.deposit(SEED_SHARES, SEED_LOCK);

        _depositFor(TREASURY, SEED_SHARES);

        assertEq(vault.balanceOf(TREASURY), SEED_SHARES);
        assertEq(vault.balanceOf(SEED_LOCK), SEED_SHARES);
        assertEq(vault.totalSupply(), SEED_SHARES * 2);
        assertEq(vault.totalAssets(), SEED_SHARES * 2);
    }

    function test_MaximumRewardBatchAllowsMinimumSupportedDepositAfterLastUserWithdraws() public {
        _completeWorstCaseRewardLifecycle(MAX_REWARD_BATCH);

        assertEq(_minimumAssetsForOneShare(), MIN_SUPPORTED_DEPOSIT);
        assertEq(vault.previewDeposit(MIN_SUPPORTED_DEPOSIT - 1), 0);
        assertEq(vault.previewDeposit(MIN_SUPPORTED_DEPOSIT), 1);

        uint256 shares = _depositFor(NEW_DEPOSITOR, MIN_SUPPORTED_DEPOSIT);

        assertEq(shares, 1);
        assertEq(vault.balanceOf(NEW_DEPOSITOR), 1);
        assertEq(vault.totalSupply(), SEED_SHARES + 1);
    }

    function test_MintingOneShareCostsMinimumSupportedDepositAtMaximumRewardBatch() public {
        _completeWorstCaseRewardLifecycle(MAX_REWARD_BATCH);

        assertEq(vault.previewMint(1), MIN_SUPPORTED_DEPOSIT);

        uint256 assets = _mintFor(NEW_MINTER, 1);

        assertEq(assets, MIN_SUPPORTED_DEPOSIT);
        assertEq(vault.balanceOf(NEW_MINTER), 1);
    }

    function _completeWorstCaseRewardLifecycle(uint256 rewardAmount) internal {
        _notifyRewards(rewardAmount);

        // Rewards are fully locked, so the last live holder can still withdraw all of its original principal.
        assertEq(vault.lockedRewardsRemaining(), rewardAmount);
        assertEq(vault.totalAssets(), SEED_SHARES * 2);
        assertEq(vault.maxWithdraw(TREASURY), SEED_SHARES);

        vm.prank(TREASURY);
        uint256 burnedShares = vault.withdraw(SEED_SHARES, TREASURY, TREASURY);

        assertEq(burnedShares, SEED_SHARES);
        assertEq(vault.balanceOf(TREASURY), 0);
        assertEq(vault.balanceOf(SEED_LOCK), SEED_SHARES);
        assertEq(vault.totalSupply(), SEED_SHARES);
        assertEq(vault.accountedAssets(), SEED_SHARES + rewardAmount);
        assertEq(vault.lockedRewardsRemaining(), rewardAmount);
        assertEq(vault.totalAssets(), SEED_SHARES);
        assertEq(dusd.balanceOf(address(vault)), SEED_SHARES + rewardAmount);

        vm.warp(vault.rewardPeriodFinish());

        assertEq(vault.lockedRewardsRemaining(), 0);
        assertEq(vault.totalAssets(), SEED_SHARES + rewardAmount);
    }

    function _depositFor(address depositor, uint256 assets) internal returns (uint256 shares) {
        dusd.mint(depositor, assets);
        vm.startPrank(depositor);
        dusd.approve(address(vault), assets);
        shares = vault.deposit(assets, depositor);
        vm.stopPrank();
    }

    function _mintFor(address minter, uint256 shares) internal returns (uint256 assets) {
        uint256 requiredAssets = vault.previewMint(shares);
        dusd.mint(minter, requiredAssets);
        vm.startPrank(minter);
        dusd.approve(address(vault), requiredAssets);
        assets = vault.mint(shares, minter);
        vm.stopPrank();
    }

    function _notifyRewards(uint256 amount) internal {
        dusd.mint(REWARDER, amount);
        vm.startPrank(REWARDER);
        dusd.approve(address(vault), amount);
        vault.notifyRewardAmount(amount);
        vm.stopPrank();
    }

    function _minimumAssetsForOneShare() internal view returns (uint256) {
        return Math.ceilDiv(vault.totalAssets() + 1, vault.totalSupply() + 1);
    }
}
