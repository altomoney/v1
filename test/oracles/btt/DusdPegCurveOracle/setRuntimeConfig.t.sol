// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Vm} from "forge-std/Vm.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {
    DusdPegCurveOracleRuntimeConfig,
    IDusdPegCurveOracleErrors,
    IDusdPegCurveOracleEvents
} from "@alto/oracles/DusdPegCurveOracle/interfaces/IDusdPegCurveOracle.sol";
import {DusdPegCurveOracleCommon} from "./DusdPegCurveOracleCommon.t.sol";

contract DusdPegCurveOracleSetRuntimeConfigTest is DusdPegCurveOracleCommon {
    uint256 private constant NEW_MA_EXP_TIME = MA_EXP_TIME + 1;
    uint256 private constant NEW_A_PRECISE = A_PRECISE + 1;

    function test_RevertWhen_CallerIsNotOwner() external {
        _setNewPoolConfig();

        vm.recordLogs();
        vm.prank(NON_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NON_OWNER));
        oracle.setRuntimeConfig(_newRuntimeConfig());
        Vm.Log[] memory logs = vm.getRecordedLogs();

        _assertStoredConfig(MA_EXP_TIME, A_PRECISE);
        assertEq(logs.length, 0);
    }

    function test_RevertWhen_CallerIsPendingOwner() external {
        vm.prank(OWNER);
        oracle.transferOwnership(PENDING_OWNER);
        _setNewPoolConfig();

        vm.recordLogs();
        vm.prank(PENDING_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, PENDING_OWNER));
        oracle.setRuntimeConfig(_newRuntimeConfig());
        Vm.Log[] memory logs = vm.getRecordedLogs();

        _assertStoredConfig(MA_EXP_TIME, A_PRECISE);
        assertEq(logs.length, 0);
    }

    function test_RevertWhen_NewMaExpTimeIsZero() external {
        vm.prank(OWNER);
        vm.expectRevert(IDusdPegCurveOracleErrors.DusdPegCurveOracleInvalidConfig.selector);
        oracle.setRuntimeConfig(
            DusdPegCurveOracleRuntimeConfig({expectedMaExpTime: 0, expectedAPrecise: NEW_A_PRECISE})
        );

        _assertStoredConfig(MA_EXP_TIME, A_PRECISE);
    }

    function test_RevertWhen_NewAPreciseIsZero() external {
        vm.prank(OWNER);
        vm.expectRevert(IDusdPegCurveOracleErrors.DusdPegCurveOracleInvalidConfig.selector);
        oracle.setRuntimeConfig(
            DusdPegCurveOracleRuntimeConfig({expectedMaExpTime: NEW_MA_EXP_TIME, expectedAPrecise: 0})
        );

        _assertStoredConfig(MA_EXP_TIME, A_PRECISE);
    }

    function test_RevertWhen_MaExpTimeReadReverts() external {
        _mockPoolReadRevert(_maExpTimeCall());

        vm.prank(OWNER);
        _expectPoolReadRevert();
        oracle.setRuntimeConfig(_newRuntimeConfig());

        _assertStoredConfig(MA_EXP_TIME, A_PRECISE);
    }

    function test_RevertWhen_MaExpTimeDoesNotMatch() external {
        vm.prank(OWNER);
        vm.expectRevert(IDusdPegCurveOracleErrors.DusdPegCurveOracleInvalidMaExpTime.selector);
        oracle.setRuntimeConfig(_newRuntimeConfig());

        _assertStoredConfig(MA_EXP_TIME, A_PRECISE);
    }

    function test_RevertWhen_APreciseReadReverts() external {
        pool.setMaExpTime(NEW_MA_EXP_TIME);
        _mockPoolReadRevert(_aPreciseCall());

        vm.prank(OWNER);
        _expectPoolReadRevert();
        oracle.setRuntimeConfig(_newRuntimeConfig());

        _assertStoredConfig(MA_EXP_TIME, A_PRECISE);
    }

    function test_RevertWhen_APreciseDoesNotMatch() external {
        pool.setMaExpTime(NEW_MA_EXP_TIME);

        vm.prank(OWNER);
        vm.expectRevert(IDusdPegCurveOracleErrors.DusdPegCurveOracleInvalidAmplification.selector);
        oracle.setRuntimeConfig(_newRuntimeConfig());

        _assertStoredConfig(MA_EXP_TIME, A_PRECISE);
    }

    function test_RevertWhen_FutureAReadReverts() external {
        pool.setMaExpTime(NEW_MA_EXP_TIME);
        pool.setAPrecise(NEW_A_PRECISE);
        _mockPoolReadRevert(_futureACall());

        vm.prank(OWNER);
        _expectPoolReadRevert();
        oracle.setRuntimeConfig(_newRuntimeConfig());

        _assertStoredConfig(MA_EXP_TIME, A_PRECISE);
    }

    function test_RevertWhen_FutureADoesNotMatch() external {
        pool.setMaExpTime(NEW_MA_EXP_TIME);
        pool.setAPrecise(NEW_A_PRECISE);

        vm.prank(OWNER);
        vm.expectRevert(IDusdPegCurveOracleErrors.DusdPegCurveOracleInvalidAmplification.selector);
        oracle.setRuntimeConfig(_newRuntimeConfig());

        _assertStoredConfig(MA_EXP_TIME, A_PRECISE);
    }

    function test_WhenNewConfigMatchesPool_UpdatesBothValuesAndEmits() external {
        _setNewPoolConfig();
        address ownerBefore = oracle.owner();
        address pendingOwnerBefore = oracle.pendingOwner();

        vm.expectEmit(false, false, false, true, address(oracle));
        emit IDusdPegCurveOracleEvents.SetRuntimeConfig(_newRuntimeConfig());

        vm.prank(OWNER);
        oracle.setRuntimeConfig(_newRuntimeConfig());

        _assertStoredConfig(NEW_MA_EXP_TIME, NEW_A_PRECISE);
        _assertPriceResult(PRICE_WAD, PRICE_UPDATED_AT, true);
        assertEq(oracle.owner(), ownerBefore);
        assertEq(oracle.pendingOwner(), pendingOwnerBefore);
    }

    function test_WhenConfigEqualsStoredValues_StillValidatesAndEmits() external {
        vm.expectEmit(false, false, false, true, address(oracle));
        emit IDusdPegCurveOracleEvents.SetRuntimeConfig(runtimeConfig);

        vm.prank(OWNER);
        oracle.setRuntimeConfig(runtimeConfig);

        _assertStoredConfig(MA_EXP_TIME, A_PRECISE);
    }

    function _setNewPoolConfig() private {
        pool.setMaExpTime(NEW_MA_EXP_TIME);
        pool.setAPrecise(NEW_A_PRECISE);
        pool.setFutureA(NEW_A_PRECISE);
    }

    function _newRuntimeConfig() private pure returns (DusdPegCurveOracleRuntimeConfig memory config) {
        config = DusdPegCurveOracleRuntimeConfig({expectedMaExpTime: NEW_MA_EXP_TIME, expectedAPrecise: NEW_A_PRECISE});
    }

    function _assertStoredConfig(uint256 expectedMaExpTime, uint256 expectedAPrecise) private view {
        _assertRuntimeConfig(oracle, expectedMaExpTime, expectedAPrecise);
    }
}
