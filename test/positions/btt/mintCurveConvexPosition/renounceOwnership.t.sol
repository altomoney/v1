// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {MintCurveConvexPositionCommon} from "./MintCurveConvexPositionCommon.t.sol";
import {IMintCurveConvexPositionErrors} from "@alto/positions/interfaces/IMintCurveConvexPosition.sol";

contract MintCurveConvexPosition_RenounceOwnership_Test is MintCurveConvexPositionCommon {
    function test_RevertWhen_CalledByOwner() public {
        vm.prank(OWNER);
        vm.expectRevert(IMintCurveConvexPositionErrors.MintCurveConvexPositionRenounceDisabled.selector);
        position.renounceOwnership();

        assertEq(position.owner(), OWNER, "owner retained");
    }

    function test_RevertWhen_CalledByNonOwner() public {
        vm.prank(NON_AUTHORIZED);
        vm.expectRevert(IMintCurveConvexPositionErrors.MintCurveConvexPositionRenounceDisabled.selector);
        position.renounceOwnership();

        assertEq(position.owner(), OWNER, "owner retained");
    }
}
