// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {DusdPegCurveOracle} from "@alto/oracles/DusdPegCurveOracle/DusdPegCurveOracle.sol";
import {
    DusdPegCurveOracleRuntimeConfig,
    DusdPegCurveOracleValidationConfig
} from "@alto/oracles/interfaces/IDusdPegCurveOracle.sol";
import {ICurveStableSwapNGOracle as ICurveStableSwap} from "@alto/interfaces/curve/ICurveStableSwapNG.sol";
import {MockCurveStableSwapFactory} from "@alto-test/oracles/btt/mocks/MockCurveStableSwapFactory.sol";
import {MockCurveStableSwapNG} from "@alto-test/oracles/btt/mocks/MockCurveStableSwapNG.sol";

abstract contract DusdPegCurveOracleCommon is Test {
    error MockPoolReadReverted(uint256 code);
    error MockFactoryReadReverted(uint256 code);

    uint256 internal constant MOCK_POOL_REVERT_CODE = 0xC0FFEE;
    uint256 internal constant MOCK_FACTORY_REVERT_CODE = 0xFAC7;

    address internal constant OWNER = address(0xA11CE);
    address internal constant NON_OWNER = address(0xB0B);
    address internal constant PENDING_OWNER = address(0xCAFE);
    address internal constant DUSD = address(0xD05D);
    address internal constant QUOTE_TOKEN = address(0xA0B0);
    address internal constant POOL_IMPLEMENTATION = address(0x1A1);

    uint256 internal constant DEFAULT_NOW = 1_700_000_000;
    uint256 internal constant MA_EXP_TIME = 866;
    uint256 internal constant A_PRECISE = 20_000;
    uint256 internal constant PRICE_WAD = 1e18;
    uint256 internal constant CURRENT_STATE_PRICE_WAD = 0.99e18;
    uint128 internal constant LAST_STATE_PRICE_WAD = 1e18;
    uint128 internal constant STORED_EMA_PRICE_WAD = 1e18;
    uint256 internal constant QUOTE_TOKEN_BALANCE = 2_000_000e6;
    uint256 internal constant DUSD_BALANCE = 2_010_000e18;
    uint48 internal constant PRICE_UPDATED_AT = uint48(DEFAULT_NOW - 30);
    uint48 internal constant INVARIANT_UPDATED_AT = uint48(DEFAULT_NOW - 15);

    MockCurveStableSwapNG internal pool;
    MockCurveStableSwapFactory internal factory;
    DusdPegCurveOracle internal oracle;
    DusdPegCurveOracleRuntimeConfig internal runtimeConfig;
    DusdPegCurveOracleValidationConfig internal oracleValidationConfig;

    function setUp() public virtual {
        vm.warp(DEFAULT_NOW);

        pool = new MockCurveStableSwapNG(_addressArray(QUOTE_TOKEN, DUSD), MA_EXP_TIME, A_PRECISE);
        factory = new MockCurveStableSwapFactory();
        runtimeConfig = _validRuntimeConfig();
        oracleValidationConfig = _validValidationConfig();

        _setValidPoolState();
        _setValidFactoryState();
        oracle = _deployOracle();
    }

    function _validRuntimeConfig() internal pure returns (DusdPegCurveOracleRuntimeConfig memory config) {
        config = DusdPegCurveOracleRuntimeConfig({expectedMaExpTime: MA_EXP_TIME, expectedAPrecise: A_PRECISE});
    }

    function _validValidationConfig() internal view returns (DusdPegCurveOracleValidationConfig memory config) {
        config = DusdPegCurveOracleValidationConfig({
            curveFactory: address(factory),
            expectedCurvePoolImplementation: POOL_IMPLEMENTATION,
            dusd: DUSD,
            quoteToken: QUOTE_TOKEN
        });
    }

    function _deployOracle() internal returns (DusdPegCurveOracle deployedOracle) {
        return _deployOracle(runtimeConfig, OWNER);
    }

    function _deployOracle(DusdPegCurveOracleRuntimeConfig memory config, address initialOwner)
        internal
        returns (DusdPegCurveOracle deployedOracle)
    {
        return _deployOracle(address(pool), config, oracleValidationConfig, initialOwner);
    }

    function _deployOracle(
        DusdPegCurveOracleRuntimeConfig memory config,
        DusdPegCurveOracleValidationConfig memory validationConfig,
        address initialOwner
    ) internal returns (DusdPegCurveOracle deployedOracle) {
        return _deployOracle(address(pool), config, validationConfig, initialOwner);
    }

    function _deployOracle(
        address curvePoolAddress,
        DusdPegCurveOracleRuntimeConfig memory config,
        DusdPegCurveOracleValidationConfig memory validationConfig,
        address initialOwner
    ) internal returns (DusdPegCurveOracle deployedOracle) {
        return new DusdPegCurveOracle(curvePoolAddress, config, validationConfig, initialOwner);
    }

    function _setValidPoolState() internal {
        pool.setMaExpTime(MA_EXP_TIME);
        pool.setAPrecise(A_PRECISE);
        pool.setFutureA(A_PRECISE);
        pool.setMaLastTime(_pack128(PRICE_UPDATED_AT, INVARIANT_UPDATED_AT));
        pool.setBalances(_uint256Array(QUOTE_TOKEN_BALANCE, DUSD_BALANCE));
        _setPoolPriceData(CURRENT_STATE_PRICE_WAD, LAST_STATE_PRICE_WAD, STORED_EMA_PRICE_WAD, PRICE_WAD);
    }

    function _setValidFactoryState() internal {
        factory.registerPool(
            address(pool), _addressArray(QUOTE_TOKEN, DUSD), _uint8Array(0, 0), POOL_IMPLEMENTATION, false
        );
    }

    function _setPoolPriceData(
        uint256 currentStatePriceWad,
        uint128 lastStatePriceWad,
        uint128 storedEmaPriceWad,
        uint256 projectedEmaPriceWad
    ) internal {
        pool.setPriceData(0, currentStatePriceWad, lastStatePriceWad, storedEmaPriceWad, projectedEmaPriceWad);
    }

    function _pack128(uint128 low, uint128 high) internal pure returns (uint256 packed) {
        return uint256(low) | (uint256(high) << 128);
    }

    function _mockPoolReturn(bytes memory callData, bytes memory returnData) internal {
        vm.mockCall(address(pool), callData, returnData);
    }

    function _mockPoolReturn(bytes memory callData, uint256 value) internal {
        _mockPoolReturn(callData, abi.encode(value));
    }

    function _mockFactoryReturn(bytes memory callData, bytes memory returnData) internal {
        vm.mockCall(address(factory), callData, returnData);
    }

    function _mockPoolReadRevert(bytes memory callData) internal {
        vm.mockCallRevert(address(pool), callData, _poolReadRevertData());
    }

    function _mockFactoryReadRevert(bytes memory callData) internal {
        vm.mockCallRevert(address(factory), callData, _factoryReadRevertData());
    }

    function _expectPoolReadRevert() internal {
        vm.expectRevert(_poolReadRevertData());
    }

    function _expectFactoryReadRevert() internal {
        vm.expectRevert(_factoryReadRevertData());
    }

    function _poolReadRevertData() internal pure returns (bytes memory) {
        return abi.encodeWithSelector(MockPoolReadReverted.selector, MOCK_POOL_REVERT_CODE);
    }

    function _factoryReadRevertData() internal pure returns (bytes memory) {
        return abi.encodeWithSelector(MockFactoryReadReverted.selector, MOCK_FACTORY_REVERT_CODE);
    }

    function _assertPriceResult(uint256 expectedPriceWad, uint48 expectedObservedAt, bool expectedValid) internal view {
        (uint256 priceWad, uint48 observedAt, bool valid) = oracle.getPrice();

        assertEq(priceWad, expectedPriceWad, "priceWad");
        assertEq(observedAt, expectedObservedAt, "observedAt");
        assertEq(valid, expectedValid, "valid");
    }

    function _assertRuntimeConfig(
        DusdPegCurveOracle deployedOracle,
        uint256 expectedMaExpTime,
        uint256 expectedAPrecise
    ) internal view {
        (uint256 actualMaExpTime, uint256 actualAPrecise) = deployedOracle.runtimeConfig();
        assertEq(actualMaExpTime, expectedMaExpTime, "expectedMaExpTime");
        assertEq(actualAPrecise, expectedAPrecise, "expectedAPrecise");
    }

    function _maLastTimeCall() internal pure returns (bytes memory) {
        return abi.encodeWithSelector(ICurveStableSwap.ma_last_time.selector);
    }

    function _getBalancesCall() internal pure returns (bytes memory) {
        return abi.encodeWithSelector(ICurveStableSwap.get_balances.selector);
    }

    function _getPCall() internal pure returns (bytes memory) {
        return abi.encodeWithSelector(ICurveStableSwap.get_p.selector, uint256(0));
    }

    function _lastPriceCall() internal pure returns (bytes memory) {
        return abi.encodeWithSelector(ICurveStableSwap.last_price.selector, uint256(0));
    }

    function _emaPriceCall() internal pure returns (bytes memory) {
        return abi.encodeWithSelector(ICurveStableSwap.ema_price.selector, uint256(0));
    }

    function _priceOracleCall() internal pure returns (bytes memory) {
        return abi.encodeWithSelector(ICurveStableSwap.price_oracle.selector, uint256(0));
    }

    function _maExpTimeCall() internal pure returns (bytes memory) {
        return abi.encodeWithSelector(ICurveStableSwap.ma_exp_time.selector);
    }

    function _aPreciseCall() internal pure returns (bytes memory) {
        return abi.encodeWithSelector(ICurveStableSwap.A_precise.selector);
    }

    function _futureACall() internal pure returns (bytes memory) {
        return abi.encodeWithSelector(ICurveStableSwap.future_A.selector);
    }

    function _addressArray(address value0) internal pure returns (address[] memory values) {
        values = new address[](1);
        values[0] = value0;
    }

    function _addressArray(address value0, address value1) internal pure returns (address[] memory values) {
        values = new address[](2);
        values[0] = value0;
        values[1] = value1;
    }

    function _addressArray(address value0, address value1, address value2)
        internal
        pure
        returns (address[] memory values)
    {
        values = new address[](3);
        values[0] = value0;
        values[1] = value1;
        values[2] = value2;
    }

    function _uint8Array(uint8 value0) internal pure returns (uint8[] memory values) {
        values = new uint8[](1);
        values[0] = value0;
    }

    function _uint8Array(uint8 value0, uint8 value1) internal pure returns (uint8[] memory values) {
        values = new uint8[](2);
        values[0] = value0;
        values[1] = value1;
    }

    function _uint8Array(uint8 value0, uint8 value1, uint8 value2) internal pure returns (uint8[] memory values) {
        values = new uint8[](3);
        values[0] = value0;
        values[1] = value1;
        values[2] = value2;
    }

    function _uint256Array() internal pure returns (uint256[] memory values) {
        return new uint256[](0);
    }

    function _uint256Array(uint256 value0) internal pure returns (uint256[] memory values) {
        values = new uint256[](1);
        values[0] = value0;
    }

    function _uint256Array(uint256 value0, uint256 value1) internal pure returns (uint256[] memory values) {
        values = new uint256[](2);
        values[0] = value0;
        values[1] = value1;
    }
}
