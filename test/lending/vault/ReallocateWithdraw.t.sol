// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./helpers/IntegrationTest.sol";

uint256 constant CAP2 = 100e18;
uint256 constant INITIAL_DEPOSIT = 4 * CAP2;

contract ReallocateWithdrawTest is IntegrationTest {
    using MarketLib for address;
    using AltoBalancesLib for IAltoVault;
    using AltoBalancesLib for address;
    using AssetShareConversionMath for uint256;
    using UtilsLib for uint256;

    MarketAllocation[] internal allocations;

    function setUp() public override {
        super.setUp();

        _setCap(allMarkets[0], CAP2);
        _setCap(allMarkets[1], CAP2);
        _setCap(allMarkets[2], CAP2);

        _sortSupplyQueueIdleLast();

        loanToken.setBalance(SUPPLIER, INITIAL_DEPOSIT);

        vm.prank(SUPPLIER);
        IERC4626(address(vault)).deposit(INITIAL_DEPOSIT, ONBEHALF);
    }

    function testReallocateWithdrawMax() public {
        allocations.push(MarketAllocation({market: allMarkets[0], assets: 0}));
        allocations.push(MarketAllocation({market: allMarkets[1], assets: 0}));
        allocations.push(MarketAllocation({market: allMarkets[2], assets: 0}));
        allocations.push(MarketAllocation({market: idleMarket, assets: type(uint256).max}));

        vm.expectEmit();
        emit IAltoVaultEvents.ReallocateWithdraw(
            ALLOCATOR, allMarkets[0], CAP2, allMarkets[0].userSupplyShares(address(vault))
        );
        emit IAltoVaultEvents.ReallocateWithdraw(
            ALLOCATOR, allMarkets[1], CAP2, allMarkets[1].userSupplyShares(address(vault))
        );
        emit IAltoVaultEvents.ReallocateWithdraw(
            ALLOCATOR, allMarkets[2], CAP2, allMarkets[2].userSupplyShares(address(vault))
        );

        vm.prank(ALLOCATOR);
        vault.reallocate(allocations);

        assertEq(allMarkets[0].userSupplyShares(address(vault)), 0, "allMarkets[0].userSupplyShares()");
        assertEq(allMarkets[1].userSupplyShares(address(vault)), 0, "allMarkets[1].userSupplyShares()");
        assertEq(allMarkets[2].userSupplyShares(address(vault)), 0, "allMarkets[2].userSupplyShares()");
        assertEq(_idle(), INITIAL_DEPOSIT, "idle");
    }

    function testReallocateWithdrawMarketNotEnabled() public {
        address notEnabledMarket =
            _deployMarket(address(collateralToken), address(loanToken), 0.9 ether, address(0), address(0));
        loanToken.setBalance(SUPPLIER, 1);

        vm.startPrank(SUPPLIER);
        loanToken.approve(notEnabledMarket, 1);
        IMarket(notEnabledMarket).addSupply(1, 0, address(vault));
        vm.stopPrank();

        allocations.push(MarketAllocation({market: notEnabledMarket, assets: 0}));

        vm.prank(ALLOCATOR);
        vm.expectRevert(abi.encodeWithSelector(IAltoVaultErrors.MarketNotEnabled.selector, notEnabledMarket));
        vault.reallocate(allocations);
    }

    function testReallocateWithdrawSupply(uint256[3] memory newAssets) public {
        uint256[3] memory totalSupplyAssets;
        uint256[3] memory totalSupplyShares;
        (totalSupplyAssets[0], totalSupplyShares[0],,) = allMarkets[0].expectedMarketBalances();
        (totalSupplyAssets[1], totalSupplyShares[1],,) = allMarkets[1].expectedMarketBalances();
        (totalSupplyAssets[2], totalSupplyShares[2],,) = allMarkets[2].expectedMarketBalances();

        newAssets[0] = bound(newAssets[0], 0, CAP2);
        newAssets[1] = bound(newAssets[1], 0, CAP2);
        newAssets[2] = bound(newAssets[2], 0, CAP2);

        uint256[3] memory assets;
        assets[0] = allMarkets[0].expectedSupplyAssets(address(vault));
        assets[1] = allMarkets[1].expectedSupplyAssets(address(vault));
        assets[2] = allMarkets[2].expectedSupplyAssets(address(vault));

        allocations.push(MarketAllocation({market: idleMarket, assets: 0}));
        allocations.push(MarketAllocation({market: allMarkets[0], assets: newAssets[0]}));
        allocations.push(MarketAllocation({market: allMarkets[1], assets: newAssets[1]}));
        allocations.push(MarketAllocation({market: allMarkets[2], assets: newAssets[2]}));
        allocations.push(MarketAllocation({market: idleMarket, assets: type(uint256).max}));

        uint256 expectedIdle = _idle() + 3 * CAP2 - newAssets[0] - newAssets[1] - newAssets[2];

        emit IAltoVaultEvents.ReallocateWithdraw(ALLOCATOR, idleMarket, 0, 0);

        if (newAssets[0] < assets[0]) emit IAltoVaultEvents.ReallocateWithdraw(ALLOCATOR, allMarkets[0], 0, 0);
        else if (newAssets[0] > assets[0]) emit IAltoVaultEvents.ReallocateSupply(ALLOCATOR, allMarkets[0], 0, 0);

        if (newAssets[1] < assets[1]) emit IAltoVaultEvents.ReallocateWithdraw(ALLOCATOR, allMarkets[1], 0, 0);
        else if (newAssets[1] > assets[1]) emit IAltoVaultEvents.ReallocateSupply(ALLOCATOR, allMarkets[1], 0, 0);

        if (newAssets[2] < assets[2]) emit IAltoVaultEvents.ReallocateWithdraw(ALLOCATOR, allMarkets[2], 0, 0);
        else if (newAssets[2] > assets[2]) emit IAltoVaultEvents.ReallocateSupply(ALLOCATOR, allMarkets[2], 0, 0);

        emit IAltoVaultEvents.ReallocateSupply(ALLOCATOR, idleMarket, 0, 0);

        vm.prank(ALLOCATOR);
        vault.reallocate(allocations);

        assertEq(
            allMarkets[0].userSupplyShares(address(vault)),
            newAssets[0] * AssetShareConversionMath.VIRTUAL_SHARES,
            "allMarkets[0].userSupplyShares()"
        );
        assertApproxEqAbs(
            allMarkets[1].userSupplyShares(address(vault)),
            newAssets[1] * AssetShareConversionMath.VIRTUAL_SHARES,
            AssetShareConversionMath.VIRTUAL_SHARES,
            "allMarkets[1].userSupplyShares()"
        );
        assertEq(
            allMarkets[2].userSupplyShares(address(vault)),
            newAssets[2] * AssetShareConversionMath.VIRTUAL_SHARES,
            "allMarkets[2].userSupplyShares()"
        );
        assertApproxEqAbs(_idle(), expectedIdle, 1, "idle");
    }

    function testReallocateWithdrawIncreaseSupply() public {
        _setCap(allMarkets[2], 3 * CAP2);

        allocations.push(MarketAllocation({market: allMarkets[0], assets: 0}));
        allocations.push(MarketAllocation({market: allMarkets[1], assets: 0}));
        allocations.push(MarketAllocation({market: allMarkets[2], assets: 3 * CAP2}));

        vm.expectEmit();
        emit IAltoVaultEvents.ReallocateWithdraw(
            ALLOCATOR, allMarkets[0], CAP2, allMarkets[0].userSupplyShares(address(vault))
        );
        emit IAltoVaultEvents.ReallocateWithdraw(
            ALLOCATOR, allMarkets[1], CAP2, allMarkets[1].userSupplyShares(address(vault))
        );
        emit IAltoVaultEvents.ReallocateSupply(
            ALLOCATOR, allMarkets[2], 3 * CAP2, 3 * allMarkets[2].userSupplyShares(address(vault))
        );

        vm.prank(ALLOCATOR);
        vault.reallocate(allocations);

        assertEq(allMarkets[0].userSupplyShares(address(vault)), 0, "allMarkets[0].userSupplyShares()");
        assertEq(allMarkets[1].userSupplyShares(address(vault)), 0, "allMarkets[1].userSupplyShares()");
        assertEq(
            allMarkets[2].userSupplyShares(address(vault)),
            3 * CAP2 * AssetShareConversionMath.VIRTUAL_SHARES,
            "allMarkets[2].userSupplyShares()"
        );
    }

    function testReallocateUnauthorizedMarket(uint256[3] memory suppliedAssets) public {
        suppliedAssets[0] = bound(suppliedAssets[0], 1, CAP2);
        suppliedAssets[1] = bound(suppliedAssets[1], 1, CAP2);
        suppliedAssets[2] = bound(suppliedAssets[2], 1, CAP2);

        _setCap(allMarkets[1], 0);

        allocations.push(MarketAllocation({market: allMarkets[0], assets: 0}));
        allocations.push(MarketAllocation({market: allMarkets[1], assets: 0}));
        allocations.push(MarketAllocation({market: allMarkets[2], assets: 0}));

        allocations.push(MarketAllocation({market: allMarkets[0], assets: suppliedAssets[0]}));
        allocations.push(MarketAllocation({market: allMarkets[1], assets: suppliedAssets[1]}));
        allocations.push(MarketAllocation({market: allMarkets[2], assets: suppliedAssets[2]}));

        vm.prank(ALLOCATOR);
        vm.expectRevert(abi.encodeWithSelector(IAltoVaultErrors.SupplyCapExceeded.selector, allMarkets[1]));
        vault.reallocate(allocations);
    }

    function testReallocateSupplyCapExceeded() public {
        allocations.push(MarketAllocation({market: allMarkets[0], assets: 0}));
        allocations.push(MarketAllocation({market: allMarkets[1], assets: 0}));
        allocations.push(MarketAllocation({market: allMarkets[2], assets: 0}));

        allocations.push(MarketAllocation({market: allMarkets[0], assets: CAP2 + 1}));

        vm.prank(ALLOCATOR);
        vm.expectRevert(abi.encodeWithSelector(IAltoVaultErrors.SupplyCapExceeded.selector, allMarkets[0]));
        vault.reallocate(allocations);
    }

    function testReallocateInconsistentReallocation(uint256 rewards) public {
        rewards = bound(rewards, 1, MAX_TEST_ASSETS);

        loanToken.setBalance(address(vault), rewards);

        _setCap(allMarkets[0], type(uint184).max);

        allocations.push(MarketAllocation({market: idleMarket, assets: 0}));
        allocations.push(MarketAllocation({market: allMarkets[0], assets: 2 * CAP2 + rewards}));

        vm.prank(ALLOCATOR);
        vm.expectRevert(IAltoVaultErrors.InconsistentReallocation.selector);
        vault.reallocate(allocations);
    }

    function testReallocateZeroToDisabledMarket() public {
        allocations.push(MarketAllocation({market: allMarkets[0], assets: CAP2}));
        allocations.push(MarketAllocation({market: allMarkets[1], assets: CAP2}));
        allocations.push(MarketAllocation({market: allMarkets[2], assets: CAP2}));
        allocations.push(MarketAllocation({market: allMarkets[3], assets: 0})); // non enabled market.
        allocations.push(MarketAllocation({market: idleMarket, assets: type(uint256).max}));

        vm.prank(ALLOCATOR);
        vm.expectRevert(abi.encodeWithSelector(IAltoVaultErrors.MarketNotEnabled.selector, allMarkets[3]));
        vault.reallocate(allocations);
    }

    /// @notice Demonstrates that reallocate() cannot clear dust supply shares when
    /// the vault's share position has a rounded-down asset value of zero.
    /// @dev This is POC of audit report from Cantina with issue number 2
    /// @dev fixed by adding condition (allocation.assets == 0 && supplyShares != 0) in the reallocate function
    ///
    /// Scenario:
    ///   1. A large external supplier deposits directly into allMarkets[0], inflating
    ///      totalSupplyAssets/totalSupplyShares.
    ///   2. Someone supplies 1 share on behalf of the vault (via addSupply(0, 1, vault)),
    ///      giving it a dust share position.
    ///   3. convertToAssetsDown(1 share, ~1000e18, ~1000e24) ≈ 0 due to rounding.
    ///   4. reallocate(assets=0) is called to fully unwind, but:
    ///        supplyAssets = 0 (rounded down), so withdrawn = 0.zeroFloorSub(0) = 0
    ///        The `if (withdrawn > 0)` branch is skipped entirely.
    function testPOCReallocateDustSharesNotCleared() public {
        address market = allMarkets[0];

        // First, withdraw everything from allMarkets[0..2] back to idle so the vault
        // has no position in any non-idle market.
        allocations.push(MarketAllocation({market: allMarkets[0], assets: 0}));
        allocations.push(MarketAllocation({market: allMarkets[1], assets: 0}));
        allocations.push(MarketAllocation({market: allMarkets[2], assets: 0}));
        allocations.push(MarketAllocation({market: idleMarket, assets: type(uint256).max}));

        vm.prank(ALLOCATOR);
        vault.reallocate(allocations);
        delete allocations;

        assertEq(market.userSupplyShares(address(vault)), 0, "vault shares should be 0 before setup");

        // Step 1: Large external supplier deposits directly into the market, inflating
        // totalSupply so that any subsequent tiny share position rounds to 0 assets.
        uint256 largeDeposit = 1000e18;
        loanToken.setBalance(SUPPLIER, largeDeposit);
        vm.prank(SUPPLIER);
        IMarket(market).addSupply(largeDeposit, 0, SUPPLIER);

        // Step 2: Give the vault exactly 1 supply share via addSupply(0, 1, vault).
        // convertToAssetsUp(1, 1000e18, 1000e24) rounds up to 1 wei of loan token cost.
        loanToken.setBalance(SUPPLIER, 1);
        vm.prank(SUPPLIER);
        IMarket(market).addSupply(0, 1, address(vault));

        uint128 vaultShares = market.userSupplyShares(address(vault));
        assertEq(vaultShares, 1, "vault must hold exactly 1 supply share");

        // Step 3: Verify the vault's 1 share rounds to 0 assets.
        // convertToAssetsDown(1, ~1000e18, ~1000e24) = 1 * (~1000e18 + 1) / (~1000e24 + 1e6) ≈ 0
        (uint128 totalAssets, uint128 totalShares) = market.totalSupply();
        uint256 vaultAssets = uint256(vaultShares).convertToAssetsDown(uint256(totalAssets), uint256(totalShares));
        assertEq(vaultAssets, 0, "vault asset value must round to 0 (dust shares)");
        assertGt(market.userSupplyShares(address(vault)), 0, "vault must still hold nonzero shares");

        // Step 4: Attempt to fully unwind via reallocate(assets=0). This should clear
        // the position, but the bug causes it to skip the withdrawal entirely.
        // After the fix, the dust shares should be cleared.
        allocations.push(MarketAllocation({market: market, assets: 0}));
        allocations.push(MarketAllocation({market: idleMarket, assets: type(uint256).max}));

        vm.prank(ALLOCATOR);
        vault.reallocate(allocations);

        // After the fix, the dust shares should be cleared.
        uint128 remainingShares = market.userSupplyShares(address(vault));
        assertEq(remainingShares, 0, "dust shares should have been cleared but were not");
    }
}
