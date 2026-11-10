// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {DlbDcfPriorityLiquidationEngine} from "@alto/lending/liquidation/DlbDcfPriorityLiquidationEngine.sol";
import {
    IDcfDlbPriorityLiquidationEngine,
    IDcfDlbPriorityLiquidationEngineErrors
} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {AltoBorrowMarket} from "@alto/lending/AltoBorrowMarket.sol";
import {BaseMarketInitParams, BorrowMarketInitParams} from "@alto/lending/interfaces/IMarket.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {OracleMock} from "@alto-test/helpers/OracleMock.sol";
import {LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {ERC20Mock} from "@alto-test/helpers/ERC20Mock.sol";
import {MarketDeployer} from "@alto-test/helpers/MarketDeployer.sol";
import {IAltoLiquidationEngine} from "@alto/lending/interfaces/IAltoLiquidationEngine.sol";

contract SetMarketOnceTest is Test {
    IDcfDlbPriorityLiquidationEngine liquidationEngine;
    address owner = address(this);
    address marketAddress;
    address otherAddress = address(0x1234);

    function setUp() public {
        liquidationEngine = IDcfDlbPriorityLiquidationEngine(address(new DlbDcfPriorityLiquidationEngine(owner)));
    }

    modifier givenMarketIsAlreadySet() {
        // Deploy a market and set it on the liquidation engine
        ERC20Mock borrowToken = new ERC20Mock("Borrow Token", "BTKN");
        ERC20Mock collateralToken = new ERC20Mock("Collateral Token", "CTKN");
        address irm = address(new FixedRateIrm(0.04 ether / uint256(365 days), owner));
        address oracle = address(new OracleMock());
        OracleMock(oracle).setPrice(LENDING_ORACLE_PRICE_PRECISION);

        BaseMarketInitParams memory baseMarketInitParams = BaseMarketInitParams({
            borrowToken: address(borrowToken),
            collateralToken: address(collateralToken),
            irm: address(irm),
            owner: owner,
            emergencyAdmin: owner,
            oracle: address(oracle),
            maxLtv: 0.75 ether,
            feeRecipient: owner,
            liquidationEngine: address(liquidationEngine)
        });

        BorrowMarketInitParams memory borrowMarketInitParams = BorrowMarketInitParams({
            baseMarketInitParams: baseMarketInitParams,
            initialBorrowOpeningFee: 0,
            supplyCapAssets: 0,
            initialInterestFee: 0
        });

        AltoBorrowMarket market = AltoBorrowMarket(MarketDeployer.deployBorrowMarket(borrowMarketInitParams));
        marketAddress = address(market);
        _;
    }

    modifier givenMarketIsNotSet() {
        // Market is not set in setUp, so this is already the case
        _;
    }

    modifier whenMarketIsAddressZero() {
        _;
    }

    modifier whenMarketIsNotAddressZero() {
        _;
    }

    modifier whenMsgSenderIsNotMarket() {
        _;
    }

    modifier whenMsgSenderIsMarket() {
        _;
    }

    function test_RevertWhen_MarketIsAlreadySet() external givenMarketIsAlreadySet {
        // it should revert with DcfDlbPriorityLiquidationEngineInvalidInput
        vm.expectRevert(IDcfDlbPriorityLiquidationEngineErrors.DcfDlbPriorityLiquidationEngineInvalidInput.selector);
        vm.prank(marketAddress);
        liquidationEngine.setMarketOnce(marketAddress);
    }

    function test_RevertWhen_MarketIsAddressZero() external givenMarketIsNotSet whenMarketIsAddressZero {
        // it should revert with DcfDlbPriorityLiquidationEngineInvalidInput
        vm.expectRevert(IDcfDlbPriorityLiquidationEngineErrors.DcfDlbPriorityLiquidationEngineInvalidInput.selector);
        liquidationEngine.setMarketOnce(address(0));
    }

    function test_RevertWhen_MsgSenderIsNotMarket()
        external
        givenMarketIsNotSet
        whenMarketIsNotAddressZero
        whenMsgSenderIsNotMarket
    {
        // Use a non-zero address for the market parameter
        address testMarket = address(0x5678);

        // it should revert with DcfDlbPriorityLiquidationEngineLiquidationUnauthorized
        vm.expectRevert(
            IDcfDlbPriorityLiquidationEngineErrors.DcfDlbPriorityLiquidationEngineLiquidationUnauthorized.selector
        );
        vm.prank(otherAddress);
        liquidationEngine.setMarketOnce(testMarket);
    }

    function test_WhenMsgSenderIsMarket()
        external
        givenMarketIsNotSet
        whenMarketIsNotAddressZero
        whenMsgSenderIsMarket
    {
        // Deploy a market to use as the market address
        ERC20Mock borrowToken = new ERC20Mock("Borrow Token", "BTKN");
        ERC20Mock collateralToken = new ERC20Mock("Collateral Token", "CTKN");
        address irm = address(new FixedRateIrm(0.04 ether / uint256(365 days), owner));
        address oracle = address(new OracleMock());
        OracleMock(oracle).setPrice(LENDING_ORACLE_PRICE_PRECISION);

        BaseMarketInitParams memory baseMarketInitParams = BaseMarketInitParams({
            borrowToken: address(borrowToken),
            collateralToken: address(collateralToken),
            irm: address(irm),
            owner: owner,
            emergencyAdmin: owner,
            oracle: address(oracle),
            maxLtv: 0.75 ether,
            feeRecipient: owner,
            liquidationEngine: address(liquidationEngine)
        });

        BorrowMarketInitParams memory borrowMarketInitParams = BorrowMarketInitParams({
            baseMarketInitParams: baseMarketInitParams,
            initialBorrowOpeningFee: 0,
            supplyCapAssets: 0,
            initialInterestFee: 0
        });

        // Expect the event to be emitted from the liquidation engine
        // We check the event signature and emitter, but not the data since we don't know the market address yet
        vm.expectEmit(false, false, false, false, address(liquidationEngine));
        emit IAltoLiquidationEngine.SetMarketOnce(address(0)); // Placeholder - address will be verified separately
        AltoBorrowMarket market = AltoBorrowMarket(MarketDeployer.deployBorrowMarket(borrowMarketInitParams));
        marketAddress = address(market);

        // it should set market successfully
        // The market initialization already calls setMarketOnce, so we verify it was set
        assertEq(liquidationEngine.market(), marketAddress);
    }
}
