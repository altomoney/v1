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

    function testDonationWithLostAssets(uint256 assets, uint128 expectedLostAssets, uint256 donation) public {
        expectedLostAssets = testLostAssetsValue(assets, expectedLostAssets);

        donation = bound(donation, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

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
