// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AltoLeverage} from "@alto/lending/leverage/AltoLeverage.sol";
import {SwapperSimpleMock} from "@alto/lending/mocks/SwapperSimpleMock.sol";

contract AltoLeverageConstructorTest is Test {
    address internal constant OWNER = address(0xA11CE);

    function test_RevertWhen_OwnerIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new AltoLeverage(address(0), address(0));
    }

    function test_WhenSwapperHasCode_InitializesOwnershipSwapperAndMarkets() public {
        _deployAndAssert(address(new SwapperSimpleMock(address(this))));
    }

    function test_WhenSwapperIsZeroOrAnEoa_AcceptsItWithoutValidation() public {
        _deployAndAssert(address(0));
        _deployAndAssert(address(0xCAFE));
    }

    function _deployAndAssert(address swapper) internal {
        vm.recordLogs();
        AltoLeverage leverage = new AltoLeverage(swapper, OWNER);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(leverage.owner(), OWNER);
        assertEq(leverage.pendingOwner(), address(0));
        assertEq(address(leverage.swapper()), swapper);
        assertFalse(leverage.supportedMarkets(address(0)));
        assertFalse(leverage.supportedMarkets(OWNER));
        assertFalse(leverage.supportedMarkets(address(this)));
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(leverage));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], Ownable.OwnershipTransferred.selector);
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(OWNER))));
        assertEq(logs[0].data.length, 0);
    }
}
