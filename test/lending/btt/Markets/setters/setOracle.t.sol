// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {MarketCommon, MarketType} from "../MarketCommon.t.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IMarketErrors, IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";
import {OracleMock} from "@alto-test/helpers/OracleMock.sol";

contract AltoMarketSetOracle is MarketCommon {
    constructor(MarketType _marketType) MarketCommon(_marketType) {}

    function test_RevertWhen_CallerIsNotOwner() external {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        market.setOracle(address(1));
    }

    modifier whenCallerIsOwner() {
        vm.startPrank(OWNER);
        _;
        vm.stopPrank();
    }

    function test_WhenCallerIsOwner() external whenCallerIsOwner {
        address oldOracle = market.oracle();
        OracleMock newOracle = new OracleMock();

        // it should emit SetOracle event
        vm.expectEmit();
        emit IMarketEvents.SetOracle(oldOracle, address(newOracle));

        market.setOracle(address(newOracle));

        // it should update oracle address
        assertEq(market.oracle(), address(newOracle));
    }

    function test_RevertWhen_OracleIsZeroAddress() external whenCallerIsOwner {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IMarketErrors.AltoBaseMarketInvalidInput.selector));
        market.setOracle(address(0));
    }
}
