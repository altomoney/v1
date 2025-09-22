// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {AltoRewardsOracleCommon} from "./AltoRewardsOracleCommon.t.sol";
import {AltoRewardsOracle} from "@alto/oracles/AltoRewardsOracle.sol";
import {AltoRewardsOracleInitParams, IAltoRewardsOracleErrors} from "@alto/oracles/interfaces/IAltoRewardsOracle.sol";

contract AltoRewardsOracleGetPrice is AltoRewardsOracleCommon {
    AltoRewardsOracle oracle;

    function setUp() public override {
        super.setUp();

        AltoRewardsOracleInitParams memory params = _createValidInitParams();
        oracle = new AltoRewardsOracle(params);
    }

    modifier givenOracleIsNotInitiated() {
        _;
    }

    function test_RevertWhen_LastPriceUpdateTimestampIsZero() external givenOracleIsNotInitiated {
        // Oracle is not initiated by default, lastPriceUpdateTimestamp should be 0
        assertEq(oracle.lastPriceUpdateTimestamp(), 0);

        vm.expectRevert(IAltoRewardsOracleErrors.AltoRewardsOracleNotInitiated.selector);
        oracle.getPrice();
    }

    modifier givenOracleIsInitiated() {
        _;
    }

    function test_WhenLastPriceUpdateTimestampIsGreaterThanZero() external givenOracleIsInitiated {
        uint256 initialPrice = 1000e8; // 1000 USD in USD_ORACLE_PRICE_PRECISION

        // Initialize the oracle by calling startTwapPeriod
        vm.prank(OWNER);
        oracle.startTwapPeriod(initialPrice);

        // Verify lastPriceUpdateTimestamp is greater than zero
        assertGt(oracle.lastPriceUpdateTimestamp(), 0);

        // it should return the cached price
        uint256 returnedPrice = oracle.getPrice();
        assertEq(returnedPrice, initialPrice);

        // it should not modify any state
        uint256 timestampBefore = oracle.lastPriceUpdateTimestamp();
        uint256 cachedPriceBefore = oracle.cachedPrice();

        oracle.getPrice();

        assertEq(oracle.lastPriceUpdateTimestamp(), timestampBefore);
        assertEq(oracle.cachedPrice(), cachedPriceBefore);
    }

    function test_GetPriceWithDifferentCachedValues() external givenOracleIsInitiated {
        uint256[] memory testPrices = new uint256[](3);
        testPrices[0] = 1e8; // 1 USD
        testPrices[1] = 1000e8; // 1000 USD
        testPrices[2] = 0; // 0 USD (edge case)

        for (uint256 i = 0; i < testPrices.length; i++) {
            // Deploy new oracle for each test
            AltoRewardsOracleInitParams memory params = _createValidInitParams();
            AltoRewardsOracle testOracle = new AltoRewardsOracle(params);

            vm.prank(OWNER);
            testOracle.startTwapPeriod(testPrices[i]);

            uint256 returnedPrice = testOracle.getPrice();
            assertEq(returnedPrice, testPrices[i]);
        }
    }
}
