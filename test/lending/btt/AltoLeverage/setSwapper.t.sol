// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {AltoLeverageBTTTest} from "./AltoLeverage.t.sol";
import {IAltoLeverageSwapper} from "@alto/lending/leverage/interfaces/IAltoLeverageSwapper.sol";
import {AltoLeverage} from "@alto/lending/leverage/AltoLeverage.sol";
import {SwapperSimpleMock} from "@alto/deployments/testnet/contracts/SwapperSimpleMock.sol";

contract SetSwapperTest is AltoLeverageBTTTest {
    /// @dev it should revert
    function test_RevertWhen_CallerIsNotOwner() external givenCallerIsNotOwner {
        vm.expectRevert();
        leverage.setSwapper(IAltoLeverageSwapper(address(0x1)));
    }

    /// @dev it should set swapper and emit event
    function test_SetSwapperAndEmitEvent_WhenNewSwapperIsZeroAddress() external givenCallerIsOwner {
        vm.expectEmit(true, true, false, false);
        emit AltoLeverage.SwapperUpdated(address(swapper), address(0));

        leverage.setSwapper(IAltoLeverageSwapper(address(0)));

        assertEq(address(leverage.swapper()), address(0));
    }

    /// @dev it should set swapper and emit event
    function test_SetSwapperAndEmitEvent_WhenNewSwapperIsValidAddress() external givenCallerIsOwner {
        SwapperSimpleMock newSwapper = new SwapperSimpleMock(address(this));

        vm.expectEmit(true, true, false, false);
        emit AltoLeverage.SwapperUpdated(address(swapper), address(newSwapper));

        leverage.setSwapper(IAltoLeverageSwapper(address(newSwapper)));

        assertEq(address(leverage.swapper()), address(newSwapper));
    }

    /// @dev Fuzz test for setting swapper with random addresses
    function testFuzz_SetSwapperAndEmitEvent(address newSwapperAddr) external givenCallerIsOwner {
        vm.expectEmit(true, true, false, false);
        emit AltoLeverage.SwapperUpdated(address(swapper), newSwapperAddr);

        leverage.setSwapper(IAltoLeverageSwapper(newSwapperAddr));

        assertEq(address(leverage.swapper()), newSwapperAddr);
    }
}
