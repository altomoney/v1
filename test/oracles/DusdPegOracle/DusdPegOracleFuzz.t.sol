// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {
    DusdPegCurveOracleRawPoolState,
    DusdPegCurveOracleRuntimeConfig
} from "@alto/oracles/DusdPegCurveOracle/interfaces/IDusdPegCurveOracle.sol";

import {DusdPegCurveOracleCommon} from "@alto-test/oracles/btt/DusdPegCurveOracle/DusdPegCurveOracleCommon.t.sol";

contract DusdPegOracleFuzzTest is DusdPegCurveOracleCommon {
    function testFuzz_ValidTimestampAndPriceAreReturnedExactly(
        uint48 rawObservedAt,
        uint128 invariantUpdatedAt,
        uint256 rawPriceWad
    ) external {
        uint48 observedAt = uint48(bound(rawObservedAt, 1, block.timestamp));
        uint256 priceWad = bound(rawPriceWad, 1, type(uint256).max);
        pool.setMaLastTime(_pack128(observedAt, invariantUpdatedAt));
        _setPoolPriceData(CURRENT_STATE_PRICE_WAD, LAST_STATE_PRICE_WAD, STORED_EMA_PRICE_WAD, priceWad);

        _assertPriceResult(priceWad, observedAt, true);
    }

    function testFuzz_FutureTimestampReturnsCanonicalInvalid(uint128 rawObservedAt, uint128 invariantUpdatedAt)
        external
    {
        uint128 observedAt = uint128(bound(rawObservedAt, block.timestamp + 1, type(uint128).max));
        pool.setMaLastTime(_pack128(observedAt, invariantUpdatedAt));
        _mockPoolReadRevert(_maExpTimeCall());

        _assertPriceResult(0, 0, false);
    }

    function testFuzz_TimestampAboveUint48ReturnsCanonicalInvalidWithoutDowncast(
        uint128 rawObservedAt,
        uint128 invariantUpdatedAt
    ) external {
        uint128 observedAt = uint128(bound(rawObservedAt, uint256(type(uint48).max) + 1, type(uint128).max));
        vm.warp(observedAt);
        pool.setMaLastTime(_pack128(observedAt, invariantUpdatedAt));
        _mockPoolReadRevert(_maExpTimeCall());

        _assertPriceResult(0, 0, false);
    }

    function testFuzz_RuntimeMismatchRejectsObservation(uint8 rawField, uint256 rawMismatchedValue) external {
        uint48 observedAt = uint48(block.timestamp);
        pool.setMaLastTime(_pack128(observedAt, uint128(block.timestamp)));

        uint256 field = bound(rawField, 0, 2);
        if (field == 0) {
            pool.setMaExpTime(_differentFrom(rawMismatchedValue, MA_EXP_TIME));
        } else if (field == 1) {
            pool.setAPrecise(_differentFrom(rawMismatchedValue, A_PRECISE));
        } else {
            pool.setFutureA(_differentFrom(rawMismatchedValue, A_PRECISE));
        }
        _mockPoolReadRevert(_priceOracleCall());

        _assertPriceResult(0, observedAt, false);
    }

    function testFuzz_OwnerCanApproveAnyMatchingNonZeroRuntimeConfig(uint256 rawMaExpTime, uint256 rawAPrecise)
        external
    {
        uint256 maExpTime = bound(rawMaExpTime, 1, type(uint256).max);
        uint256 aPrecise = bound(rawAPrecise, 1, type(uint256).max);
        pool.setMaExpTime(maExpTime);
        pool.setAPrecise(aPrecise);
        pool.setFutureA(aPrecise);

        DusdPegCurveOracleRuntimeConfig memory newConfig =
            DusdPegCurveOracleRuntimeConfig({expectedMaExpTime: maExpTime, expectedAPrecise: aPrecise});
        vm.prank(OWNER);
        oracle.setRuntimeConfig(newConfig);

        _assertRuntimeConfig(oracle, maExpTime, aPrecise);
        _assertPriceResult(PRICE_WAD, PRICE_UPDATED_AT, true);
    }

    function testFuzz_RawPoolStatePreservesEverySourceValue(
        uint128 priceUpdatedAt,
        uint128 invariantUpdatedAt,
        uint256 currentStatePriceWad,
        uint128 lastStatePriceWad,
        uint128 storedEmaPriceWad,
        uint256 currentEmaPriceWad,
        uint256 maExpTime,
        uint256 aPrecise,
        uint256 futureAPrecise,
        uint256 quoteTokenBalance,
        uint256 dusdBalance
    ) external {
        pool.setMaLastTime(_pack128(priceUpdatedAt, invariantUpdatedAt));
        pool.setMaExpTime(maExpTime);
        pool.setAPrecise(aPrecise);
        pool.setFutureA(futureAPrecise);
        pool.setBalances(_uint256Array(quoteTokenBalance, dusdBalance));
        _setPoolPriceData(currentStatePriceWad, lastStatePriceWad, storedEmaPriceWad, currentEmaPriceWad);

        DusdPegCurveOracleRawPoolState memory state = oracle.rawPoolState();

        assertEq(state.currentStatePriceWad, currentStatePriceWad, "currentStatePriceWad");
        assertEq(state.lastStatePriceWad, lastStatePriceWad, "lastStatePriceWad");
        assertEq(state.storedEmaPriceWad, storedEmaPriceWad, "storedEmaPriceWad");
        assertEq(state.currentEmaPriceWad, currentEmaPriceWad, "currentEmaPriceWad");
        assertEq(state.priceUpdatedAt, priceUpdatedAt, "priceUpdatedAt");
        assertEq(state.invariantUpdatedAt, invariantUpdatedAt, "invariantUpdatedAt");
        assertEq(state.maExpTime, maExpTime, "maExpTime");
        assertEq(state.aPrecise, aPrecise, "aPrecise");
        assertEq(state.futureAPrecise, futureAPrecise, "futureAPrecise");
        assertEq(state.quoteTokenBalance, quoteTokenBalance, "quoteTokenBalance");
        assertEq(state.dusdBalance, dusdBalance, "dusdBalance");
    }

    function _differentFrom(uint256 candidate, uint256 expected) private pure returns (uint256) {
        return candidate == expected ? expected + 1 : candidate;
    }
}
