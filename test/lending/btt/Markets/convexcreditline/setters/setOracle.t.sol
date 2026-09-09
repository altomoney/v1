// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IMarketErrors, IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";
import {OracleMock} from "@alto/oracles/mocks/OracleMock.sol";
import {PAUSE_TYPE, FROZEN_TYPE} from "@alto/utils/Constants.sol";

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

    function test_UpdatesAndEmitsWithoutValidationOrSideEffects() external {
        AccountingState memory beforeState = _state();
        address oldOracle = market.oracle();

        vm.expectEmit(address(market));
        emit IMarketEvents.SetOracle(oldOracle, USER);
        vm.prank(OWNER);
        market.setOracle(USER);

        assertEq(market.oracle(), USER);
        _assertUnchanged(beforeState);

        vm.expectEmit(address(market));
        emit IMarketEvents.SetOracle(USER, USER);
        vm.prank(OWNER);
        market.setOracle(USER);
        assertEq(market.oracle(), USER);
    }

    function test_RemainsCallableInAllPauseStatesAndAffectsOutstandingDebt() external {
        _openPosition(1_000 ether, 100 ether);
        OracleMock foreclosureOracle = new OracleMock();
        foreclosureOracle.setPrice(100 ether);

        _pause(FROZEN_TYPE);
        vm.prank(OWNER);
        market.setOracle(address(foreclosureOracle));

        _pause(PAUSE_TYPE);
        vm.prank(OWNER);
        market.setOracle(address(foreclosureOracle));

        vm.prank(OWNER);
        market.governanceLiquidate(CREDIT_ACCOUNT, false);
        assertEq(market.badDebtAssets(), 100 ether);
    }
}
