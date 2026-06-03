// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {WrapperTokenCommon} from "./WrapperTokenCommon.t.sol";
import {IWrapperTokenErrors, IWrapperTokenEvents} from "@alto/lending/wrappedToken/IWrapperToken.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract SetRollOverBotTest is WrapperTokenCommon {
    function test_RevertWhen_CallerIsNotOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        wrapper.setRollOverBot(makeAddr("newBot"));
    }

    function test_RevertWhen_RollOverBotIsZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(IWrapperTokenErrors.ZeroAddress.selector);
        wrapper.setRollOverBot(address(0));
    }

    function test_SetRollOverBot_WhenNewBotIsValid() public {
        address newBot = makeAddr("newRollOverBot");

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit IWrapperTokenEvents.RollOverBotSet(rollOverBot, newBot);
        wrapper.setRollOverBot(newBot);

        assertEq(wrapper.rollOverBot(), newBot);
    }
}
