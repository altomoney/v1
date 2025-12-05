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
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {ModuleUniswap} from "@alto/oracles/modules/ModuleUniswap/ModuleUniswap.sol";
import {ModuleChainlink, ConversionDirection} from "@alto/oracles/modules/ModuleChainlink.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {MockUniswapPool} from "@alto-test/oracles/btt/mocks/MockUniswapPool.sol";
import {ERC20MockDecimals} from "@alto-test/helpers/ERC20MockDecimals.sol";
import {UniswapNode} from "@alto/oracles/interfaces/IModuleNode.sol";

contract AltoRewardsOracleConstructor is AltoRewardsOracleCommon {
    modifier givenInvalidInputs() {
        _;
    }

    modifier givenValidInputs() {
        _;
    }

    function test_RevertWhen_UniswapNodeIsInvalid() external givenInvalidInputs {
        AltoRewardsOracleInitParams memory params = _createValidInitParams();

        params.uniswapNode.twapPeriod = 0; // twap period is 0 which is invalid

        vm.expectRevert(ModuleUniswap.ModuleUniswapInvalidInput.selector);
        new AltoRewardsOracle(params);
    }

    function test_RevertWhen_InTokenIsNotAltoToken_WhenDirectionIsInToOut() external givenInvalidInputs {
        AltoRewardsOracleInitParams memory params = _createValidInitParams();
        params.uniswapNode.direction = ConversionDirection.IN_TO_OUT;

        // Create a new pool with non-ALTO token as token0 (inToken for IN_TO_OUT)
        ERC20MockDecimals nonAltoToken = new ERC20MockDecimals("Wrapped Ether", "WETH", 18);
        ERC20MockDecimals otherToken = new ERC20MockDecimals("Out Token", "OUT", 18);
        MockUniswapPool newPool = new MockUniswapPool(address(nonAltoToken), address(otherToken));
        newPool.setTokens(address(nonAltoToken), address(otherToken));

        params.uniswapNode.pool = IUniswapV3Pool(address(newPool));

        vm.expectRevert(IAltoRewardsOracleErrors.AltoRewardsOracleInvalidInput.selector);
        new AltoRewardsOracle(params);
    }

    function test_RevertWhen_InTokenIsNotAltoToken_WhenDirectionIsOutToIn() external givenInvalidInputs {
        AltoRewardsOracleInitParams memory params = _createValidInitParams();
        params.uniswapNode.direction = ConversionDirection.OUT_TO_IN;

        // Create a new pool with non-ALTO token as token1 (inToken for OUT_TO_IN)
        ERC20MockDecimals nonAltoToken = new ERC20MockDecimals("Wrapped Ether", "WETH", 18);
        ERC20MockDecimals otherToken = new ERC20MockDecimals("Out Token", "OUT", 18);
        MockUniswapPool newPool = new MockUniswapPool(address(otherToken), address(nonAltoToken));

        params.uniswapNode.pool = IUniswapV3Pool(address(newPool));

        vm.expectRevert(IAltoRewardsOracleErrors.AltoRewardsOracleInvalidInput.selector);
        new AltoRewardsOracle(params);
    }

    function test_RevertWhen_ChainlinkNodeIsInvalid() external givenInvalidInputs {
        AltoRewardsOracleInitParams memory params = _createValidInitParams();

        // Make circuit arrays length mismatch
        params.chainlinkNode.stalePeriod = 0; // stale period is 0 which is invalid

        vm.expectRevert(ModuleChainlink.ModuleChainlinkInvalidInput.selector);
        new AltoRewardsOracle(params);
    }

    function test_RevertWhen_OwnerIsZeroAddress() external givenInvalidInputs {
        AltoRewardsOracleInitParams memory params = _createValidInitParams();
        params.owner = address(0);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new AltoRewardsOracle(params);
    }

    function test_RevertWhen_PriceUpdateCooldownPeriodIsZero() external givenInvalidInputs {
        AltoRewardsOracleInitParams memory params = _createValidInitParams();
        params.priceUpdateCooldownPeriod = 0;

        vm.expectRevert(IAltoRewardsOracleErrors.AltoRewardsOracleInvalidInput.selector);
        new AltoRewardsOracle(params);
    }

    function test_WhenValidParametersProvided() external givenValidInputs {
        AltoRewardsOracleInitParams memory params = _createValidInitParams();

        vm.expectEmit(false, false, false, true);
        emit IAltoRewardsOracleEvents.PriceUpdateCooldownPeriodUpdated(0, DEFAULT_COOLDOWN_PERIOD);

        AltoRewardsOracle oracle = new AltoRewardsOracle(params);

        // it should set inTokenOneUnit correctly based on in-currency decimals
        assertEq(oracle.inTokenOneUnit(), 10 ** 18);

        // it should set priceUpdateCooldownPeriod correctly
        assertEq(oracle.priceUpdateCooldownPeriod(), DEFAULT_COOLDOWN_PERIOD);

        (IUniswapV3Pool pool, ConversionDirection direction, uint32 twapPeriod) = oracle.uniswapNode();

        // it should set uniswap node correctly
        assertEq(address(pool), address(mockPool));
        assertEq(twapPeriod, DEFAULT_TWAP_PERIOD);
        assertEq(uint8(direction), uint8(ConversionDirection.IN_TO_OUT));

        (
            AggregatorV3Interface feed,
            ConversionDirection chainlinkDirection,
            uint32 stalePeriod,
            uint8 inDecimals,
            uint8 outDecimals
        ) = oracle.chainlinkNode();
        assertEq(address(feed), address(mockFeed));
        assertEq(uint8(chainlinkDirection), uint8(ConversionDirection.IN_TO_OUT));
        assertEq(stalePeriod, DEFAULT_STALE_PERIOD);
        assertEq(inDecimals, 18);
        assertEq(outDecimals, 8);

        // it should set owner correctly
        assertEq(oracle.owner(), OWNER);

        // it should initialize lastPriceUpdateTimestamp to zero
        assertEq(oracle.lastPriceUpdateTimestamp(), 0);

        // it should initialize cachedPrice to zero
        assertEq(oracle.cachedPrice(), 0);
    }
}
