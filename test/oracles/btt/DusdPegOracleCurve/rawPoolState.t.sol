// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Vm} from "forge-std/Vm.sol";
import {stdError} from "forge-std/StdError.sol";

import {DusdPegOracleCurveRawPoolState} from "@alto/oracles/dusd/interfaces/IDusdPegOracleCurve.sol";
import {DusdPegOracleCurveCommon} from "./DusdPegOracleCurveCommon.t.sol";

contract DusdPegOracleCurveRawPoolStateTest is DusdPegOracleCurveCommon {
    uint256 private constant CURRENT_STATE_PRICE = 0.91 ether;
    uint256 private constant LAST_STATE_PRICE = 0.92 ether;
    uint256 private constant STORED_EMA_PRICE = 0.93 ether;
    uint256 private constant CURRENT_EMA_PRICE = 0.94 ether;
    uint256 private constant RAW_PRICE_UPDATED_AT = 101;
    uint256 private constant RAW_INVARIANT_UPDATED_AT = 202;
    uint256 private constant RAW_MA_EXP_TIME = 303;
    uint256 private constant RAW_A_PRECISE = 404;
    uint256 private constant RAW_FUTURE_A = 505;
    uint256 private constant QUOTE_BALANCE = 606;
    uint256 private constant RAW_DUSD_BALANCE = 707;

    function test_RevertWhen_MaLastTimeReverts() external {
        _assertRawReadReverts(_maLastTimeCall());
    }

    function test_RevertWhen_GetBalancesReverts() external {
        _assertRawReadReverts(_getBalancesCall());
    }

    function test_RevertWhen_GetPReverts() external {
        _assertRawReadReverts(_getPCall());
    }

    function test_RevertWhen_LastPriceReverts() external {
        _assertRawReadReverts(_lastPriceCall());
    }

    function test_RevertWhen_EmaPriceReverts() external {
        _assertRawReadReverts(_emaPriceCall());
    }

    function test_RevertWhen_PriceOracleReverts() external {
        _assertRawReadReverts(_priceOracleCall());
    }

    function test_RevertWhen_MaExpTimeReverts() external {
        _assertRawReadReverts(_maExpTimeCall());
    }

    function test_RevertWhen_APreciseReverts() external {
        _assertRawReadReverts(_aPreciseCall());
    }

    function test_RevertWhen_FutureAReverts() external {
        _assertRawReadReverts(_futureACall());
    }

    function test_RevertWhen_GetBalancesReturnsAnEmptyArray() external {
        _mockBalances(_uint256Array());

        vm.expectRevert(stdError.indexOOBError);
        oracle.rawPoolState();
    }

    function test_RevertWhen_GetBalancesReturnsOneElement() external {
        _mockBalances(_uint256Array(QUOTE_BALANCE));

        vm.expectRevert(stdError.indexOOBError);
        oracle.rawPoolState();
    }

    function test_WhenGetBalancesReturnsTwoElements() external {
        _mockBalances(_uint256Array(QUOTE_BALANCE, RAW_DUSD_BALANCE));

        DusdPegOracleCurveRawPoolState memory state = oracle.rawPoolState();

        assertEq(state.quoteTokenBalance, QUOTE_BALANCE);
        assertEq(state.dusdBalance, RAW_DUSD_BALANCE);
    }

    function test_WhenGetBalancesReturnsMoreThanTwoElements() external {
        uint256[] memory balances = new uint256[](4);
        balances[0] = QUOTE_BALANCE;
        balances[1] = RAW_DUSD_BALANCE;
        balances[2] = 808;
        balances[3] = 909;
        _mockBalances(balances);

        DusdPegOracleCurveRawPoolState memory state = oracle.rawPoolState();

        assertEq(state.quoteTokenBalance, QUOTE_BALANCE);
        assertEq(state.dusdBalance, RAW_DUSD_BALANCE);
    }

    function test_WhenEveryReadSucceeds_ItMapsEveryRawFieldAndOracleIndex() external {
        _mockDistinctRawState();
        vm.expectCall(address(pool), _getPCall(), 1);
        vm.expectCall(address(pool), _lastPriceCall(), 1);
        vm.expectCall(address(pool), _emaPriceCall(), 1);
        vm.expectCall(address(pool), _priceOracleCall(), 1);

        DusdPegOracleCurveRawPoolState memory state = oracle.rawPoolState();

        _assertDistinctRawState(state);
    }

    function test_WhenRawValuesAreZeroOrInconsistent_ItDoesNotValidateThem() external {
        _mockPoolReturn(_maLastTimeCall(), 0);
        _mockBalances(_uint256Array(0, 0));
        _mockPoolReturn(_getPCall(), 0);
        _mockPoolReturn(_lastPriceCall(), 11);
        _mockPoolReturn(_emaPriceCall(), 0);
        _mockPoolReturn(_priceOracleCall(), 22);
        _mockPoolReturn(_maExpTimeCall(), 0);
        _mockPoolReturn(_aPreciseCall(), 33);
        _mockPoolReturn(_futureACall(), 44);

        DusdPegOracleCurveRawPoolState memory state = oracle.rawPoolState();

        assertEq(state.currentStatePriceWad, 0);
        assertEq(state.lastStatePriceWad, 11);
        assertEq(state.storedEmaPriceWad, 0);
        assertEq(state.currentEmaPriceWad, 22);
        assertEq(state.priceUpdatedAt, 0);
        assertEq(state.invariantUpdatedAt, 0);
        assertEq(state.maExpTime, 0);
        assertEq(state.aPrecise, 33);
        assertEq(state.futureAPrecise, 44);
        assertEq(state.quoteTokenBalance, 0);
        assertEq(state.dusdBalance, 0);
    }

    function test_WhenRuntimeChecksToggle_ItReturnsTheSameSnapshot() external {
        _mockDistinctRawState();

        DusdPegOracleCurveRawPoolState memory enabledState = oracle.rawPoolState();

        vm.prank(OWNER);
        oracle.setRuntimeChecks(false);
        DusdPegOracleCurveRawPoolState memory disabledState = oracle.rawPoolState();

        assertEq(keccak256(abi.encode(disabledState)), keccak256(abi.encode(enabledState)));
    }

    function test_WhenExecutionSucceeds_ItDoesNotModifyStateOrEmitEvents() external {
        _mockDistinctRawState();
        address ownerBefore = oracle.owner();
        address pendingOwnerBefore = oracle.pendingOwner();
        bool runtimeChecksBefore = oracle.runtimeConfigChecksEnabled();

        vm.recordLogs();
        oracle.rawPoolState();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(oracle.owner(), ownerBefore);
        assertEq(oracle.pendingOwner(), pendingOwnerBefore);
        assertEq(oracle.runtimeConfigChecksEnabled(), runtimeChecksBefore);
        assertEq(logs.length, 0);
    }

    function _assertRawReadReverts(bytes memory callData) private {
        _mockPoolReadRevert(callData);
        _expectPoolReadRevert();
        oracle.rawPoolState();
    }

    function _mockDistinctRawState() private {
        uint256 packedTimestamps = RAW_PRICE_UPDATED_AT | (RAW_INVARIANT_UPDATED_AT << 128);
        _mockPoolReturn(_maLastTimeCall(), packedTimestamps);
        _mockBalances(_uint256Array(QUOTE_BALANCE, RAW_DUSD_BALANCE));
        _mockPoolReturn(_getPCall(), CURRENT_STATE_PRICE);
        _mockPoolReturn(_lastPriceCall(), LAST_STATE_PRICE);
        _mockPoolReturn(_emaPriceCall(), STORED_EMA_PRICE);
        _mockPoolReturn(_priceOracleCall(), CURRENT_EMA_PRICE);
        _mockPoolReturn(_maExpTimeCall(), RAW_MA_EXP_TIME);
        _mockPoolReturn(_aPreciseCall(), RAW_A_PRECISE);
        _mockPoolReturn(_futureACall(), RAW_FUTURE_A);
    }

    function _assertDistinctRawState(DusdPegOracleCurveRawPoolState memory state) private pure {
        assertEq(state.currentStatePriceWad, CURRENT_STATE_PRICE);
        assertEq(state.lastStatePriceWad, LAST_STATE_PRICE);
        assertEq(state.storedEmaPriceWad, STORED_EMA_PRICE);
        assertEq(state.currentEmaPriceWad, CURRENT_EMA_PRICE);
        assertEq(state.priceUpdatedAt, RAW_PRICE_UPDATED_AT);
        assertEq(state.invariantUpdatedAt, RAW_INVARIANT_UPDATED_AT);
        assertEq(state.maExpTime, RAW_MA_EXP_TIME);
        assertEq(state.aPrecise, RAW_A_PRECISE);
        assertEq(state.futureAPrecise, RAW_FUTURE_A);
        assertEq(state.quoteTokenBalance, QUOTE_BALANCE);
        assertEq(state.dusdBalance, RAW_DUSD_BALANCE);
    }

    function _mockBalances(uint256[] memory balances) private {
        _mockPoolReturn(_getBalancesCall(), abi.encode(balances));
    }
}
