// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AltoLeverageSwapperMultiTarget} from "@alto/lending/leverage/AltoLeverageSwapperMultiTarget.sol";
import {
    IAltoLeverageSwapperErrors,
    IAltoLeverageSwapperMultiTargetEvents
} from "@alto/lending/leverage/interfaces/IAltoLeverageSwapper.sol";
import {MockSwapper} from "@alto-test/lending/liquidation/helpers/MockSwapper.sol";

contract AltoLeverageSwapperMultiTargetConstructorTest is Test {
    address internal constant OWNER = address(0xA11CE);

    function test_RevertWhen_OwnerIsZero_BeforeTargetValidation() public {
        address[] memory targets = new address[](1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new AltoLeverageSwapperMultiTarget(address(0), targets);
    }

    function test_RevertWhen_AnyTargetIsZero_IncludingAfterValidEntries() public {
        for (uint256 i; i < 3; ++i) {
            address[] memory targets = new address[](3);
            targets[0] = address(0x1001);
            targets[1] = address(0x1002);
            targets[2] = address(0x1003);
            targets[i] = address(0);
            vm.expectRevert(IAltoLeverageSwapperErrors.AltoLeverageSwapperInvalidInput.selector);
            new AltoLeverageSwapperMultiTarget(OWNER, targets);
        }
    }

    function test_WhenTargetListIsEmpty_DeploysWithNoValidTargets() public {
        _deployAndAssert(new address[](0));
    }

    function test_WhenTargetsIncludeDuplicatesAndEoas_EmitsForEveryEntryInOrder() public {
        address[] memory targets = new address[](3);
        targets[0] = address(new MockSwapper());
        targets[1] = address(0xCAFE);
        targets[2] = targets[0];
        _deployAndAssert(targets);
    }

    function _deployAndAssert(address[] memory targets) internal {
        vm.recordLogs();
        AltoLeverageSwapperMultiTarget swapper = new AltoLeverageSwapperMultiTarget(OWNER, targets);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(swapper.owner(), OWNER);
        assertFalse(swapper.isWhitelisted(OWNER));
        assertFalse(swapper.isWhitelisted(address(this)));
        assertFalse(swapper.isValidSwapTarget(address(0)));
        assertFalse(swapper.isValidSwapTarget(address(0xDEAD)));
        assertEq(logs.length, targets.length + 1);
        assertEq(logs[0].emitter, address(swapper));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], Ownable.OwnershipTransferred.selector);
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(OWNER))));
        assertEq(logs[0].data.length, 0);
        for (uint256 i; i < targets.length; ++i) {
            assertTrue(swapper.isValidSwapTarget(targets[i]));
            assertEq(logs[i + 1].emitter, address(swapper));
            assertEq(logs[i + 1].topics.length, 2);
            assertEq(logs[i + 1].topics[0], IAltoLeverageSwapperMultiTargetEvents.SetValidSwapTarget.selector);
            assertEq(logs[i + 1].topics[1], bytes32(uint256(uint160(targets[i]))));
            assertEq(logs[i + 1].data, abi.encode(true));
        }
    }
}
