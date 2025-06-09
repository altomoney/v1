// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "../../../helpers/ERC20Mock.sol";
import {AltoBorrowMarket, LiquidationConfiguration} from "@alto/lending/AltoBorrowMarket.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {OracleMock} from "@alto/oracles/mocks/OracleMock.sol";
import {ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IMarketErrors} from "@alto/lending/interfaces/IMarket.sol";

contract SetLiquidationConfigurationTest is Test {
    AltoBorrowMarket market;
    ERC20Mock borrowToken;
    ERC20Mock collateralToken;
    address alice = address(0xA11CE);
    address owner = address(this);

    function setUp() public {
        // Deploy mock contracts
        borrowToken = new ERC20Mock("Borrow Token", "BTKN");
        collateralToken = new ERC20Mock("Collateral Token", "CTKN");

        address irm = address(new FixedRateIrm(0.04 ether / uint256(365 days), owner));
        address oracle = address(new OracleMock());
        OracleMock(oracle).setPrice(ORACLE_PRICE_PRECISION);

        market = new AltoBorrowMarket(
            address(borrowToken),
            address(collateralToken),
            address(irm),
            owner,
            address(oracle),
            0.75 ether,
            0,
            owner,
            LiquidationConfiguration({
                maxLiquidationLtv: 0.8 ether,
                dynamicBonusFeeStart: 0.03 ether,
                ltvForCompleteLiquidation: 0.9 ether,
                dynamicBonusFeeDecaySteepness: 5 ether,
                liquidationBaseFee: 0.05 ether,
                minPenaltyPercentage: 0.01 ether,
                priorityLiquidationGracePeriod: 5 minutes,
                taggerLiquidationGracePeriod: 2 minutes,
                liquidationWindowTag: 3 days
            })
        );
    }

    function test_RevertWhen_CallerIsNotOwner() public {
        LiquidationConfiguration memory config = LiquidationConfiguration({
            maxLiquidationLtv: 0.8 ether,
            dynamicBonusFeeStart: 0.03 ether,
            ltvForCompleteLiquidation: 0.9 ether,
            dynamicBonusFeeDecaySteepness: 5 ether,
            liquidationBaseFee: 0.05 ether,
            minPenaltyPercentage: 0.01 ether,
            priorityLiquidationGracePeriod: 5 minutes,
            taggerLiquidationGracePeriod: 2 minutes,
            liquidationWindowTag: 3 days
        });

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        market.setLiquidationConfiguration(config);
        vm.stopPrank();
    }

    modifier givenCallerIsOwner() {
        _;
    }

    function test_SetLiquidationConfigurationWhen_MaxLiquidationLtvIsZero() public givenCallerIsOwner {
        LiquidationConfiguration memory config = LiquidationConfiguration({
            maxLiquidationLtv: 0,
            dynamicBonusFeeStart: 0.03 ether,
            ltvForCompleteLiquidation: 0.9 ether,
            dynamicBonusFeeDecaySteepness: 5 ether,
            liquidationBaseFee: 0.05 ether,
            minPenaltyPercentage: 0.01 ether,
            priorityLiquidationGracePeriod: 5 minutes,
            taggerLiquidationGracePeriod: 2 minutes,
            liquidationWindowTag: 3 days
        });

        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSelector(IMarketErrors.AltoBorrowMarketInvalidInput.selector));
        market.setLiquidationConfiguration(config);
        vm.stopPrank();
    }

    function test_SetLiquidationConfigurationWhen_MaxLiquidationLtvIsGreaterThanWad() public givenCallerIsOwner {
        LiquidationConfiguration memory config = LiquidationConfiguration({
            maxLiquidationLtv: 1.1 ether,
            dynamicBonusFeeStart: 0.03 ether,
            ltvForCompleteLiquidation: 0.9 ether,
            dynamicBonusFeeDecaySteepness: 5 ether,
            liquidationBaseFee: 0.05 ether,
            minPenaltyPercentage: 0.01 ether,
            priorityLiquidationGracePeriod: 5 minutes,
            taggerLiquidationGracePeriod: 2 minutes,
            liquidationWindowTag: 3 days
        });

        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSelector(IMarketErrors.AltoBorrowMarketInvalidInput.selector));
        market.setLiquidationConfiguration(config);
        vm.stopPrank();
    }

    function test_SetLiquidationConfigurationWhen_DynamicBonusFeeStartIsGreaterThanWad() public givenCallerIsOwner {
        LiquidationConfiguration memory config = LiquidationConfiguration({
            maxLiquidationLtv: 0.8 ether,
            dynamicBonusFeeStart: 1.1 ether,
            ltvForCompleteLiquidation: 0.9 ether,
            dynamicBonusFeeDecaySteepness: 5 ether,
            liquidationBaseFee: 0.05 ether,
            minPenaltyPercentage: 0.01 ether,
            priorityLiquidationGracePeriod: 5 minutes,
            taggerLiquidationGracePeriod: 2 minutes,
            liquidationWindowTag: 3 days
        });

        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSelector(IMarketErrors.AltoBorrowMarketInvalidInput.selector));
        market.setLiquidationConfiguration(config);
        vm.stopPrank();
    }

    function test_SetLiquidationConfigurationWhen_LtvForCompleteLiquidationIsLessThanMaxLiquidationLtv()
        public
        givenCallerIsOwner
    {
        LiquidationConfiguration memory config = LiquidationConfiguration({
            maxLiquidationLtv: 0.8 ether,
            dynamicBonusFeeStart: 0.03 ether,
            ltvForCompleteLiquidation: 0.7 ether, // Less than maxLiquidationLtv
            dynamicBonusFeeDecaySteepness: 5 ether,
            liquidationBaseFee: 0.05 ether,
            minPenaltyPercentage: 0.01 ether,
            priorityLiquidationGracePeriod: 5 minutes,
            taggerLiquidationGracePeriod: 2 minutes,
            liquidationWindowTag: 3 days
        });

        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSelector(IMarketErrors.AltoBorrowMarketInvalidInput.selector));
        market.setLiquidationConfiguration(config);
        vm.stopPrank();
    }

    function test_SetLiquidationConfigurationWhen_LtvForCompleteLiquidationIsGreaterThanWad()
        public
        givenCallerIsOwner
    {
        LiquidationConfiguration memory config = LiquidationConfiguration({
            maxLiquidationLtv: 0.8 ether,
            dynamicBonusFeeStart: 0.03 ether,
            ltvForCompleteLiquidation: 1.1 ether,
            dynamicBonusFeeDecaySteepness: 5 ether,
            liquidationBaseFee: 0.05 ether,
            minPenaltyPercentage: 0.01 ether,
            priorityLiquidationGracePeriod: 5 minutes,
            taggerLiquidationGracePeriod: 2 minutes,
            liquidationWindowTag: 3 days
        });

        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSelector(IMarketErrors.AltoBorrowMarketInvalidInput.selector));
        market.setLiquidationConfiguration(config);
        vm.stopPrank();
    }

    function test_SetLiquidationConfigurationWhen_LiquidationBaseFeeIsGreaterThanWad() public givenCallerIsOwner {
        LiquidationConfiguration memory config = LiquidationConfiguration({
            maxLiquidationLtv: 0.8 ether,
            dynamicBonusFeeStart: 0.03 ether,
            ltvForCompleteLiquidation: 0.9 ether,
            dynamicBonusFeeDecaySteepness: 5 ether,
            liquidationBaseFee: 1.1 ether,
            minPenaltyPercentage: 0.01 ether,
            priorityLiquidationGracePeriod: 5 minutes,
            taggerLiquidationGracePeriod: 2 minutes,
            liquidationWindowTag: 3 days
        });

        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSelector(IMarketErrors.AltoBorrowMarketInvalidInput.selector));
        market.setLiquidationConfiguration(config);
        vm.stopPrank();
    }

    function test_SetLiquidationConfigurationWhen_MinPenaltyPercentageIsGreaterThanWad() public givenCallerIsOwner {
        LiquidationConfiguration memory config = LiquidationConfiguration({
            maxLiquidationLtv: 0.8 ether,
            dynamicBonusFeeStart: 0.03 ether,
            ltvForCompleteLiquidation: 0.9 ether,
            dynamicBonusFeeDecaySteepness: 5 ether,
            liquidationBaseFee: 0.05 ether,
            minPenaltyPercentage: 1.1 ether,
            priorityLiquidationGracePeriod: 5 minutes,
            taggerLiquidationGracePeriod: 2 minutes,
            liquidationWindowTag: 3 days
        });

        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSelector(IMarketErrors.AltoBorrowMarketInvalidInput.selector));
        market.setLiquidationConfiguration(config);
        vm.stopPrank();
    }

    function test_SetLiquidationConfigurationWhen_AllParametersAreValid() public {
        LiquidationConfiguration memory newConfig = LiquidationConfiguration({
            maxLiquidationLtv: 0.85 ether,
            dynamicBonusFeeStart: 0.02 ether,
            ltvForCompleteLiquidation: 0.95 ether,
            dynamicBonusFeeDecaySteepness: 6 ether,
            liquidationBaseFee: 0.06 ether,
            minPenaltyPercentage: 0.02 ether,
            priorityLiquidationGracePeriod: 6 minutes,
            taggerLiquidationGracePeriod: 3 minutes,
            liquidationWindowTag: 3 days
        });

        vm.startPrank(owner);
        market.setLiquidationConfiguration(newConfig);

        // Destructure the tuple returned by the getter
        (
            uint256 maxLiquidationLtv,
            uint256 dynamicBonusFeeStart,
            uint256 ltvForCompleteLiquidation,
            uint256 dynamicBonusFeeDecaySteepness,
            uint256 liquidationBaseFee,
            uint256 minPenaltyPercentage,
            uint32 priorityLiquidationGracePeriod,
            uint32 taggerLiquidationGracePeriod,
            uint32 liquidationWindowTag
        ) = market.liquidationConfiguration();
        assertEq(maxLiquidationLtv, newConfig.maxLiquidationLtv);
        assertEq(dynamicBonusFeeStart, newConfig.dynamicBonusFeeStart);
        assertEq(ltvForCompleteLiquidation, newConfig.ltvForCompleteLiquidation);
        assertEq(dynamicBonusFeeDecaySteepness, newConfig.dynamicBonusFeeDecaySteepness);
        assertEq(liquidationBaseFee, newConfig.liquidationBaseFee);
        assertEq(minPenaltyPercentage, newConfig.minPenaltyPercentage);
        assertEq(priorityLiquidationGracePeriod, newConfig.priorityLiquidationGracePeriod);
        assertEq(taggerLiquidationGracePeriod, newConfig.taggerLiquidationGracePeriod);
        assertEq(liquidationWindowTag, newConfig.liquidationWindowTag);
        vm.stopPrank();
    }
}
