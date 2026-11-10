// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IMarketErrors, IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";
import {OracleMock} from "@alto-test/helpers/OracleMock.sol";

import {ConvexCreditLineCommon} from "../ConvexCreditLineCommon.t.sol";

contract AltoConvexCreditLineMarketSetOracleTest is ConvexCreditLineCommon {
    function test_RevertWhenCallerIsNotOwner() external {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        market.setOracle(address(0));
    }

    function test_RevertForZeroOracle() external {
        vm.prank(OWNER);
        vm.expectRevert(IMarketErrors.AltoBaseMarketInvalidInput.selector);
        market.setOracle(address(0));
    }

    function test_UpdatesAndEmitsIncludingUnchangedValue() external {
        OracleMock newOracle = new OracleMock();
        address oldOracle = market.oracle();

        vm.expectEmit(address(market));
        emit IMarketEvents.SetOracle(oldOracle, address(newOracle));
        vm.prank(OWNER);
        market.setOracle(address(newOracle));

        assertEq(market.oracle(), address(newOracle));

        vm.expectEmit(address(market));
        emit IMarketEvents.SetOracle(address(newOracle), address(newOracle));
        vm.prank(OWNER);
        market.setOracle(address(newOracle));
        assertEq(market.oracle(), address(newOracle));
    }
}
