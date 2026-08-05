// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {MintCurveConvexPositionFactoryCommon} from "./MintCurveConvexPositionFactoryCommon.t.sol";
import {MintCurveConvexPositionFactory} from "@alto/positions/MintCurveConvexPositionFactory.sol";
import {
    IMintCurveConvexPositionFactoryErrors,
    IMintCurveConvexPositionFactoryEvents
} from "@alto/positions/interfaces/IMintCurveConvexPositionFactory.sol";
import {IMintCurveConvexPosition} from "@alto/positions/interfaces/IMintCurveConvexPosition.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Vm} from "forge-std/Vm.sol";

contract MintCurveConvexPositionFactoryHarness is MintCurveConvexPositionFactory {
    function seedPositions(address owner, uint256 count) external {
        for (uint256 i = 0; i < count; i++) {
            // Safe because benchmark counts are far below type(uint160).max.
            // forge-lint: disable-next-line(unsafe-typecast)
            address position = address(uint160(i + 1));
            _positionIndex[position] = _positionsOf[owner].length;
            _positionsOf[owner].push(position);
        }
    }
}

contract MintCurveConvexPositionFactory_PositionsOf_Test is MintCurveConvexPositionFactoryCommon {
    uint256 internal constant RPC_BENCHMARK_POSITION_COUNT = 1_000;
    uint256 internal constant REFERENCE_RPC_GAS_CAP = 30_000_000;
    uint256 internal constant REFERENCE_RPC_RESPONSE_CAP = 1_048_576;

    function setUp() public override {
        super.setUp();
        _setBeacon();
    }

    function test_PositionsOf_UnknownOwnerReturnsEmptyArray() public view {
        address[] memory positions = factory.positionsOf(NON_OWNER);

        assertEq(positions.length, 0);
    }

    function test_PositionsOf_OneCreatePositionAppendsReturnedAddress() public {
        vm.prank(USER);
        address position = factory.createPosition(MINT_MARKET);

        address[] memory positions = factory.positionsOf(USER);
        assertEq(positions.length, 1);
        assertEq(positions[0], position);
    }

    function test_PositionsOf_TwoPositionsForSameMarketAreRecordedInCreationOrder() public {
        vm.startPrank(USER);
        address firstPosition = factory.createPosition(MINT_MARKET);
        address secondPosition = factory.createPosition(MINT_MARKET);
        vm.stopPrank();

        address[] memory positions = factory.positionsOf(USER);
        assertEq(positions.length, 2);
        assertEq(positions[0], firstPosition);
        assertEq(positions[1], secondPosition);
    }

    function test_PositionsOf_DifferentOwnersHaveIsolatedLists() public {
        vm.prank(USER);
        address userPosition = factory.createPosition(MINT_MARKET);

        vm.prank(NON_OWNER);
        address nonOwnerPosition = factory.createPosition(MINT_MARKET);

        address[] memory userPositions = factory.positionsOf(USER);
        address[] memory nonOwnerPositions = factory.positionsOf(NON_OWNER);

        assertEq(userPositions.length, 1);
        assertEq(userPositions[0], userPosition);
        assertEq(nonOwnerPositions.length, 1);
        assertEq(nonOwnerPositions[0], nonOwnerPosition);
    }

    function test_PositionsOf_ContentsMatchPositionCreatedEvents() public {
        vm.recordLogs();

        vm.startPrank(USER);
        factory.createPosition(MINT_MARKET);
        factory.createPosition(MINT_MARKET);
        vm.stopPrank();

        address[] memory positions = factory.positionsOf(USER);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 positionCreatedCount;

        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].emitter == address(factory)
                    && logs[i].topics[0] == IMintCurveConvexPositionFactoryEvents.PositionCreated.selector
            ) {
                assertEq(address(uint160(uint256(logs[i].topics[1]))), USER);
                assertEq(address(uint160(uint256(logs[i].topics[2]))), positions[positionCreatedCount]);
                positionCreatedCount++;
            }
        }

        assertEq(positionCreatedCount, positions.length);
        assertEq(positionCreatedCount, 2);
    }

    function test_PositionsOf_OwnershipTransferMovesPositionToNewOwner() public {
        vm.prank(USER);
        address position = factory.createPosition(MINT_MARKET);

        _transferPosition(position, USER, NON_OWNER);

        address[] memory previousOwnerPositions = factory.positionsOf(USER);
        address[] memory newOwnerPositions = factory.positionsOf(NON_OWNER);

        assertEq(OwnableUpgradeable(position).owner(), NON_OWNER);
        assertEq(previousOwnerPositions.length, 0);
        assertEq(newOwnerPositions.length, 1);
        assertEq(newOwnerPositions[0], position);
    }

    function test_PositionsOf_SwapAndPopMaintainsMovedPositionIndex() public {
        vm.startPrank(USER);
        address firstPosition = factory.createPosition(MINT_MARKET);
        address secondPosition = factory.createPosition(MINT_MARKET);
        address thirdPosition = factory.createPosition(MINT_MARKET);
        vm.stopPrank();

        _transferPosition(secondPosition, USER, NON_OWNER);

        address[] memory positionsAfterFirstTransfer = factory.positionsOf(USER);
        assertEq(positionsAfterFirstTransfer.length, 2);
        assertEq(positionsAfterFirstTransfer[0], firstPosition);
        assertEq(positionsAfterFirstTransfer[1], thirdPosition);

        _transferPosition(thirdPosition, USER, OWNER);

        address[] memory userPositions = factory.positionsOf(USER);
        address[] memory ownerPositions = factory.positionsOf(OWNER);
        assertEq(userPositions.length, 1);
        assertEq(userPositions[0], firstPosition);
        assertEq(ownerPositions.length, 1);
        assertEq(ownerPositions[0], thirdPosition);
    }

    function test_PositionsOf_OwnershipRoundTripDoesNotDuplicatePosition() public {
        vm.prank(USER);
        address position = factory.createPosition(MINT_MARKET);

        _transferPosition(position, USER, NON_OWNER);
        _transferPosition(position, NON_OWNER, USER);

        address[] memory userPositions = factory.positionsOf(USER);
        address[] memory nonOwnerPositions = factory.positionsOf(NON_OWNER);
        assertEq(userPositions.length, 1);
        assertEq(userPositions[0], position);
        assertEq(nonOwnerPositions.length, 0);
    }

    function test_RevertWhen_OwnershipCallbackCallerIsNotTrackedPosition() public {
        vm.prank(NON_OWNER);
        vm.expectRevert(IMintCurveConvexPositionFactoryErrors.MintCurveConvexPositionFactoryInvalidPosition.selector);
        factory.onPositionOwnershipTransferred(USER);
    }

    function test_PositionsOf_ThousandPositionRpcReadBenchmark() public {
        vm.pauseGasMetering();
        MintCurveConvexPositionFactoryHarness benchmarkFactory = new MintCurveConvexPositionFactoryHarness();
        benchmarkFactory.seedPositions(USER, RPC_BENCHMARK_POSITION_COUNT);
        vm.cool(address(benchmarkFactory));
        vm.resumeGasMetering();

        uint256 gasBeforeFullRead = gasleft();
        address[] memory positions = benchmarkFactory.positionsOf(USER);
        uint256 fullReadGas = gasBeforeFullRead - gasleft();

        emit log_named_uint("positionsOf(1000) gas", fullReadGas);
        emit log_named_uint("positionsOf(1000) ABI bytes", abi.encode(positions).length);

        assertEq(positions.length, RPC_BENCHMARK_POSITION_COUNT);
        assertEq(abi.encode(positions).length, 32_064);
        assertLt(fullReadGas, REFERENCE_RPC_GAS_CAP);
        assertLt(abi.encode(positions).length, REFERENCE_RPC_RESPONSE_CAP);
    }

    function _transferPosition(address position, address previousOwner, address newOwner) internal {
        vm.prank(previousOwner);
        IMintCurveConvexPosition(position).transferOwnership(newOwner);
        vm.prank(newOwner);
        IMintCurveConvexPosition(position).acceptOwnership();
    }
}
