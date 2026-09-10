// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {StdStorage, stdStorage} from "forge-std/StdStorage.sol";

import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";
import {DlbDcfPriorityLiquidationEngine} from "@alto/lending/liquidation/DlbDcfPriorityLiquidationEngine.sol";
import {BaseMarketInitParams, MintMarketInitParams} from "@alto/lending/interfaces/IMarket.sol";
import {PegResponsiveExponentialIrmConfig, IRState} from "@alto/lending/interfaces/IPegResponsiveExponentialIrm.sol";
import {LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {OracleMock} from "@alto/oracles/mocks/OracleMock.sol";
import {IDusdPegOracle} from "@alto/oracles/interfaces/IDusdPegOracle.sol";
import {FixedPointMath} from "@alto/utils/FixedPointMath.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {
    PegResponsiveExponentialIrmHarness
} from "@alto-test/lending/btt/PegResponsiveExponentialIrm/PegResponsiveExponentialIrmHarness.sol";
import {MockDusdPegOracle} from "@alto-test/lending/btt/mocks/MockDusdPegOracle.sol";
import {MockRawDusdPegOracle} from "@alto-test/lending/btt/mocks/MockRawDusdPegOracle.sol";
import {ERC20Mock} from "@alto-test/helpers/ERC20Mock.sol";
import {ERC20MockMintable} from "@alto-test/helpers/ERC20MockMintable.sol";
import {MarketDeployer} from "@alto-test/helpers/MarketDeployer.sol";

abstract contract PegResponsiveExponentialIrmCommon is Test {
    using FixedPointMath for uint256;
    using stdStorage for StdStorage;

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
    uint256 internal constant MARKET_MAX_LTV = 0.75e18;

    MockDusdPegOracle internal oracle;
    MockRawDusdPegOracle internal rawOracle;
    AltoMintMarket internal market;
    PegResponsiveExponentialIrmHarness internal irm;
    PegResponsiveExponentialIrmConfig internal irmConfig;
    ERC20MockMintable internal borrowToken;
    ERC20Mock internal collateralToken;
    OracleMock internal lendingOracle;
    DlbDcfPriorityLiquidationEngine internal liquidationEngine;

    function setUp() public virtual {
        vm.warp(DEFAULT_NOW);

        oracle = new MockDusdPegOracle();
        rawOracle = new MockRawDusdPegOracle();
        irmConfig = _validConfig();
        irm = _deployIrm(irmConfig, address(oracle), OWNER);
        market = _deployMintMarket();
        _setObservation(RECOVERY_PRICE, uint48(block.timestamp), true);
    }

    function _validConfig() internal pure returns (PegResponsiveExponentialIrmConfig memory config) {
        config = PegResponsiveExponentialIrmConfig({
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

    function _deployIrm(PegResponsiveExponentialIrmConfig memory config, address pegOracleAddress, address owner)
        internal
        returns (PegResponsiveExponentialIrmHarness deployedIrm)
    {
        return new PegResponsiveExponentialIrmHarness(pegOracleAddress, config, owner);
    }

    function _deployIrm(PegResponsiveExponentialIrmConfig memory config)
        internal
        returns (PegResponsiveExponentialIrmHarness deployedIrm)
    {
        return _deployIrm(config, address(oracle), OWNER);
    }

    function _bindMarket() internal {
        vm.prank(OWNER);
        market.setIrm(address(irm), true);
        assertEq(market.irm(), address(irm), "market IRM");
        assertEq(irm.market(), address(market), "IRM market");
    }

    function _pauseMarket() internal {
        vm.prank(OWNER);
        market.pause(PAUSE_TYPE, true);
    }

    function _unpauseMarket() internal {
        vm.prank(OWNER);
        market.pause(PAUSE_TYPE, false);
    }

    function _openDebt(uint256 borrowedAssets) internal {
        uint256 collateralAssets = borrowedAssets * 2;
        deal(address(collateralToken), address(this), collateralAssets);
        collateralToken.approve(address(market), collateralAssets);
        market.addCollateral(collateralAssets, address(this));
        market.borrow(borrowedAssets, 0, address(this), address(this), hex"");
    }

    /// @dev Creates a real Mint Market accounting failure after the IRM callback
    /// has executed. Accrued interest fits uint128, but adding it to a saturated
    /// claimableFeesAssets value reverts and rolls back the nested IRM update.
    function _prepareMarketAccrualOverflow() internal {
        _openDebt(1e18);
        stdstore.target(address(market)).sig("claimableFeesAssets()").checked_write(type(uint128).max);
        _setIRState(MAX_RATE, uint48(block.timestamp), 0, false);
        vm.warp(block.timestamp + YEAR);
        _setCurrentObservation(STRESS_PRICE);
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

    function _readIrmConfig() internal view returns (PegResponsiveExponentialIrmConfig memory config) {
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

    function _assertIrmConfig(PegResponsiveExponentialIrmConfig memory expected) internal view {
        PegResponsiveExponentialIrmConfig memory actual = _readIrmConfig();
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

    function _deployMintMarket() private returns (AltoMintMarket deployedMarket) {
        borrowToken = new ERC20MockMintable("DUSD", "DUSD");
        collateralToken = new ERC20Mock("Collateral", "COLL");
        lendingOracle = new OracleMock();
        lendingOracle.setPrice(LENDING_ORACLE_PRICE_PRECISION);

        liquidationEngine = new DlbDcfPriorityLiquidationEngine(OWNER);
        MintMarketInitParams memory params = MintMarketInitParams({
            baseMarketInitParams: BaseMarketInitParams({
                borrowToken: address(borrowToken),
                collateralToken: address(collateralToken),
                irm: address(0),
                owner: OWNER,
                emergencyAdmin: OWNER,
                oracle: address(lendingOracle),
                maxLtv: MARKET_MAX_LTV,
                feeRecipient: OWNER,
                liquidationEngine: address(liquidationEngine)
            }),
            debtCeiling: type(uint128).max,
            initialBorrowOpeningFee: 0
        });

        deployedMarket = AltoMintMarket(MarketDeployer.deployMintMarket(params));
    }

    function _rawOracleData(uint256 priceWord, uint256 observedAtWord, uint256 validWord)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(priceWord, observedAtWord, validWord);
    }
}
