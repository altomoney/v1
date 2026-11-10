// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {MarketCommon, MarketType} from "../MarketCommon.t.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IMarketErrors, IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";
import {DlbDcfPriorityLiquidationEngine} from "@alto/lending/liquidation/DlbDcfPriorityLiquidationEngine.sol";
import {IAltoLiquidationEngine} from "@alto/lending/interfaces/IAltoLiquidationEngine.sol";
import {StdStorage, stdStorage} from "forge-std/StdStorage.sol";

contract AltoMarketSetLiquidationEngine is MarketCommon {
    using stdStorage for StdStorage;

    constructor(MarketType _marketType) MarketCommon(_marketType) {}

    function test_RevertWhen_CallerIsNotOwner() external {
        address newLiquidationEngine = address(new DlbDcfPriorityLiquidationEngine(OWNER));
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        market.setLiquidationEngine(newLiquidationEngine);
    }

    modifier whenCallerIsOwner() {
        vm.startPrank(OWNER);
        _;
        vm.stopPrank();
    }

    function test_RevertWhen_NewLiquidationEngineIsZeroAddress() external whenCallerIsOwner {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IMarketErrors.AltoBaseMarketInvalidInput.selector));
        market.setLiquidationEngine(address(0));
    }

    function test_RevertWhen_CurrentLiquidationEngineIsZeroAddress() external whenCallerIsOwner {
        // Manually set liquidationEngine to zero address using storage manipulation
        stdstore.target(address(market)).sig("liquidationEngine()").checked_write(address(0));

        address newLiquidationEngine = address(new DlbDcfPriorityLiquidationEngine(OWNER));
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IMarketErrors.AltoBaseMarketInvalidInput.selector));
        market.setLiquidationEngine(newLiquidationEngine);
    }

    function test_WhenCallerIsOwner() external whenCallerIsOwner {
        address oldLiquidationEngine = market.liquidationEngine();
        DlbDcfPriorityLiquidationEngine newLiquidationEngine = new DlbDcfPriorityLiquidationEngine(OWNER);

        // it should emit SetLiquidationEngine event
        vm.expectEmit();
        emit IMarketEvents.SetLiquidationEngine(oldLiquidationEngine, address(newLiquidationEngine));

        // it should call setMarketOnce on new liquidation engine
        vm.expectCall(
            address(newLiquidationEngine),
            abi.encodeWithSelector(IAltoLiquidationEngine.setMarketOnce.selector, address(market))
        );

        market.setLiquidationEngine(address(newLiquidationEngine));

        // it should update liquidationEngine
        assertEq(market.liquidationEngine(), address(newLiquidationEngine));
    }
}
