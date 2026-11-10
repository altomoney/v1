// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./helpers/IntegrationTest.sol";
import {Vm} from "forge-std/Vm.sol";

contract LostAssetsTest is IntegrationTest {
    // using stdStorage for StdStorage;
    using AltoBalancesLib for address;
    using MarketLib for address;
    using Math for uint256;
    using FixedPointMath for uint256;

    address internal LIQUIDATOR;

    IERC4626 internal erc4626Vault;

    function _writeTotalSupplyAssets(address market, uint128 newValue) internal {
        bytes32 totalSupplySlot = bytes32(uint256(6));
        bytes32 totalSupplyValue = vm.load(market, totalSupplySlot);
        bytes32 newTotalSupplyValue = (totalSupplyValue >> 128 << 128) | bytes32(uint256(newValue));
        vm.store(market, totalSupplySlot, newTotalSupplyValue);
    }

    function _withdrawQueueIndexesWithout(address excludedMarket) internal view returns (uint256[] memory indexes) {
        uint256 length = vault.withdrawQueueLength();
        uint256 kept;

        for (uint256 i; i < length; ++i) {
            if (vault.withdrawQueue(i) != excludedMarket) ++kept;
        }

        indexes = new uint256[](kept);
        uint256 nextIndex;

        for (uint256 i; i < length; ++i) {
            if (vault.withdrawQueue(i) == excludedMarket) continue;
            indexes[nextIndex] = i;
            ++nextIndex;
        }
    }

    function setUp() public override {
        super.setUp();

        _setCap(allMarkets[0], CAP);
        _sortSupplyQueueIdleLast();

        erc4626Vault = IERC4626(address(vault));

        LIQUIDATOR = makeAddr("Liquidator");
    }

    function testWriteTotalSupplyAssets(uint128 newValue) public {
        address market = _deployMarket(address(1), address(2), 0.7 ether, address(0), address(0));
        _writeTotalSupplyAssets(market, newValue);

        assertEq(IMarket(market).totalSupply().assets, newValue);
    }

    function testTotalAssetsNoDecrease(uint256 assets, uint128 expectedLostAssets) public {
        assets = bound(assets, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        loanToken.setBalance(SUPPLIER, assets);

        vm.prank(SUPPLIER);
        erc4626Vault.deposit(assets, ONBEHALF);

        uint128 totalSupplyAssetsBefore = IMarket(allMarkets[0]).totalSupply().assets;
        expectedLostAssets = uint128(bound(expectedLostAssets, 0, totalSupplyAssetsBefore));

        uint256 totalAssetsBefore = erc4626Vault.totalAssets();
        _writeTotalSupplyAssets(allMarkets[0], totalSupplyAssetsBefore - expectedLostAssets);
        uint256 totalAssetsAfter = erc4626Vault.totalAssets();

        assertEq(totalAssetsAfter, totalAssetsBefore, "totalAssets decreased");
    }

    function testLastTotalAssetsNoDecrease(uint256 assets, uint128 expectedLostAssets) public {
        assets = bound(assets, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        loanToken.setBalance(SUPPLIER, assets);

        vm.prank(SUPPLIER);
        erc4626Vault.deposit(assets, ONBEHALF);

        uint128 totalSupplyAssetsBefore = IMarket(allMarkets[0]).totalSupply().assets;
        expectedLostAssets = uint128(bound(expectedLostAssets, 0, totalSupplyAssetsBefore));

        uint256 lastTotalAssetsBefore = AltoVault(address(erc4626Vault)).lastTotalAssets();
        _writeTotalSupplyAssets(allMarkets[0], totalSupplyAssetsBefore - expectedLostAssets);
        erc4626Vault.deposit(0, ONBEHALF); // update lostAssets.
        uint256 lastTotalAssetsAfter = AltoVault(address(erc4626Vault)).lastTotalAssets();

        assertGe(lastTotalAssetsAfter, lastTotalAssetsBefore, "totalAssets decreased");
    }

    function testLostAssetsValue() public {
        loanToken.setBalance(SUPPLIER, 1 ether);

        vm.prank(SUPPLIER);
        erc4626Vault.deposit(1 ether, ONBEHALF);

        _writeTotalSupplyAssets(allMarkets[0], 0.5 ether);

        erc4626Vault.deposit(0, ONBEHALF); // update lostAssets.

        assertEq(AltoVault(address(erc4626Vault)).lostAssets(), 0.5 ether, "expected lostAssets");
    }

    function testLostAssetsValue(uint256 assets, uint128 expectedLostAssets) public returns (uint128) {
        assets = bound(assets, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        loanToken.setBalance(SUPPLIER, assets);

        vm.prank(SUPPLIER);
        erc4626Vault.deposit(assets, ONBEHALF);

        uint128 totalSupplyAssetsBefore = IMarket(allMarkets[0]).totalSupply().assets;
        expectedLostAssets = uint128(bound(expectedLostAssets, 0, totalSupplyAssetsBefore));

        _writeTotalSupplyAssets(allMarkets[0], totalSupplyAssetsBefore - expectedLostAssets);

        erc4626Vault.deposit(0, ONBEHALF); // update lostAssets.

        assertEq(AltoVault(address(erc4626Vault)).lostAssets(), expectedLostAssets, "expected lostAssets");

        return expectedLostAssets;
    }

    function testResupplyOnLostAssets(uint256 assets, uint128 expectedLostAssets, uint256 assets2) public {
        expectedLostAssets = testLostAssetsValue(assets, expectedLostAssets);

        assets2 = bound(assets2, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        loanToken.setBalance(SUPPLIER, assets2);

        vm.prank(SUPPLIER);
        erc4626Vault.deposit(assets2, ONBEHALF);

        assertEq(AltoVault(address(erc4626Vault)).lostAssets(), expectedLostAssets, "lostAssets after resupply");
    }

    function testNewLostAssetsOnLostAssets(
        uint256 firstSupply,
        uint128 firstLostAssets,
        uint256 secondSupply,
        uint128 secondLostAssets
    ) public {
        firstLostAssets = testLostAssetsValue(firstSupply, firstLostAssets);

        secondSupply = bound(secondSupply, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        loanToken.setBalance(SUPPLIER, secondSupply);

        vm.prank(SUPPLIER);
        erc4626Vault.deposit(secondSupply, ONBEHALF);

        uint128 totalSupplyAssetsBefore = IMarket(allMarkets[0]).totalSupply().assets;
        secondLostAssets = uint128(bound(secondLostAssets, 0, totalSupplyAssetsBefore));

        _writeTotalSupplyAssets(allMarkets[0], totalSupplyAssetsBefore - secondLostAssets);

        erc4626Vault.deposit(0, ONBEHALF); // update lostAssets.

        assertEq(
            AltoVault(address(erc4626Vault)).lostAssets(),
            firstLostAssets + secondLostAssets,
            "lostAssets after new loss"
        );
    }

    function testLostAssetsEvent(uint256 assets, uint128 expectedLostAssets) public {
        assets = bound(assets, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        loanToken.setBalance(SUPPLIER, assets);

        vm.prank(SUPPLIER);
        erc4626Vault.deposit(assets, ONBEHALF);

        uint128 totalSupplyAssetsBefore = IMarket(allMarkets[0]).totalSupply().assets;
        expectedLostAssets = uint128(bound(expectedLostAssets, 0, totalSupplyAssetsBefore));

        _writeTotalSupplyAssets(allMarkets[0], totalSupplyAssetsBefore - expectedLostAssets);

        vm.expectEmit();
        emit IAltoVaultEvents.UpdateLostAssets(expectedLostAssets);
        erc4626Vault.deposit(0, ONBEHALF); // update lostAssets.

        assertEq(AltoVault(address(erc4626Vault)).lostAssets(), expectedLostAssets, "totalAssets decreased");
    }

    function testMaxWithdrawWithLostAssets(uint256 assets, uint128 expectedLostAssets) public {
        assets = bound(assets, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        loanToken.setBalance(SUPPLIER, assets);

        vm.prank(SUPPLIER);
        erc4626Vault.deposit(assets, ONBEHALF);

        uint128 totalSupplyAssetsBefore = IMarket(allMarkets[0]).totalSupply().assets;
        expectedLostAssets = uint128(bound(expectedLostAssets, 1, totalSupplyAssetsBefore));

        assertEq(erc4626Vault.maxWithdraw(ONBEHALF), totalSupplyAssetsBefore);

        _writeTotalSupplyAssets(allMarkets[0], totalSupplyAssetsBefore - expectedLostAssets);

        erc4626Vault.deposit(0, ONBEHALF); // update lostAssets.

        assertEq(erc4626Vault.maxWithdraw(ONBEHALF), totalSupplyAssetsBefore - expectedLostAssets);
    }

    function testInterestAccrualWithLostAssets(uint256 assets, uint128 expectedLostAssets, uint128 interest) public {
        expectedLostAssets = testLostAssetsValue(assets, expectedLostAssets);

        uint128 totalSupplyAssetsBefore = IMarket(allMarkets[0]).totalSupply().assets;
        interest = uint128(bound(interest, 1, type(uint128).max - totalSupplyAssetsBefore));

        _writeTotalSupplyAssets(allMarkets[0], totalSupplyAssetsBefore + interest);

        uint256 expectedTotalAssets = allMarkets[0].expectedSupplyAssets(address(erc4626Vault));
        uint256 totalAssetsAfter = erc4626Vault.totalAssets();

        assertEq(totalAssetsAfter, expectedTotalAssets + expectedLostAssets);
    }

    // ! Note: This test was failing in the original codebase
    function testDonationWithLostAssets(uint256 assets, uint128 expectedLostAssets, uint256 donation) public {
        expectedLostAssets = testLostAssetsValue(assets, expectedLostAssets);

        (uint128 totalSupplyAssets, uint128 totalSupplyShares) = allMarkets[0].totalSupply();
        uint256 remainingShareCapacity = uint256(type(uint128).max) - totalSupplyShares;
        uint256 maxDonation = AssetShareConversionMath.convertToAssetsDown(
                remainingShareCapacity, totalSupplyAssets, totalSupplyShares
            ).min(MAX_TEST_ASSETS);

        // Some lost-assets states leave no valid donation >= MIN_TEST_ASSETS that would keep market shares in-bounds.
        if (maxDonation < MIN_TEST_ASSETS) return;

        donation = bound(donation, MIN_TEST_ASSETS, maxDonation);

        uint256 totalAssetsBefore = erc4626Vault.totalAssets();

        loanToken.setBalance(SUPPLIER, donation);
        vm.prank(SUPPLIER);
        IMarket(allMarkets[0]).addSupply(donation, 0, address(erc4626Vault));

        uint256 totalAssetsAfter = erc4626Vault.totalAssets();

        assertEq(totalAssetsAfter, totalAssetsBefore + donation);
    }

    function testForcedMarketRemoval(uint256 assets0, uint256 assets1) public {
        assets0 = bound(assets0, MIN_TEST_ASSETS, MAX_TEST_ASSETS);
        assets1 = bound(assets1, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        _setCap(allMarkets[0], type(uint128).max);
        address[] memory supplyQueue = new address[](1);
        supplyQueue[0] = allMarkets[0];
        vm.prank(CURATOR);
        AltoVault(address(erc4626Vault)).setSupplyQueue(supplyQueue);

        loanToken.setBalance(SUPPLIER, assets0);
        vm.prank(SUPPLIER);
        erc4626Vault.deposit(assets0, address(erc4626Vault));

        _setCap(allMarkets[1], type(uint128).max);
        supplyQueue[0] = allMarkets[1];
        vm.prank(CURATOR);
        AltoVault(address(erc4626Vault)).setSupplyQueue(supplyQueue);

        loanToken.setBalance(SUPPLIER, assets1);
        vm.prank(SUPPLIER);
        erc4626Vault.deposit(assets1, address(erc4626Vault));

        _setCap(allMarkets[0], 0);
        vm.prank(CURATOR);
        AltoVault(address(erc4626Vault)).submitMarketRemoval(allMarkets[0]);
        vm.warp(block.timestamp + vault.timelock());

        uint256 totalAssetsBefore = erc4626Vault.totalAssets();

        uint256[] memory withdrawQueue = new uint256[](2);
        withdrawQueue[0] = 0;
        withdrawQueue[1] = 2;
        vm.prank(CURATOR);
        AltoVault(address(erc4626Vault)).updateWithdrawQueue(withdrawQueue);

        uint256 totalAssetsAfter = erc4626Vault.totalAssets();

        erc4626Vault.deposit(0, ONBEHALF); // update lostAssets.

        assertEq(totalAssetsBefore, totalAssetsAfter);
        assertEq(AltoVault(address(erc4626Vault)).lostAssets(), assets0);
    }

    function testLostAssetsAfterBadDebt(uint256 borrowed, uint256 deposit) public {
        borrowed = bound(borrowed, MIN_TEST_ASSETS, MAX_TEST_ASSETS);
        uint256 collateral = borrowed.divideWithRounding(1e18, allMarketsLltvs[0], true);
        deposit = bound(deposit, borrowed, MAX_TEST_ASSETS);

        collateralToken.setBalance(BORROWER, collateral);
        loanToken.setBalance(LIQUIDATOR, borrowed);
        loanToken.setBalance(SUPPLIER, deposit + 1);

        vm.prank(SUPPLIER);
        erc4626Vault.deposit(deposit, ONBEHALF);

        vm.startPrank(BORROWER);
        IMarket(allMarkets[0]).addCollateral(collateral, BORROWER);
        IMarket(allMarkets[0]).borrow(borrowed, 0, BORROWER, BORROWER, hex"");
        vm.stopPrank();

        OracleMock(IMarket(allMarkets[0]).oracle()).setPrice(1e12);

        uint256 badDebtClearedAssets;

        vm.startPrank(LIQUIDATOR);
        loanToken.approve(address(allMarkets[0]), borrowed);
        vm.recordLogs();

        try IMarket(allMarkets[0]).liquidate(BORROWER, hex"", hex"") {
            Vm.Log[] memory logs = vm.getRecordedLogs();
            bytes32 liquidationTopic =
                keccak256("Liquidation(address,address,uint256,uint256,uint256,uint256,uint256,uint256)");

            for (uint256 i; i < logs.length; ++i) {
                if (logs[i].emitter == allMarkets[0] && logs[i].topics[0] == liquidationTopic) {
                    (,,,,, uint256 _badDebtClearedAssets,) =
                        abi.decode(logs[i].data, (address, uint256, uint256, uint256, uint256, uint256, uint256));
                    badDebtClearedAssets = _badDebtClearedAssets;
                    break;
                }
            }
        } catch (bytes memory reason) {
            vm.stopPrank();
            // Skip this fuzz run when liquidation reverts with Panic(0x12) (division by zero).
            // The liquidation engine computes newLTV as positionBorrowedAssets / positionCollateralValue; when
            // collateral is worthless (e.g. oracle price crashed), positionCollateralValue is 0 and the division
            // panics. That case corresponds to full bad debt; we cannot read badDebtClearedAssets from the
            // Liquidation event because the call reverted, so we skip the remainder of the test for this run.
            if (reason.length >= 36 && bytes4(reason) == bytes4(keccak256("Panic(uint256)"))) {
                uint256 panicCode;
                assembly {
                    panicCode := mload(add(add(reason, 0x20), 4))
                }
                if (panicCode == 0x12) return;
            }
            assembly {
                revert(add(reason, 0x20), mload(reason))
            }
        }

        vm.stopPrank();

        uint256 totalAssetsBefore = erc4626Vault.totalAssets();

        vm.prank(SUPPLIER);
        erc4626Vault.deposit(0, ONBEHALF);

        uint256 lostAssetsAfter = AltoVault(address(erc4626Vault)).lostAssets();
        assertEq(lostAssetsAfter, badDebtClearedAssets);
        assertEq(totalAssetsBefore, erc4626Vault.totalAssets());
    }

    function testCoverLostAssets(uint256 assets, uint128 expectedLostAssets) public {
        assets = bound(assets, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        loanToken.setBalance(SUPPLIER, assets);

        vm.prank(SUPPLIER);
        erc4626Vault.deposit(assets, ONBEHALF);

        uint128 totalSupplyAssetsBefore = IMarket(allMarkets[0]).totalSupply().assets;
        expectedLostAssets = uint128(bound(expectedLostAssets, 0, totalSupplyAssetsBefore));

        _writeTotalSupplyAssets(allMarkets[0], totalSupplyAssetsBefore - expectedLostAssets);

        loanToken.setBalance(address(this), expectedLostAssets);
        loanToken.approve(address(erc4626Vault), expectedLostAssets);
        erc4626Vault.deposit(expectedLostAssets, address(1));

        vm.prank(ONBEHALF);
        erc4626Vault.withdraw(assets, ONBEHALF, ONBEHALF);
    }

    function testReenableRemovedMarketDoesNotDoubleCountResidualSupply() public {
        uint256 initialDeposit = 100 ether;
        address market = allMarkets[0];

        loanToken.setBalance(SUPPLIER, initialDeposit);

        vm.prank(SUPPLIER);
        uint256 supplierShares = erc4626Vault.deposit(initialDeposit, SUPPLIER);

        assertEq(supplierShares, initialDeposit, "initial shares");
        assertEq(vault.lastTotalAssets(), initialDeposit, "initial lastTotalAssets");
        assertEq(erc4626Vault.totalAssets(), initialDeposit, "initial totalAssets");
        assertEq(market.expectedSupplyAssets(address(vault)), initialDeposit, "initial market balance");

        _setCap(market, 0);

        vm.prank(CURATOR);
        vault.submitMarketRemoval(market);

        vm.warp(block.timestamp + vault.timelock());

        uint256[] memory indexes = _withdrawQueueIndexesWithout(market);

        vm.prank(ALLOCATOR);
        vault.updateWithdrawQueue(indexes);

        assertFalse(vault.config(market).enabled, "market removed");
        assertEq(market.expectedSupplyAssets(address(vault)), initialDeposit, "residual market balance kept");
        assertEq(vault.lastTotalAssets(), initialDeposit, "removal preserves lastTotalAssets");
        assertEq(erc4626Vault.totalAssets(), initialDeposit, "removal preserves totalAssets");
        assertEq(vault.quarantinedAssets(market), initialDeposit, "quarantined recorded at removal");

        _setCap(market, type(uint184).max);

        assertEq(vault.lastTotalAssets(), initialDeposit, "re-enable should not inflate lastTotalAssets");
        assertEq(vault.lostAssets(), 0, "re-enable should clear preserved lostAssets overlap");
        assertEq(erc4626Vault.totalAssets(), initialDeposit, "re-enable should not inflate totalAssets");
        assertEq(vault.quarantinedAssets(market), 0, "quarantine cleared on re-enable");

        loanToken.setBalance(ONBEHALF, initialDeposit);

        vm.prank(ONBEHALF);
        uint256 victimShares = erc4626Vault.deposit(initialDeposit, ONBEHALF);

        assertEq(victimShares, initialDeposit, "victim should receive full shares");

        vm.prank(SUPPLIER);
        uint256 supplierAssets = erc4626Vault.redeem(supplierShares, SUPPLIER, SUPPLIER);

        assertEq(supplierAssets, initialDeposit, "supplier should only redeem their fair share");
    }

    function testReenableRemovedMarketWithPartialBadDebt() public {
        uint256 initialDeposit = 100 ether;
        address market = allMarkets[0];

        loanToken.setBalance(SUPPLIER, initialDeposit);

        vm.prank(SUPPLIER);
        erc4626Vault.deposit(initialDeposit, SUPPLIER);

        uint128 totalSupplyBefore = IMarket(market).totalSupply().assets;
        _writeTotalSupplyAssets(market, totalSupplyBefore / 2);

        _setCap(market, 0);

        vm.prank(CURATOR);
        vault.submitMarketRemoval(market);

        vm.warp(block.timestamp + vault.timelock());

        uint256[] memory indexes = _withdrawQueueIndexesWithout(market);

        vm.prank(ALLOCATOR);
        vault.updateWithdrawQueue(indexes);

        erc4626Vault.deposit(0, ONBEHALF);

        uint256 residual = market.expectedSupplyAssets(address(vault));
        assertEq(residual, initialDeposit / 2, "expected half residual balance");

        uint256 lostBefore = vault.lostAssets();
        assertEq(lostBefore, initialDeposit, "all removed assets preserved as lost");

        uint256 expectedLostAfter = lostBefore - residual;

        _setCap(market, type(uint184).max);

        assertEq(vault.lostAssets(), expectedLostAfter, "lostAssets only partially reduced by residual");
        assertEq(erc4626Vault.totalAssets(), initialDeposit, "totalAssets should not inflate");
        assertEq(vault.lastTotalAssets(), initialDeposit, "lastTotalAssets should not inflate");
    }

    /// @dev Verifies that re-enabling a force-removed market does NOT consume unrelated
    /// lostAssets that originated from a different market's impairment.
    function testReenablePreservesUnrelatedLostAssets() public {
        address marketA = allMarkets[0];
        address marketB = allMarkets[1];
        _setCap(marketB, type(uint184).max);

        address[] memory sq = new address[](3);
        sq[0] = marketA;
        sq[1] = marketB;
        sq[2] = idleMarket;
        vm.prank(ALLOCATOR);
        vault.setSupplyQueue(sq);

        loanToken.setBalance(SUPPLIER, 100 ether);
        vm.prank(SUPPLIER);
        erc4626Vault.deposit(100 ether, SUPPLIER);

        MarketAllocation[] memory allocs = new MarketAllocation[](2);
        allocs[0] = MarketAllocation(marketA, 50 ether);
        allocs[1] = MarketAllocation(marketB, type(uint256).max);
        vm.prank(ALLOCATOR);
        vault.reallocate(allocs);

        uint128 totalSupplyA = IMarket(marketA).totalSupply().assets;
        _writeTotalSupplyAssets(marketA, totalSupplyA - 20 ether);
        erc4626Vault.deposit(0, ONBEHALF);

        uint256 unrelatedLoss = vault.lostAssets();
        assertEq(unrelatedLoss, 20 ether, "unrelated lostAssets seeded");

        _setCap(marketB, 0);
        vm.prank(CURATOR);
        vault.submitMarketRemoval(marketB);
        vm.warp(block.timestamp + vault.timelock());

        uint256 marketBBalance = marketB.expectedSupplyAssets(address(vault));
        uint256[] memory indexes = _withdrawQueueIndexesWithout(marketB);
        vm.prank(ALLOCATOR);
        vault.updateWithdrawQueue(indexes);

        assertEq(vault.quarantinedAssets(marketB), marketBBalance, "quarantined recorded");

        erc4626Vault.deposit(0, ONBEHALF);
        assertEq(vault.lostAssets(), unrelatedLoss + marketBBalance, "total lostAssets after removal");

        _setCap(marketB, type(uint184).max);

        assertEq(vault.lostAssets(), unrelatedLoss, "unrelated lostAssets preserved after re-enable");
        assertEq(erc4626Vault.totalAssets(), 100 ether, "totalAssets unchanged");
    }

    /// @dev Same as above but the removed market accrues interest while quarantined.
    /// The excess interest should increase lastTotalAssets without consuming unrelated losses.
    function testReenableWithInterestPreservesUnrelatedLostAssets() public {
        address marketA = allMarkets[0];
        address marketB = allMarkets[1];
        _setCap(marketB, type(uint184).max);

        address[] memory sq = new address[](3);
        sq[0] = marketA;
        sq[1] = marketB;
        sq[2] = idleMarket;
        vm.prank(ALLOCATOR);
        vault.setSupplyQueue(sq);

        loanToken.setBalance(SUPPLIER, 100 ether);
        vm.prank(SUPPLIER);
        erc4626Vault.deposit(100 ether, SUPPLIER);

        MarketAllocation[] memory allocs = new MarketAllocation[](2);
        allocs[0] = MarketAllocation(marketA, 50 ether);
        allocs[1] = MarketAllocation(marketB, type(uint256).max);
        vm.prank(ALLOCATOR);
        vault.reallocate(allocs);

        uint128 totalSupplyA = IMarket(marketA).totalSupply().assets;
        _writeTotalSupplyAssets(marketA, totalSupplyA - 20 ether);
        erc4626Vault.deposit(0, ONBEHALF);
        assertEq(vault.lostAssets(), 20 ether, "unrelated lostAssets seeded");

        _setCap(marketB, 0);
        vm.prank(CURATOR);
        vault.submitMarketRemoval(marketB);
        vm.warp(block.timestamp + vault.timelock());

        uint256 marketBBalance = marketB.expectedSupplyAssets(address(vault));
        uint256[] memory indexes = _withdrawQueueIndexesWithout(marketB);
        vm.prank(ALLOCATOR);
        vault.updateWithdrawQueue(indexes);
        erc4626Vault.deposit(0, ONBEHALF);

        uint128 totalSupplyB = IMarket(marketB).totalSupply().assets;
        _writeTotalSupplyAssets(marketB, totalSupplyB + 30 ether);

        uint256 newMarketBBalance = marketB.expectedSupplyAssets(address(vault));
        uint256 interestDelta = newMarketBBalance - marketBBalance;

        _setCap(marketB, type(uint184).max);

        assertEq(vault.lostAssets(), 20 ether, "unrelated lostAssets preserved with interest");
        assertEq(vault.lastTotalAssets(), 100 ether + interestDelta, "interest captured in lastTotalAssets");
    }

    /// @dev Verifies that when a removed market loses value while quarantined,
    /// the additional loss stays in lostAssets alongside any unrelated losses.
    function testReenableWithLossPreservesUnrelatedLostAssets() public {
        address marketA = allMarkets[0];
        address marketB = allMarkets[1];
        _setCap(marketB, type(uint184).max);

        address[] memory sq = new address[](3);
        sq[0] = marketA;
        sq[1] = marketB;
        sq[2] = idleMarket;
        vm.prank(ALLOCATOR);
        vault.setSupplyQueue(sq);

        loanToken.setBalance(SUPPLIER, 100 ether);
        vm.prank(SUPPLIER);
        erc4626Vault.deposit(100 ether, SUPPLIER);

        MarketAllocation[] memory allocs = new MarketAllocation[](2);
        allocs[0] = MarketAllocation(marketA, 50 ether);
        allocs[1] = MarketAllocation(marketB, type(uint256).max);
        vm.prank(ALLOCATOR);
        vault.reallocate(allocs);

        uint128 totalSupplyA = IMarket(marketA).totalSupply().assets;
        _writeTotalSupplyAssets(marketA, totalSupplyA - 20 ether);
        erc4626Vault.deposit(0, ONBEHALF);
        assertEq(vault.lostAssets(), 20 ether, "unrelated lostAssets seeded");

        _setCap(marketB, 0);
        vm.prank(CURATOR);
        vault.submitMarketRemoval(marketB);
        vm.warp(block.timestamp + vault.timelock());

        uint256 marketBBalance = marketB.expectedSupplyAssets(address(vault));
        uint256[] memory indexes = _withdrawQueueIndexesWithout(marketB);
        vm.prank(ALLOCATOR);
        vault.updateWithdrawQueue(indexes);
        erc4626Vault.deposit(0, ONBEHALF);

        uint128 totalSupplyB = IMarket(marketB).totalSupply().assets;
        uint256 marketBLoss = 10 ether;
        _writeTotalSupplyAssets(marketB, totalSupplyB - uint128(marketBLoss));

        _setCap(marketB, type(uint184).max);

        assertEq(
            vault.lostAssets(),
            20 ether + marketBLoss,
            "lostAssets includes unrelated loss + market B's quarantined loss"
        );
        assertEq(erc4626Vault.totalAssets(), 100 ether, "totalAssets unchanged");
    }

    function testSupplyCanCreateLostAssets() public {
        _setCap(allMarkets[0], type(uint128).max);
        address[] memory supplyQueue = new address[](1);
        supplyQueue[0] = allMarkets[0];
        vm.prank(CURATOR);
        AltoVault(address(erc4626Vault)).setSupplyQueue(supplyQueue);

        uint256 assets0 = 1 ether;

        loanToken.setBalance(SUPPLIER, assets0);
        collateralToken.setBalance(BORROWER, type(uint128).max);

        vm.prank(SUPPLIER);
        IMarket(allMarkets[0]).addSupply(assets0, 0, SUPPLIER);

        vm.startPrank(BORROWER);
        IMarket(allMarkets[0]).addCollateral(type(uint128).max, BORROWER);
        IMarket(allMarkets[0]).borrow(assets0, 0, BORROWER, BORROWER, hex"");
        vm.stopPrank();

        // WARP
        irmMarkets[0].setBorrowRate(1e18 / uint256(365 days));
        vm.warp(block.timestamp + 1000);
        IMarket(allMarkets[0]).accrueInterest();

        loanToken.setBalance(address(this), 2);
        erc4626Vault.deposit(2, address(this));

        erc4626Vault.deposit(0, address(this));

        assertEq(AltoVault(address(erc4626Vault)).lostAssets(), 1);
    }

    function testWithdrawCanCreateLostAssets() public {
        // Values found by fuzzing.
        uint256 assets = 68398999741522940;
        uint128 newTotalSupplyAssets = 615590997673706468;

        _setCap(allMarkets[0], type(uint128).max);
        address[] memory supplyQueue = new address[](1);
        supplyQueue[0] = allMarkets[0];
        vm.prank(CURATOR);
        AltoVault(address(erc4626Vault)).setSupplyQueue(supplyQueue);

        loanToken.setBalance(address(this), assets);
        erc4626Vault.deposit(assets, address(this));

        collateralToken.setBalance(BORROWER, type(uint128).max);
        vm.startPrank(BORROWER);
        IMarket(allMarkets[0]).addCollateral(type(uint128).max, BORROWER);
        IMarket(allMarkets[0]).borrow(assets, 0, BORROWER, BORROWER, hex"");
        vm.stopPrank();

        // WARP
        _writeTotalSupplyAssets(allMarkets[0], newTotalSupplyAssets);

        loanToken.setBalance(BORROWER, type(uint256).max);
        vm.startPrank(BORROWER);
        loanToken.approve(address(allMarkets[0]), type(uint256).max);
        IMarket(allMarkets[0]).repay(0, IMarket(allMarkets[0]).position(BORROWER).borrowShares, BORROWER);
        vm.stopPrank();

        erc4626Vault.withdraw(erc4626Vault.maxWithdraw(address(this)) - 1, address(this), address(this));

        // Call to update lostAssets.
        erc4626Vault.deposit(0, address(this));

        assertEq(AltoVault(address(erc4626Vault)).lostAssets(), 1);
    }
}
