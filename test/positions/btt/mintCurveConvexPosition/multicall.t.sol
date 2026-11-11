// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {MintCurveConvexPositionCommon} from "./MintCurveConvexPositionCommon.t.sol";
import {MintCurveConvexPosition} from "@alto/positions/MintCurveConvexPosition.sol";
import {IMintCurveConvexPositionErrors} from "@alto/positions/interfaces/IMintCurveConvexPosition.sol";
import {stdError} from "forge-std/StdError.sol";

contract MintCurveConvexPosition_Multicall_Test is MintCurveConvexPositionCommon {
    function test_RevertWhen_CallerIsNotOwnerOrAuthorizedSpender() public {
        bytes[] memory calls = new bytes[](1);
        calls[0] = abi.encodeCall(MintCurveConvexPosition.addCollateral, (DEFAULT_COLLATERAL));

        vm.prank(NON_AUTHORIZED);
        vm.expectRevert(IMintCurveConvexPositionErrors.MintCurveConvexPositionUnauthorized.selector);
        position.multicall(calls);
    }

    function test_Multicall_WhenCallerIsOwner() public {
        _fundOwnerCollateral(DEFAULT_COLLATERAL);

        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(MintCurveConvexPosition.addCollateral, (DEFAULT_COLLATERAL));
        calls[1] = abi.encodeCall(MintCurveConvexPosition.borrowAndDepositToLp, (DEFAULT_BORROW, DEFAULT_BORROW));

        vm.prank(OWNER);
        position.multicall(calls);

        // Both batched calls executed with msg.sender preserved as the authorized owner.
        assertEq(_marketPosition().collateralAssets, DEFAULT_COLLATERAL);
        assertEq(_stakedLpBalance(), DEFAULT_BORROW);
    }

    function test_Multicall_WhenCallerIsAuthorizedSpender() public {
        _authorizeSpender(OWNER, AUTHORIZED_SPENDER);
        // Collateral is pulled from the caller (the authorized spender).
        _fundCollateral(AUTHORIZED_SPENDER, DEFAULT_COLLATERAL);

        bytes[] memory calls = new bytes[](1);
        calls[0] = abi.encodeCall(MintCurveConvexPosition.addCollateral, (DEFAULT_COLLATERAL));

        vm.prank(AUTHORIZED_SPENDER);
        position.multicall(calls);

        assertEq(_marketPosition().collateralAssets, DEFAULT_COLLATERAL);
    }

    function test_Multicall_MixedFunctions_ExecutesInOrderAndReturnsResults() public {
        _fundOwnerCollateral(DEFAULT_COLLATERAL);
        uint256 removeAmount = DEFAULT_COLLATERAL / 2;

        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(MintCurveConvexPosition.addCollateral, (DEFAULT_COLLATERAL));
        calls[1] = abi.encodeCall(MintCurveConvexPosition.removeCollateral, (removeAmount));

        vm.prank(OWNER);
        bytes[] memory results = position.multicall(calls);

        assertEq(results.length, 2, "one result per call");
        // add then remove applied in order.
        assertEq(_marketPosition().collateralAssets, DEFAULT_COLLATERAL - removeAmount);
        assertEq(collateralToken.balanceOf(OWNER), removeAmount, "collateral returned to owner");
    }

    function test_Multicall_WhenOneCallReverts_RevertsEntireBatch() public {
        _fundOwnerCollateral(DEFAULT_COLLATERAL);

        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(MintCurveConvexPosition.addCollateral, (DEFAULT_COLLATERAL));
        // Second call withdraws more than posted, underflowing in the market.
        calls[1] = abi.encodeCall(MintCurveConvexPosition.removeCollateral, (DEFAULT_COLLATERAL * 2));

        vm.prank(OWNER);
        vm.expectRevert(stdError.arithmeticError);
        position.multicall(calls);

        // Batch reverted atomically: the first call's effect was rolled back.
        assertEq(_marketPosition().collateralAssets, 0);
    }

    function test_Multicall_WhenBatchIsEmpty() public {
        bytes[] memory calls = new bytes[](0);

        vm.prank(OWNER);
        bytes[] memory results = position.multicall(calls);

        assertEq(results.length, 0, "empty results array");
    }
}
