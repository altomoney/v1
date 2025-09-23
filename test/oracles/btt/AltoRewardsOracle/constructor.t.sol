// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {AltoRewardsOracleCommon} from "./AltoRewardsOracleCommon.t.sol";
import {AltoRewardsOracle} from "@alto/oracles/AltoRewardsOracle.sol";
import {
    AltoRewardsOracleInitParams,
    IAltoRewardsOracleErrors,
    IAltoRewardsOracleEvents
} from "@alto/oracles/interfaces/IAltoRewardsOracle.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20MockDecimals} from "@alto-test/helpers/ERC20MockDecimals.sol";
import {UniswapUtils} from "@alto/oracles/utils/UniswapUtils.sol";
import {ModuleUniswapMulti} from "@alto/oracles/modules/ModuleUniswapMulti.sol";
import {ModuleChainlinkMulti} from "@alto/oracles/modules/ModuleChainlinkMulti.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

contract AltoRewardsOracleConstructor is AltoRewardsOracleCommon {
    modifier givenInvalidInputs() {
        _;
    }

    modifier givenValidInputs() {
        _;
    }

    function test_RevertWhen_AddressInAndOutUniLengthIsNot2() external givenInvalidInputs {
        AltoRewardsOracleInitParams memory params = _createInvalidAddressArrayInitParams();

        vm.expectRevert(IAltoRewardsOracleErrors.AltoRewardsOracleInvalidInput.selector);
        new AltoRewardsOracle(params);
    }

    function test_RevertWhen_OwnerIsZeroAddress() external givenInvalidInputs {
        AltoRewardsOracleInitParams memory params = _createZeroOwnerInitParams();

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new AltoRewardsOracle(params);
    }

    function test_RevertWhen_TwapPeriodIsInvalid() external givenInvalidInputs {
        AltoRewardsOracleInitParams memory params = _createValidInitParams();
        params.twapPeriod = 0; // Invalid twap period

        vm.expectRevert(UniswapUtils.UniswapUtilsInvalidTwapPeriod.selector);
        new AltoRewardsOracle(params);
    }

    function test_RevertWhen_CircuitUniswapParametersAreInvalid() external givenInvalidInputs {
        AltoRewardsOracleInitParams memory params = _createValidInitParams();

        // Make circuit arrays length mismatch
        IUniswapV3Pool[] memory circuitUniswap = new IUniswapV3Pool[](2); // length 2
        uint8[] memory circuitUniIsMultiplied = new uint8[](1); // length 1 - mismatch!

        params.circuitUniswap = circuitUniswap;
        params.circuitUniIsMultiplied = circuitUniIsMultiplied;

        vm.expectRevert(ModuleUniswapMulti.ModuleUniswapMultiInvalidInput.selector);
        new AltoRewardsOracle(params);
    }

    function test_RevertWhen_CircuitChainlinkParametersAreInvalid() external givenInvalidInputs {
        AltoRewardsOracleInitParams memory params = _createValidInitParams();

        // Make circuit arrays length mismatch
        address[] memory circuitChainlink = new address[](2); // length 2
        uint8[] memory circuitChainIsMultiplied = new uint8[](1); // length 1 - mismatch!

        params.circuitChainlink = circuitChainlink;
        params.circuitChainIsMultiplied = circuitChainIsMultiplied;

        vm.expectRevert(ModuleChainlinkMulti.ModuleChainlinkMultiInvalidInput.selector);
        new AltoRewardsOracle(params);
    }

    function test_WhenValidParametersProvided() external givenValidInputs {
        AltoRewardsOracleInitParams memory params = _createValidInitParams();

        vm.expectEmit(false, false, false, true);
        emit IAltoRewardsOracleEvents.PriceUpdateCooldownPeriodUpdated(0, DEFAULT_COOLDOWN_PERIOD);

        AltoRewardsOracle oracle = new AltoRewardsOracle(params);

        // it should set IN_BASE correctly based on in-currency decimals
        assertEq(oracle.IN_BASE(), 10 ** 18);

        // it should set OUT_BASE correctly based on out-currency decimals
        assertEq(oracle.OUT_BASE(), 10 ** 18);

        // it should set UNI_FINAL_CURRENCY correctly
        assertEq(oracle.UNI_FINAL_CURRENCY(), DEFAULT_UNI_FINAL_CURRENCY);

        // it should set description correctly
        assertEq(oracle.description(), DEFAULT_DESCRIPTION);

        // it should set priceUpdateCooldownPeriod correctly
        assertEq(oracle.priceUpdateCooldownPeriod(), DEFAULT_COOLDOWN_PERIOD);

        // it should set twap period correctly
        assertEq(oracle.twapPeriod(), DEFAULT_TWAP_PERIOD);

        // it should set circuit uniswap correctly
        assertEq(address(oracle.circuitUniswap(0)), address(mockPool));

        // it should set circuit uni is multiplied correctly
        assertEq(oracle.circuitUniIsMultiplied(0), 1);

        // it should set circuit chainlink correctly
        assertEq(address(oracle.circuitChainlink(0)), address(mockFeed));

        // it should set circuit chain is multiplied correctly
        assertEq(oracle.circuitChainIsMultiplied(0), 1);

        // it should set stale period correctly
        assertEq(oracle.stalePeriod(), DEFAULT_STALE_PERIOD);

        // it should set owner correctly
        assertEq(oracle.owner(), OWNER);

        // it should initialize lastPriceUpdateTimestamp to zero
        assertEq(oracle.lastPriceUpdateTimestamp(), 0);

        // it should initialize cachedPrice to zero
        assertEq(oracle.cachedPrice(), 0);
    }

    function test_WhenBothTokensHaveDifferentDecimalPlaces() external givenValidInputs {
        (ERC20MockDecimals inToken6, ERC20MockDecimals outToken8) = _createTokensWithDecimals(6, 8);

        AltoRewardsOracleInitParams memory params = _createValidInitParams();
        params.addressInAndOutUni[0] = address(inToken6);
        params.addressInAndOutUni[1] = address(outToken8);

        AltoRewardsOracle oracle = new AltoRewardsOracle(params);

        // it should handle different decimal tokens correctly
        assertEq(oracle.IN_BASE(), 10 ** 6);
        assertEq(oracle.OUT_BASE(), 10 ** 8);
    }
}
