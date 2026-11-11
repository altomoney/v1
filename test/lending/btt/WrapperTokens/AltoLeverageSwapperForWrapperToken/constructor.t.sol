// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {AltoLeverageSwapperForWrapperTokenCommon} from "./AltoLeverageSwapperForWrapperTokenCommon.t.sol";
import {AltoLeverageSwapperForWrapperToken} from "@alto/lending/wrappedToken/AltoLeverageSwapperForWrapperToken.sol";
import {
    IAltoLeverageSwapperErrors,
    IAltoLeverageSwapperMultiTargetEvents
} from "@alto/lending/leverage/interfaces/IAltoLeverageSwapper.sol";
import {SwapTargetMock} from "../WrapperToken/mocks/SwapTargetMock.sol";

contract ConstructorTest is AltoLeverageSwapperForWrapperTokenCommon {
    function test_RevertWhen_MarketIsZeroAddress() public {
        address[] memory validSwapTargets = new address[](1);
        validSwapTargets[0] = address(swapTarget);

        vm.expectRevert(IAltoLeverageSwapperErrors.AltoLeverageSwapperInvalidInput.selector);
        new AltoLeverageSwapperForWrapperToken(owner, address(0), validSwapTargets);
    }

    function test_RevertWhen_ValidSwapTargetsContainsZeroAddress() public {
        address[] memory validSwapTargets = new address[](2);
        validSwapTargets[0] = address(swapTarget);
        validSwapTargets[1] = address(0);

        vm.expectRevert(IAltoLeverageSwapperErrors.AltoLeverageSwapperInvalidInput.selector);
        new AltoLeverageSwapperForWrapperToken(owner, address(market), validSwapTargets);
    }

    function test_Constructor_WhenMarketAndAllValidSwapTargetsAreValid() public {
        SwapTargetMock secondSwapTarget = new SwapTargetMock();

        address[] memory validSwapTargets = new address[](2);
        validSwapTargets[0] = address(swapTarget);
        validSwapTargets[1] = address(secondSwapTarget);

        vm.expectEmit(true, true, true, true);
        emit IAltoLeverageSwapperMultiTargetEvents.SetValidSwapTarget(address(swapTarget), true);
        vm.expectEmit(true, true, true, true);
        emit IAltoLeverageSwapperMultiTargetEvents.SetValidSwapTarget(address(secondSwapTarget), true);

        AltoLeverageSwapperForWrapperToken localSwapper =
            new AltoLeverageSwapperForWrapperToken(owner, address(market), validSwapTargets);

        assertEq(localSwapper.MARKET(), address(market));
        assertTrue(localSwapper.isValidSwapTarget(address(swapTarget)));
        assertTrue(localSwapper.isValidSwapTarget(address(secondSwapTarget)));
        assertEq(localSwapper.owner(), owner);
    }
}
