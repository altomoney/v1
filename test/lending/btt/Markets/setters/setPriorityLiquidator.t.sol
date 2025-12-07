// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {MarketCommon, MarketType} from "../MarketCommon.t.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IMarketErrors, IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";
import {
    IDcfDlbPriorityLiquidationEngine,
    IDcfDlbPriorityLiquidationEngineEvents,
    IDcfDlbPriorityLiquidationEngineErrors
} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";

contract AltoMarketSetPriorityLiquidator is MarketCommon {
    constructor(MarketType _marketType) MarketCommon(_marketType) {}

    function test_RevertWhen_CallerIsNotOwner() external {
        IDcfDlbPriorityLiquidationEngine liquidationEngine = IDcfDlbPriorityLiquidationEngine(market.liquidationEngine());
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        liquidationEngine.setPriorityLiquidator(address(0), true);
    }

    modifier whenCallerIsOwner() {
        vm.startPrank(OWNER);
        _;
        vm.stopPrank();
    }

    function test_WhenCallerIsOwner() external whenCallerIsOwner {
        IDcfDlbPriorityLiquidationEngine liquidationEngine = IDcfDlbPriorityLiquidationEngine(market.liquidationEngine());
        address liquidator = address(0x123);
        bool status = true;

        // it should emit PriorityLiquidatorUpdated event
        vm.expectEmit();
        emit IDcfDlbPriorityLiquidationEngineEvents.PriorityLiquidatorUpdated(liquidator, status);

        liquidationEngine.setPriorityLiquidator(liquidator, status);

        // it should update priorityLiquidators mapping
        assertEq(IDcfDlbPriorityLiquidationEngine(market.liquidationEngine()).priorityLiquidators(liquidator), status);
    }

    function test_RevertWhen_LiquidatorIsZeroAddress() external whenCallerIsOwner {
        IDcfDlbPriorityLiquidationEngine liquidationEngine = IDcfDlbPriorityLiquidationEngine(market.liquidationEngine());
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IDcfDlbPriorityLiquidationEngineErrors.DcfDlbPriorityLiquidationEngineInvalidInput.selector));
        liquidationEngine.setPriorityLiquidator(address(0), true);
    }
}
