// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {PegResponsiveIrmConfig, IRState} from "@alto/lending/interfaces/IPegResponsiveIrm.sol";
import {IIrm} from "@alto/lending/interfaces/IIrm.sol";
import {IDusdPegOracle} from "@alto/oracles/dusd/interfaces/IDusdPegOracle.sol";
import {FixedPointMath} from "@alto/utils/FixedPointMath.sol";
import {PegResponsiveIrmHarness} from "@alto-test/lending/btt/PegResponsiveIrm/PegResponsiveIrmHarness.sol";
import {MockDusdPegOracle} from "@alto-test/lending/btt/mocks/MockDusdPegOracle.sol";
import {MockPegResponsiveIrmMarket} from "@alto-test/lending/btt/mocks/MockPegResponsiveIrmMarket.sol";
import {MockRawDusdPegOracle} from "@alto-test/lending/btt/mocks/MockRawDusdPegOracle.sol";

abstract contract PegResponsiveIrmCommon is Test {
    using FixedPointMath for uint256;

    address internal constant OWNER = address(0xA11CE);
    address internal constant NON_OWNER = address(0xB0B);
    address internal constant PENDING_OWNER = address(0xCAFE);

    uint256 internal constant DEFAULT_NOW = 1_700_000_000;
    uint256 internal constant YEAR = 365 days;
    uint256 internal constant RECOVERY_PRICE = 1e18;
    uint256 internal constant STRESS_PRICE = 995e15;
    uint256 internal constant MID_BRIDGE_PRICE = 9975e14;
    uint256 internal constant DOUBLING_DISTANCE = 25e14;
    uint256 internal constant BASE_RATE = 5e16 / YEAR;
    uint256 internal constant STRESS_RATE = 75e15 / YEAR;
    uint256 internal constant MAX_RATE = 8e18 / YEAR;
    uint48 internal constant RECOVERY_DELAY = 6 hours;
    uint48 internal constant MAX_ORACLE_AGE = 30 minutes;

    MockDusdPegOracle internal oracle;
    MockRawDusdPegOracle internal rawOracle;
    MockPegResponsiveIrmMarket internal market;
    PegResponsiveIrmHarness internal irm;
    PegResponsiveIrmConfig internal irmConfig;

    function setUp() public virtual {
        vm.warp(DEFAULT_NOW);

        oracle = new MockDusdPegOracle();
        rawOracle = new MockRawDusdPegOracle();
        irmConfig = _validConfig();
        irm = _deployIrm(irmConfig, address(oracle), OWNER);
        market = new MockPegResponsiveIrmMarket(IIrm(address(irm)));
        _setObservation(RECOVERY_PRICE, uint48(block.timestamp), true);
    }

    function _validConfig() internal pure returns (PegResponsiveIrmConfig memory config) {
        config = PegResponsiveIrmConfig({
            recoveryPrice: RECOVERY_PRICE,
            stressPrice: STRESS_PRICE,
            baseRate: BASE_RATE,
            stressRate: STRESS_RATE,
            maxRate: MAX_RATE,
            doublingDistance: DOUBLING_DISTANCE,
            recoveryDelay: RECOVERY_DELAY,
            maxOracleAge: MAX_ORACLE_AGE
        });
    }

    function _deployIrm(PegResponsiveIrmConfig memory config_, address oracle_, address owner_)
        internal
        returns (PegResponsiveIrmHarness deployedIrm)
    {
        return new PegResponsiveIrmHarness(oracle_, config_, owner_);
    }

    function _deployIrm(PegResponsiveIrmConfig memory config_) internal returns (PegResponsiveIrmHarness deployedIrm) {
        return _deployIrm(config_, address(oracle), OWNER);
    }

    function _bindMarket() internal {
        market.bindIrm();
    }

    function _setObservation(uint256 priceWad, uint48 observedAt, bool valid) internal {
        oracle.setPrice(priceWad, observedAt, valid);
    }

    function _setCurrentObservation(uint256 priceWad) internal {
        _setObservation(priceWad, uint48(block.timestamp), true);
    }

    function _setIRState(IRState memory state) internal {
        irm.setIRStateForTest(state);
    }

    function _setIRState(uint256 borrowRate, uint48 lastUpdate, uint48 recoveryStartedAt, bool stressMode) internal {
        _setIRState(
            IRState({
                borrowRate: borrowRate,
                lastUpdate: lastUpdate,
                recoveryStartedAt: recoveryStartedAt,
                stressMode: stressMode
            })
        );
    }

    function _readIRState() internal view returns (IRState memory state) {
        (state.borrowRate, state.lastUpdate, state.recoveryStartedAt, state.stressMode) = irm.irState();
    }

    function _readIrmConfig() internal view returns (PegResponsiveIrmConfig memory config) {
        (
            config.recoveryPrice,
            config.stressPrice,
            config.baseRate,
            config.stressRate,
            config.maxRate,
            config.doublingDistance,
            config.recoveryDelay,
            config.maxOracleAge
        ) = irm.irmConfig();
    }

    function _assertIRState(IRState memory expected) internal view {
        IRState memory actual = _readIRState();
        assertEq(actual.borrowRate, expected.borrowRate, "borrowRate");
        assertEq(actual.lastUpdate, expected.lastUpdate, "lastUpdate");
        assertEq(actual.recoveryStartedAt, expected.recoveryStartedAt, "recoveryStartedAt");
        assertEq(actual.stressMode, expected.stressMode, "stressMode");
    }

    function _assertIrmConfig(PegResponsiveIrmConfig memory expected) internal view {
        PegResponsiveIrmConfig memory actual = _readIrmConfig();
        assertEq(actual.recoveryPrice, expected.recoveryPrice, "recoveryPrice");
        assertEq(actual.stressPrice, expected.stressPrice, "stressPrice");
        assertEq(actual.baseRate, expected.baseRate, "baseRate");
        assertEq(actual.stressRate, expected.stressRate, "stressRate");
        assertEq(actual.maxRate, expected.maxRate, "maxRate");
        assertEq(actual.doublingDistance, expected.doublingDistance, "doublingDistance");
        assertEq(actual.recoveryDelay, expected.recoveryDelay, "recoveryDelay");
        assertEq(actual.maxOracleAge, expected.maxOracleAge, "maxOracleAge");
    }

    function _expectedInterest(uint256 totalBorrowed, uint256 borrowRate, uint256 elapsed)
        internal
        pure
        returns (uint256)
    {
        return totalBorrowed.multiplyWithPrecision(borrowRate.calculateCompoundInterest(elapsed));
    }

    function _getPriceCall() internal pure returns (bytes memory) {
        return abi.encodeWithSelector(IDusdPegOracle.getPrice.selector);
    }

    function _mockOracleReturnData(bytes memory returnData) internal {
        vm.mockCall(address(oracle), _getPriceCall(), returnData);
    }

    function _mockOracleRevert(bytes memory revertData) internal {
        vm.mockCallRevert(address(oracle), _getPriceCall(), revertData);
    }

    function _rawOracleData(uint256 priceWord, uint256 observedAtWord, uint256 validWord)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(priceWord, observedAtWord, validWord);
    }
}
