// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {AltoRewardsOracleInitParams} from "@alto/oracles/interfaces/IAltoRewardsOracle.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {ERC20MockDecimals} from "@alto-test/helpers/ERC20MockDecimals.sol";
import {MockUniswapPool} from "@alto-test/oracles/btt/mocks/MockUniswapPool.sol";
import {MockChainlinkFeed} from "@alto-test/oracles/btt/mocks/MockChainlinkFeed.sol";
import {UniswapNode, ChainlinkNode, ConversionDirection} from "@alto/oracles/interfaces/IModuleNode.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract AltoRewardsOracleCommon is Test {
    address constant OWNER = address(0x1);
    address constant NON_OWNER = address(0x2);

    ERC20MockDecimals inToken;
    ERC20MockDecimals outToken;
    MockUniswapPool mockPool;
    MockChainlinkFeed mockFeed;
    ChainlinkNode chainlinkNode;
    UniswapNode uniswapNode;

    // Default valid parameters
    uint32 constant DEFAULT_TWAP_PERIOD = 1 hours;
    uint16 constant DEFAULT_OBSERVATION_LENGTH = 100;
    uint8 constant DEFAULT_UNI_FINAL_CURRENCY = 0;
    uint32 constant DEFAULT_STALE_PERIOD = 1 days;
    uint256 constant DEFAULT_COOLDOWN_PERIOD = 1 hours;

    function setUp() public virtual {
        inToken = new ERC20MockDecimals("ALTO", "ALTO", 18);
        outToken = new ERC20MockDecimals("Wrapped Ether", "WETH", 18);
        mockPool = new MockUniswapPool(address(inToken), address(outToken));
        mockFeed = new MockChainlinkFeed();
    }

    function _createValidInitParams() internal returns (AltoRewardsOracleInitParams memory) {
        chainlinkNode = ChainlinkNode({
            feed: AggregatorV3Interface(address(mockFeed)),
            stalePeriod: DEFAULT_STALE_PERIOD,
            inDecimals: 18,
            outDecimals: 8,
            direction: ConversionDirection.IN_TO_OUT
        });
        uniswapNode = UniswapNode({
            pool: IUniswapV3Pool(address(mockPool)),
            twapPeriod: DEFAULT_TWAP_PERIOD,
            direction: ConversionDirection.IN_TO_OUT,
            roundUp: true
        });

        return AltoRewardsOracleInitParams({
            uniswapNode: uniswapNode,
            chainlinkNode: chainlinkNode,
            owner: OWNER,
            priceUpdateCooldownPeriod: DEFAULT_COOLDOWN_PERIOD,
            altoToken: address(inToken)
        });
    }
}
