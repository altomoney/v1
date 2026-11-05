// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AltoLeverageSwapperMultiTarget} from "@alto/lending/leverage/AltoLeverageSwapperMultiTarget.sol";
import {IAltoLeverageSwapperMultiTargetErrors} from "@alto/lending/leverage/interfaces/IAltoLeverageSwapper.sol";
import {MockSwapper} from "@alto-test/lending/liquidation/helpers/MockSwapper.sol";
import {AltoLeverageSwapperMultiTargetCommon} from "../SwapperCommon.t.sol";
import {SwapperSwapTests} from "../SwapperSwapTests.t.sol";

contract AltoLeverageSwapperMultiTargetSwapTest is SwapperSwapTests, AltoLeverageSwapperMultiTargetCommon {
    function test_RevertWhen_TargetIsZeroUnlistedOrRevoked_BeforePullingTokens() public {
        _allowCaller();
        vm.prank(OWNER);
        AltoLeverageSwapperMultiTarget(address(swapper)).setValidSwapTarget(address(target), false);
        address[3] memory invalidTargets = [address(0), OTHER, address(target)];
        for (uint256 i; i < invalidTargets.length; ++i) {
            bytes memory params = _encodeParams(invalidTargets[i], 0, hex"ff");
            vm.prank(CALLER);
            vm.expectRevert(
                abi.encodeWithSelector(
                    IAltoLeverageSwapperMultiTargetErrors.AltoLeverageSwapperInvalidSwapTarget.selector,
                    invalidTargets[i]
                )
            );
            swapper.swap(address(sellToken), address(buyToken), type(uint256).max, params);
            _assertBalancesUnchanged();
        }
    }

    function test_WhenAnotherValidTargetIsSelected_UsesOnlyItsBalancesAndAllowance() public {
        _allowCaller();
        address originalTarget = address(target);
        target = new MockSwapper();
        deal(address(buyToken), address(target), TARGET_BUY);
        vm.prank(OWNER);
        AltoLeverageSwapperMultiTarget(address(swapper)).setValidSwapTarget(address(target), true);

        _assertSuccessfulSwap(100 ether, 60 ether, 200 ether, 200 ether, 0);
        assertEq(sellToken.balanceOf(originalTarget), 0);
        assertEq(buyToken.balanceOf(originalTarget), TARGET_BUY);
        assertEq(sellToken.allowance(address(swapper), originalTarget), 0);
    }
}
