// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MarketCommon, MarketType} from "../MarketCommon.t.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {Vm} from "forge-std/Vm.sol";
import {PAUSED_MARKET} from "@alto/utils/Constants.sol";

contract AltoMarketSetIrm is MarketCommon {
    constructor(MarketType _marketType) MarketCommon(_marketType) {}

    function test_RevertWhen_CallerIsNotOwner() external {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        market.setIrm(address(1));
    }

    modifier whenCallerIsOwner() {
        vm.startPrank(OWNER);
        _;
        vm.stopPrank();
    }

    function test_WhenCallerIsOwner() external whenCallerIsOwner {
        address oldIrm = market.irm();
        address newIrm = address(new FixedRateIrm(0.05 ether / uint256(365 days), OWNER));

        // it should emit accrue event
        vm.expectEmit(false, false, false, false);
        emit IMarketEvents.AccrueInterest(0, 0, 0, 0);

        // it should emit SetIrm event
        vm.expectEmit();
        emit IMarketEvents.SetIrm(oldIrm, newIrm);

        market.setIrm(newIrm);

        // it should update irm address
        assertEq(market.irm(), newIrm);
    }

    modifier whenMarketIsPaused() {
        vm.prank(PAUSER);
        market.pause(PAUSED_MARKET, true);
        _;
    }

    function test_WhenCallerIsOwnerAndMarketIsPaused() external whenMarketIsPaused whenCallerIsOwner {
        address oldIrm = market.irm();
        address newIrm = address(new FixedRateIrm(0.05 ether / uint256(365 days), OWNER));

        // it should emit SetIrm event
        vm.expectEmit();
        emit IMarketEvents.SetIrm(oldIrm, newIrm);

        vm.recordLogs();
        market.setIrm(newIrm);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        // Assert that no AccrueInterest events were emitted
        for (uint256 i = 0; i < logs.length; i++) {
            assertFalse(logs[i].topics[0] == IMarketEvents.AccrueInterest.selector);
        }

        // it should update irm address
        assertEq(market.irm(), newIrm);
    }

    function test_WhenIrmIsNotZeroAddress() external whenCallerIsOwner {
        FixedRateIrm newIrm = new FixedRateIrm(0.05 ether / uint256(365 days), OWNER);

        market.setIrm(address(newIrm));

        assertEq(newIrm.market(), address(market));
    }
}
