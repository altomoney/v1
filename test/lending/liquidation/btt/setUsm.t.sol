// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {LiquidationPeripheryCommon} from "./LiquidationPeripheryCommon.t.sol";
import {DUSD} from "@alto/tokens/DUSD.sol";
import {DUSDAdvancedPermissionsUsm} from "@alto/usm/DUSDAdvancedPermissionsUsm.sol";
import {
    ILiquidationPeripheryErrors,
    ILiquidationPeripheryEvents
} from "@alto/lending/liquidation/interfaces/ILiquidationPeriphery.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract LiquidationPeriphery_SetUsm_Test is LiquidationPeripheryCommon {
    function test_RevertWhen_CallerIsNotOwner() public {
        DUSDAdvancedPermissionsUsm newUsm = _deployUsm(address(borrowToken), address(underlyingToken), ONE_TO_ONE_PRICE_RATIO);

        vm.prank(NON_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NON_OWNER));
        periphery.setUsm(address(newUsm));
    }

    function test_RevertWhen_NewUsmIsZeroAddress() public {
        vm.prank(OWNER);
        vm.expectRevert(ILiquidationPeripheryErrors.ZeroAddress.selector);
        periphery.setUsm(address(0));
    }

    function test_RevertWhen_NewUsmIsAlreadySet() public {
        vm.prank(OWNER);
        vm.expectRevert(ILiquidationPeripheryErrors.AlreadySet.selector);
        periphery.setUsm(address(usm));
    }

    function test_RevertWhen_NewUsmStableTokenDiffersFromBorrowToken() public {
        vm.prank(OWNER);
        DUSD otherStable = new DUSD(address(endpoints[1]), OWNER);
        DUSDAdvancedPermissionsUsm wrongUsm =
            _deployUsm(address(otherStable), address(underlyingToken), ONE_TO_ONE_PRICE_RATIO);

        vm.prank(OWNER);
        vm.expectRevert(ILiquidationPeripheryErrors.InvalidInput.selector);
        periphery.setUsm(address(wrongUsm));
    }

    function test_SetUsm_UpdatesStateAndEmitsEvent() public {
        DUSDAdvancedPermissionsUsm newUsm = _deployUsm(address(borrowToken), address(underlyingToken), ONE_TO_ONE_PRICE_RATIO);

        vm.prank(OWNER);
        vm.expectEmit(true, true, false, true);
        emit ILiquidationPeripheryEvents.UsmSet(address(usm), address(newUsm));
        periphery.setUsm(address(newUsm));
        _grantPeripheryUsmSellPermissionOn(newUsm);

        assertEq(address(periphery.usm()), address(newUsm));
    }
}
