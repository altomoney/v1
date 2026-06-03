// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AltoLeverageSwapperForWrapperTokenCommon} from "./AltoLeverageSwapperForWrapperTokenCommon.t.sol";
import {
    IAltoLeverageSwapperErrors,
    IAltoLeverageSwapperEvents
} from "@alto/lending/leverage/interfaces/IAltoLeverageSwapper.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract SetWhitelistedTest is AltoLeverageSwapperForWrapperTokenCommon {
    function test_RevertWhen_CallerIsNotOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        swapper.setWhitelisted(makeAddr("account"), true);
    }

    function test_RevertWhen_IsWhitelistedStatusIsUnchanged() public {
        assertTrue(swapper.isWhitelisted(caller));

        vm.prank(owner);
        vm.expectRevert(IAltoLeverageSwapperErrors.AltoLeverageSwapperInvalidInput.selector);
        swapper.setWhitelisted(caller, true);
    }

    function test_SetWhitelisted_WhenSettingToTrue() public {
        address account = makeAddr("account");
        assertFalse(swapper.isWhitelisted(account));

        vm.prank(owner);
        vm.expectEmit(true, true, true, true, address(swapper));
        emit IAltoLeverageSwapperEvents.SetWhitelisted(account, true);
        swapper.setWhitelisted(account, true);

        assertTrue(swapper.isWhitelisted(account));
    }

    function test_SetWhitelisted_WhenSettingToFalse() public {
        assertTrue(swapper.isWhitelisted(caller));

        vm.prank(owner);
        vm.expectEmit(true, true, true, true, address(swapper));
        emit IAltoLeverageSwapperEvents.SetWhitelisted(caller, false);
        swapper.setWhitelisted(caller, false);

        assertFalse(swapper.isWhitelisted(caller));
    }
}
