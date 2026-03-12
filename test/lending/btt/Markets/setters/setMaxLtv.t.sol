// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MarketCommon, MarketType} from "../MarketCommon.t.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IMarketErrors, IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";
import {
    IDcfDlbPriorityLiquidationEngine
} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";

contract AltoMarketSetMaxLtv is MarketCommon {
    constructor(MarketType _marketType) MarketCommon(_marketType) {}

    function test_RevertWhen_CallerIsNotOwner() external {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        market.setMaxLtv(0.8 ether);
    }

    modifier whenCallerIsOwner() {
        vm.startPrank(OWNER);
        _;
        vm.stopPrank();
    }

    function test_WhenCallerIsOwner() external whenCallerIsOwner {
        uint256 oldMaxLtv = market.maxLtv();
        uint256 newMaxLtv = 0.77 ether;

        // it should emit SetMaxLtv event
        vm.expectEmit();
        emit IMarketEvents.SetMaxLtv(oldMaxLtv, newMaxLtv);

        market.setMaxLtv(newMaxLtv);

        // it should update maxLtv
        assertEq(market.maxLtv(), newMaxLtv);
    }

    function test_RevertWhen_MaxLtvIsGreaterThanMATH_PRECISION() external whenCallerIsOwner {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IMarketErrors.AltoBaseMarketInvalidInput.selector));
        market.setMaxLtv(1.1 ether);
    }

    function test_RevertWhen_MaxLtvIsGreaterThanMaxLiquidationLtv() external whenCallerIsOwner {
        uint256 newLtv = IDcfDlbPriorityLiquidationEngine(market.liquidationEngine())
            .liquidationConfiguration()
            .maxLiquidationLtv + 1;

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IMarketErrors.AltoBaseMarketInvalidInput.selector));
        market.setMaxLtv(newLtv);
    }
}
