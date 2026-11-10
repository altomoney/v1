// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {AltoBorrowMarketUpgraded} from "./contracts/AltoBorrowMarketUpgraded.sol";
import {ERC20Mock} from "@alto-test/helpers/ERC20Mock.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {OracleMock} from "@alto-test/helpers/OracleMock.sol";
import {LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {MarketDeployer} from "@alto-test/helpers/MarketDeployer.sol";
import {BorrowMarketInitParams, BaseMarketInitParams, Balance, Position} from "@alto/lending/interfaces/IMarket.sol";
import {
    IDcfDlbPriorityLiquidationEngine,
    LiquidationConfiguration
} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {PAUSE_TYPE, FROZEN_TYPE} from "@alto/utils/Constants.sol";
import {IMarket} from "@alto/lending/interfaces/IMarket.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {DlbDcfPriorityLiquidationEngine} from "@alto/lending/liquidation/DlbDcfPriorityLiquidationEngine.sol";
import {AltoBaseMarket} from "@alto/lending/AltoBaseMarket.sol";

import {AltoBorrowMarketUpgraded} from "./contracts/AltoBorrowMarketUpgraded.sol";
import {AltoBorrowMarketUpgradedOriginalBaseMarket} from "./contracts/AltoBorrowMarketUpgradedOriginalBaseMarket.sol";

contract AltoBorrowMarketProxyTest is Test {
    IMarket public market;
    ERC20Mock public borrowToken;
    ERC20Mock public collateralToken;

    address internal immutable USER = makeAddr("User");
    address internal immutable USER2 = makeAddr("User2");
    address internal immutable SUPPLIER = makeAddr("Supplier");
    address internal immutable OWNER = makeAddr("Owner");
    address internal immutable PAUSER = makeAddr("Pauser");

    function setUp() public {
        borrowToken = new ERC20Mock("Borrow Token", "BTKN");
        collateralToken = new ERC20Mock("Collateral Token", "CTKN");

        address irm = address(new FixedRateIrm(0.04 ether / uint256(365 days), OWNER));
        address oracle = address(new OracleMock());
        OracleMock(oracle).setPrice(LENDING_ORACLE_PRICE_PRECISION);

        LiquidationConfiguration memory liquidationConfig = LiquidationConfiguration({
            maxLiquidationLtv: 0.8 ether,
            dynamicBonusFeeStart: 0.03 ether,
            ltvForCompleteLiquidation: 0.9 ether,
            dynamicBonusFeeDecaySteepness: 5 ether,
            liquidationBaseFee: 0.05 ether,
            minPenaltyPercentage: 0.01 ether,
            protocolFeePercentage: 0.075 ether,
            isEnabledPriorityLiquidation: true,
            disablePriorityLiquidationAbovePositionLtv: type(uint256).max,
            priorityLiquidationGracePeriod: 5 minutes,
            taggerLiquidationGracePeriod: 2 minutes,
            liquidationWindowTag: 3 days
        });

        // Liquidation engine will be set after market deployment

        // Create liquidation engine before market deployment
        address liquidationEngine = address(new DlbDcfPriorityLiquidationEngine(OWNER));

        BaseMarketInitParams memory baseMarketInitParams = BaseMarketInitParams({
            borrowToken: address(borrowToken),
            collateralToken: address(collateralToken),
            irm: address(irm),
            owner: OWNER,
            emergencyAdmin: PAUSER,
            oracle: address(oracle),
            maxLtv: 0.75 ether,
            feeRecipient: OWNER,
            liquidationEngine: liquidationEngine
        });

        BorrowMarketInitParams memory borrowMarketInitParams = BorrowMarketInitParams({
            baseMarketInitParams: baseMarketInitParams,
            initialBorrowOpeningFee: 0,
            supplyCapAssets: 0,
            initialInterestFee: 0
        });

        market = IMarket(MarketDeployer.deployBorrowMarket(borrowMarketInitParams));

        assertFalse(AltoBaseMarket(address(market)).pausers(OWNER, PAUSE_TYPE));
        assertFalse(AltoBaseMarket(address(market)).pausers(OWNER, FROZEN_TYPE));
        assertTrue(AltoBaseMarket(address(market)).pausers(PAUSER, PAUSE_TYPE));
        assertTrue(AltoBaseMarket(address(market)).pausers(PAUSER, FROZEN_TYPE));

        // Market initialization automatically calls setMarketOnce on the liquidation engine
        vm.startPrank(OWNER);
        IDcfDlbPriorityLiquidationEngine(liquidationEngine).setLiquidationConfiguration(liquidationConfig);
        vm.stopPrank();

        deal(address(borrowToken), address(this), type(uint256).max);
        deal(address(collateralToken), address(this), type(uint256).max);

        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);

        vm.prank(SUPPLIER);
        market.setAuthorization(address(this), true);

        vm.prank(USER);
        market.setAuthorization(address(this), true);

        vm.prank(USER2);
        market.setAuthorization(address(this), true);

        market.addSupply(100 ether, 0, SUPPLIER);
        market.addCollateral(1 ether, USER);
        market.borrow(0.5 ether, 0, USER, USER, hex"");
    }

    struct MarketData {
        address borrowToken;
        address collateralToken;
        Balance totalSupply;
        Balance totalBorrowed;
        Position position;
        address irm;
        address owner;
        address oracle;
        uint256 maxLtv;
        uint256 borrowOpeningFee;
        address feeRecipient;
        LiquidationConfiguration liquidationConfiguration;
    }

    function _getAllMarketData() internal view returns (MarketData memory) {
        return MarketData({
            borrowToken: market.borrowToken(),
            collateralToken: market.collateralToken(),
            totalSupply: market.totalSupply(),
            totalBorrowed: market.totalBorrowed(),
            position: market.position(USER),
            irm: market.irm(),
            owner: Ownable(address(market)).owner(),
            oracle: market.oracle(),
            maxLtv: market.maxLtv(),
            borrowOpeningFee: market.borrowOpeningFee(),
            feeRecipient: market.feeRecipient(),
            liquidationConfiguration: IDcfDlbPriorityLiquidationEngine(market.liquidationEngine())
                .liquidationConfiguration()
        });
    }

    function upgradeProxyExternal(address proxy, string memory contractName, bytes memory data) external {
        Upgrades.upgradeProxy(proxy, contractName, data);
    }

    function upgradeProxyExternalUnsafe(address proxy, address newImpl, bytes memory data) external {
        UnsafeUpgrades.upgradeProxy(proxy, newImpl, data);
    }

    function test_upgradeWhenBaseWasUpgraded() public {
        vm.warp(block.timestamp + 1 days);
        market.accrueInterest();

        MarketData memory marketDataBefore = _getAllMarketData();

        // Sanity check that the market is not empty
        assertNotEq(marketDataBefore.totalSupply.assets, 0);
        assertNotEq(marketDataBefore.totalSupply.shares, 0);
        assertNotEq(marketDataBefore.totalBorrowed.assets, 0);
        assertNotEq(marketDataBefore.totalBorrowed.shares, 0);
        assertNotEq(marketDataBefore.position.borrowShares, 0);
        assertNotEq(marketDataBefore.position.collateralAssets, 0);

        vm.startPrank(OWNER);
        bool shouldUseSafeProxy = vm.envOr("VERIFY_PROXY", false);

        if (shouldUseSafeProxy) {
            Upgrades.upgradeProxy(
                address(market),
                "AltoBorrowMarketUpgraded.sol",
                abi.encodeCall(AltoBorrowMarketUpgraded.initializeV2, (1, 2, address(0x1)))
            );
        } else {
            UnsafeUpgrades.upgradeProxy(
                address(market),
                address(new AltoBorrowMarketUpgraded()),
                abi.encodeCall(AltoBorrowMarketUpgraded.initializeV2, (1, 2, address(0x1)))
            );
        }
        vm.stopPrank();

        // Verify the upgrade was successful by checking the new properties exist
        AltoBorrowMarketUpgraded upgradedMarket = AltoBorrowMarketUpgraded(address(market));

        // Verify the values were initialized
        assertEq(upgradedMarket.addedProperty1(), 1);
        assertEq(upgradedMarket.addedProperty2(), 2);
        assertEq(upgradedMarket.addedProperty3(), address(0x1));

        // Test that the new functions are available
        upgradedMarket.setAddedProperty1(100);
        upgradedMarket.setAddedProperty2(200);
        upgradedMarket.setAddedProperty3(address(0x123));

        // Verify the values were set
        assertEq(upgradedMarket.addedProperty1(), 100);
        assertEq(upgradedMarket.addedProperty2(), 200);
        assertEq(upgradedMarket.addedProperty3(), address(0x123));

        // Verify existing functionality still works
        MarketData memory marketDataAfter = _getAllMarketData();

        // Verify that the market is equal to the original market
        assertEq(marketDataBefore.borrowToken, marketDataAfter.borrowToken);
        assertEq(marketDataBefore.collateralToken, marketDataAfter.collateralToken);
        assertEq(marketDataBefore.totalSupply.assets, marketDataAfter.totalSupply.assets);
        assertEq(marketDataBefore.totalSupply.shares, marketDataAfter.totalSupply.shares);
        assertEq(marketDataBefore.totalBorrowed.assets, marketDataAfter.totalBorrowed.assets);
        assertEq(marketDataBefore.totalBorrowed.shares, marketDataAfter.totalBorrowed.shares);
        assertEq(marketDataBefore.position.supplyShares, marketDataAfter.position.supplyShares);
        assertEq(marketDataBefore.position.borrowShares, marketDataAfter.position.borrowShares);
        assertEq(marketDataBefore.position.collateralAssets, marketDataAfter.position.collateralAssets);
        assertEq(marketDataBefore.irm, marketDataAfter.irm);
        assertEq(marketDataBefore.owner, marketDataAfter.owner);
        assertEq(marketDataBefore.oracle, marketDataAfter.oracle);
        assertEq(marketDataBefore.maxLtv, marketDataAfter.maxLtv);
        assertEq(marketDataBefore.borrowOpeningFee, marketDataAfter.borrowOpeningFee);
        assertEq(marketDataBefore.feeRecipient, marketDataAfter.feeRecipient);
        assertEq(
            marketDataBefore.liquidationConfiguration.maxLiquidationLtv,
            marketDataAfter.liquidationConfiguration.maxLiquidationLtv
        );
        assertEq(
            marketDataBefore.liquidationConfiguration.dynamicBonusFeeStart,
            marketDataAfter.liquidationConfiguration.dynamicBonusFeeStart
        );
        assertEq(
            marketDataBefore.liquidationConfiguration.ltvForCompleteLiquidation,
            marketDataAfter.liquidationConfiguration.ltvForCompleteLiquidation
        );
        assertEq(
            marketDataBefore.liquidationConfiguration.dynamicBonusFeeDecaySteepness,
            marketDataAfter.liquidationConfiguration.dynamicBonusFeeDecaySteepness
        );
        assertEq(
            marketDataBefore.liquidationConfiguration.liquidationBaseFee,
            marketDataAfter.liquidationConfiguration.liquidationBaseFee
        );
        assertEq(
            marketDataBefore.liquidationConfiguration.minPenaltyPercentage,
            marketDataAfter.liquidationConfiguration.minPenaltyPercentage
        );
        assertEq(
            marketDataBefore.liquidationConfiguration.isEnabledPriorityLiquidation,
            marketDataAfter.liquidationConfiguration.isEnabledPriorityLiquidation
        );
        assertEq(
            marketDataBefore.liquidationConfiguration.disablePriorityLiquidationAbovePositionLtv,
            marketDataAfter.liquidationConfiguration.disablePriorityLiquidationAbovePositionLtv
        );
        assertEq(
            marketDataBefore.liquidationConfiguration.priorityLiquidationGracePeriod,
            marketDataAfter.liquidationConfiguration.priorityLiquidationGracePeriod
        );
        assertEq(
            marketDataBefore.liquidationConfiguration.taggerLiquidationGracePeriod,
            marketDataAfter.liquidationConfiguration.taggerLiquidationGracePeriod
        );
        assertEq(
            marketDataBefore.liquidationConfiguration.liquidationWindowTag,
            marketDataAfter.liquidationConfiguration.liquidationWindowTag
        );

        // Sanity check that the market is still working
        market.addCollateral(1 ether, USER2);
        market.borrow(0.5 ether, 0, USER2, USER2, hex"");
    }

    function test_upgradeWhenBorrowOnlyWasUpgraded() public {
        vm.warp(block.timestamp + 1 days);
        market.accrueInterest();

        MarketData memory marketDataBefore = _getAllMarketData();

        // Sanity check that the market is not empty
        assertNotEq(marketDataBefore.totalSupply.assets, 0);
        assertNotEq(marketDataBefore.totalSupply.shares, 0);
        assertNotEq(marketDataBefore.totalBorrowed.assets, 0);
        assertNotEq(marketDataBefore.totalBorrowed.shares, 0);
        assertNotEq(marketDataBefore.position.borrowShares, 0);
        assertNotEq(marketDataBefore.position.collateralAssets, 0);

        vm.startPrank(OWNER);
        bool shouldUseSafeProxy = vm.envOr("VERIFY_PROXY", false);

        if (shouldUseSafeProxy) {
            Upgrades.upgradeProxy(
                address(market),
                "AltoBorrowMarketUpgradedOriginalBaseMarket.sol",
                abi.encodeCall(AltoBorrowMarketUpgradedOriginalBaseMarket.initializeV2, ())
            );
        } else {
            UnsafeUpgrades.upgradeProxy(
                address(market),
                address(new AltoBorrowMarketUpgradedOriginalBaseMarket()),
                abi.encodeCall(AltoBorrowMarketUpgradedOriginalBaseMarket.initializeV2, ())
            );
        }
        vm.stopPrank();

        // Verify the upgrade was successful by checking the new properties exist
        AltoBorrowMarketUpgradedOriginalBaseMarket upgradedMarket =
            AltoBorrowMarketUpgradedOriginalBaseMarket(address(market));

        // Test that the new functions are available
        upgradedMarket.setAddedProperty1(100);
        upgradedMarket.setAddedProperty2(address(0x123));
        upgradedMarket.setAddedProperty3(200);

        // Verify the values were set
        assertEq(upgradedMarket.addedProperty1(), 100);
        assertEq(upgradedMarket.addedProperty2(), address(0x123));
        assertEq(upgradedMarket.addedProperty3(), 200);

        // Verify existing functionality still works
        MarketData memory marketDataAfter = _getAllMarketData();

        // Verify that the market is equal to the original market
        assertEq(marketDataBefore.borrowToken, marketDataAfter.borrowToken);
        assertEq(marketDataBefore.collateralToken, marketDataAfter.collateralToken);
        assertEq(marketDataBefore.totalSupply.assets, marketDataAfter.totalSupply.assets);
        assertEq(marketDataBefore.totalSupply.shares, marketDataAfter.totalSupply.shares);
        assertEq(marketDataBefore.totalBorrowed.assets, marketDataAfter.totalBorrowed.assets);
        assertEq(marketDataBefore.totalBorrowed.shares, marketDataAfter.totalBorrowed.shares);
        assertEq(marketDataBefore.position.supplyShares, marketDataAfter.position.supplyShares);
        assertEq(marketDataBefore.position.borrowShares, marketDataAfter.position.borrowShares);
        assertEq(marketDataBefore.position.collateralAssets, marketDataAfter.position.collateralAssets);
        assertEq(marketDataBefore.irm, marketDataAfter.irm);
        assertEq(marketDataBefore.owner, marketDataAfter.owner);
        assertEq(marketDataBefore.oracle, marketDataAfter.oracle);
        assertEq(marketDataBefore.maxLtv, marketDataAfter.maxLtv);
        assertEq(marketDataBefore.borrowOpeningFee, marketDataAfter.borrowOpeningFee);
        assertEq(marketDataBefore.feeRecipient, marketDataAfter.feeRecipient);
        assertEq(
            marketDataBefore.liquidationConfiguration.maxLiquidationLtv,
            marketDataAfter.liquidationConfiguration.maxLiquidationLtv
        );
        assertEq(
            marketDataBefore.liquidationConfiguration.dynamicBonusFeeStart,
            marketDataAfter.liquidationConfiguration.dynamicBonusFeeStart
        );
        assertEq(
            marketDataBefore.liquidationConfiguration.ltvForCompleteLiquidation,
            marketDataAfter.liquidationConfiguration.ltvForCompleteLiquidation
        );
        assertEq(
            marketDataBefore.liquidationConfiguration.dynamicBonusFeeDecaySteepness,
            marketDataAfter.liquidationConfiguration.dynamicBonusFeeDecaySteepness
        );
        assertEq(
            marketDataBefore.liquidationConfiguration.liquidationBaseFee,
            marketDataAfter.liquidationConfiguration.liquidationBaseFee
        );
        assertEq(
            marketDataBefore.liquidationConfiguration.minPenaltyPercentage,
            marketDataAfter.liquidationConfiguration.minPenaltyPercentage
        );
        assertEq(
            marketDataBefore.liquidationConfiguration.isEnabledPriorityLiquidation,
            marketDataAfter.liquidationConfiguration.isEnabledPriorityLiquidation
        );
        assertEq(
            marketDataBefore.liquidationConfiguration.disablePriorityLiquidationAbovePositionLtv,
            marketDataAfter.liquidationConfiguration.disablePriorityLiquidationAbovePositionLtv
        );
        assertEq(
            marketDataBefore.liquidationConfiguration.priorityLiquidationGracePeriod,
            marketDataAfter.liquidationConfiguration.priorityLiquidationGracePeriod
        );
        assertEq(
            marketDataBefore.liquidationConfiguration.taggerLiquidationGracePeriod,
            marketDataAfter.liquidationConfiguration.taggerLiquidationGracePeriod
        );
        assertEq(
            marketDataBefore.liquidationConfiguration.liquidationWindowTag,
            marketDataAfter.liquidationConfiguration.liquidationWindowTag
        );

        // Sanity check that the market is still working
        market.addCollateral(1 ether, USER2);
        market.borrow(0.5 ether, 0, USER2, USER2, hex"");
    }

    function test_upgradeWhenNotOwner() public {
        vm.warp(block.timestamp + 1 days);
        market.accrueInterest();

        bool success = false;
        bytes memory returnData;

        bool shouldUseSafeProxy = vm.envOr("VERIFY_PROXY", false);

        if (shouldUseSafeProxy) {
            try this.upgradeProxyExternal(
                address(market),
                "AltoBorrowMarketUpgradedOriginalBaseMarket.sol",
                abi.encodeCall(AltoBorrowMarketUpgradedOriginalBaseMarket.initializeV2, ())
            ) {
                // If we reach here, the call succeeded when it should have failed
                fail();
                success = true;
            } catch (bytes memory reason) {
                // Verify the revert reason matches what we expect
                bytes memory expectedError =
                    abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this));
                assertEq(reason, expectedError, "Unexpected revert reason");
                returnData = reason;
            }
        } else {
            try this.upgradeProxyExternalUnsafe(
                address(market),
                address(new AltoBorrowMarketUpgradedOriginalBaseMarket()),
                abi.encodeCall(AltoBorrowMarketUpgradedOriginalBaseMarket.initializeV2, ())
            ) {
                // If we reach here, the call succeeded when it should have failed
                fail();
                success = true;
            } catch (bytes memory reason) {
                // Verify the revert reason matches what we expect
                bytes memory expectedError =
                    abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this));
                assertEq(reason, expectedError, "Unexpected revert reason");
                returnData = reason;
            }
        }

        // Ensure the call failed as expected
        assertFalse(success, "Expected revert but upgrade succeeded");
    }
}
