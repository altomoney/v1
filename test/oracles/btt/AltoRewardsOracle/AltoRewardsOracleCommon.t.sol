// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {AltoRewardsOracle} from "@alto/oracles/AltoRewardsOracle.sol";
import {
    AltoRewardsOracleInitParams,
    IAltoRewardsOracleErrors,
    IAltoRewardsOracleEvents
} from "@alto/oracles/interfaces/IAltoRewardsOracle.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {ERC20MockDecimals} from "@alto-test/helpers/ERC20MockDecimals.sol";
import {MockUniswapPool} from "./MockUniswapPool.sol";
import {MockChainlinkFeed} from "./MockChainlinkFeed.sol";

contract AltoRewardsOracleCommon is Test {
    address constant OWNER = address(0x1);
    address constant NON_OWNER = address(0x2);

    ERC20MockDecimals inToken;
    ERC20MockDecimals outToken;
    MockUniswapPool mockPool;
    MockChainlinkFeed mockFeed;

    // Default valid parameters
    uint32 constant DEFAULT_TWAP_PERIOD = 1 hours;
    uint16 constant DEFAULT_OBSERVATION_LENGTH = 100;
    uint8 constant DEFAULT_UNI_FINAL_CURRENCY = 0;
    uint32 constant DEFAULT_STALE_PERIOD = 1 days;
    bytes32 constant DEFAULT_DESCRIPTION = "Test Oracle";
    uint256 constant DEFAULT_COOLDOWN_PERIOD = 1 hours;

    function setUp() public virtual {
        inToken = new ERC20MockDecimals("In Token", "IN", 18);
        outToken = new ERC20MockDecimals("Out Token", "OUT", 18);
        mockPool = new MockUniswapPool();
        mockFeed = new MockChainlinkFeed();
    }

    function _createValidInitParams() internal view returns (AltoRewardsOracleInitParams memory) {
        address[] memory addressInAndOutUni = new address[](2);
        addressInAndOutUni[0] = address(inToken);
        addressInAndOutUni[1] = address(outToken);

        // Create valid circuits with mock contracts
        IUniswapV3Pool[] memory circuitUniswap = new IUniswapV3Pool[](1);
        circuitUniswap[0] = IUniswapV3Pool(address(mockPool));
        uint8[] memory circuitUniIsMultiplied = new uint8[](1);
        circuitUniIsMultiplied[0] = 1; // multiply

        address[] memory circuitChainlink = new address[](1);
        circuitChainlink[0] = address(mockFeed);
        uint8[] memory circuitChainIsMultiplied = new uint8[](1);
        circuitChainIsMultiplied[0] = 1; // multiply

        return AltoRewardsOracleInitParams({
            addressInAndOutUni: addressInAndOutUni,
            circuitUniswap: circuitUniswap,
            circuitUniIsMultiplied: circuitUniIsMultiplied,
            twapPeriod: DEFAULT_TWAP_PERIOD,
            observationLength: DEFAULT_OBSERVATION_LENGTH,
            uniFinalCurrency: DEFAULT_UNI_FINAL_CURRENCY,
            circuitChainlink: circuitChainlink,
            circuitChainIsMultiplied: circuitChainIsMultiplied,
            owner: OWNER,
            stalePeriod: DEFAULT_STALE_PERIOD,
            description: DEFAULT_DESCRIPTION,
            priceUpdateCooldownPeriod: DEFAULT_COOLDOWN_PERIOD
        });
    }

    function _createInvalidAddressArrayInitParams() internal view returns (AltoRewardsOracleInitParams memory) {
        // Create invalid address array with wrong length
        address[] memory invalidAddressArray = new address[](1);
        invalidAddressArray[0] = address(inToken);

        // Create valid circuits with mock contracts (same as valid params)
        IUniswapV3Pool[] memory circuitUniswap = new IUniswapV3Pool[](1);
        circuitUniswap[0] = IUniswapV3Pool(address(mockPool));
        uint8[] memory circuitUniIsMultiplied = new uint8[](1);
        circuitUniIsMultiplied[0] = 1;

        address[] memory circuitChainlink = new address[](1);
        circuitChainlink[0] = address(mockFeed);
        uint8[] memory circuitChainIsMultiplied = new uint8[](1);
        circuitChainIsMultiplied[0] = 1;

        return AltoRewardsOracleInitParams({
            addressInAndOutUni: invalidAddressArray, // This is the invalid part
            circuitUniswap: circuitUniswap,
            circuitUniIsMultiplied: circuitUniIsMultiplied,
            twapPeriod: DEFAULT_TWAP_PERIOD,
            observationLength: DEFAULT_OBSERVATION_LENGTH,
            uniFinalCurrency: DEFAULT_UNI_FINAL_CURRENCY,
            circuitChainlink: circuitChainlink,
            circuitChainIsMultiplied: circuitChainIsMultiplied,
            owner: OWNER,
            stalePeriod: DEFAULT_STALE_PERIOD,
            description: DEFAULT_DESCRIPTION,
            priceUpdateCooldownPeriod: DEFAULT_COOLDOWN_PERIOD
        });
    }

    function _createZeroOwnerInitParams() internal view returns (AltoRewardsOracleInitParams memory) {
        AltoRewardsOracleInitParams memory params = _createValidInitParams();
        params.owner = address(0);
        return params;
    }

    function _createTokensWithDecimals(uint8 inDecimals, uint8 outDecimals)
        internal
        returns (ERC20MockDecimals, ERC20MockDecimals)
    {
        ERC20MockDecimals inTokenCustom = new ERC20MockDecimals("In Token", "IN", inDecimals);
        ERC20MockDecimals outTokenCustom = new ERC20MockDecimals("Out Token", "OUT", outDecimals);
        return (inTokenCustom, outTokenCustom);
    }
}
