// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AltoLeverageSwapper} from "@alto/lending/leverage/AltoLeverageSwapper.sol";
import {IAltoLeverageSwapperErrors} from "@alto/lending/leverage/interfaces/IAltoLeverageSwapper.sol";
import {MockSwapper} from "@alto-test/lending/liquidation/helpers/MockSwapper.sol";

contract AltoLeverageSwapperConstructorTest is Test {
    address internal constant OWNER = address(0xA11CE);

    function test_RevertWhen_OwnerIsZero_BeforeTargetValidation() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new AltoLeverageSwapper(address(0), address(0));
    }

    function test_RevertWhen_TargetIsZero() public {
        vm.expectRevert(IAltoLeverageSwapperErrors.AltoLeverageSwapperInvalidInput.selector);
        new AltoLeverageSwapper(OWNER, address(0));
    }

    function test_WhenTargetHasCode_StoresOwnerAndTargetAndEmitsOnlyOwnership() public {
        _deployAndAssert(address(new MockSwapper()));
    }

    function test_WhenTargetIsAnEoa_AcceptsItsAddress() public {
        address target = address(0xCAFE);
        assertEq(target.code.length, 0);
        _deployAndAssert(target);
    }

    function _deployAndAssert(address target) internal {
        vm.recordLogs();
        AltoLeverageSwapper swapper = new AltoLeverageSwapper(OWNER, target);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(swapper.owner(), OWNER);
        assertEq(swapper.SWAP_TARGET(), target);
        assertFalse(swapper.isWhitelisted(OWNER));
        assertFalse(swapper.isWhitelisted(address(this)));
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(swapper));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], Ownable.OwnershipTransferred.selector);
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(OWNER))));
        assertEq(logs[0].data.length, 0);
    }
}
