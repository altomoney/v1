// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {AltoRewardsOracleCommon} from "./AltoRewardsOracleCommon.t.sol";
import {AltoRewardsOracle} from "@alto/oracles/AltoRewardsOracle.sol";
import {AltoRewardsOracleInitParams, IAltoRewardsOracleErrors} from "@alto/oracles/interfaces/IAltoRewardsOracle.sol";

contract AltoRewardsOracleUpdatePrice is AltoRewardsOracleCommon {
    AltoRewardsOracle oracle;
    uint256 constant INITIAL_PRICE = 1000e8;

    function setUp() public override {
        super.setUp();

        AltoRewardsOracleInitParams memory params = _createValidInitParams();
        oracle = new AltoRewardsOracle(params);
    }

    modifier whenOracleIsNotInitiated() {
        _;
    }

    modifier whenOracleIsInitiated() {
        _;
    }

    function test_RevertWhen_LastPriceUpdateTimestampIsZero() external whenOracleIsNotInitiated {
        // Oracle is not initiated by default
        assertEq(oracle.lastPriceUpdateTimestamp(), 0);

        vm.expectRevert(IAltoRewardsOracleErrors.AltoRewardsOracleNotInitiated.selector);
        oracle.updatePrice();
    }

    function test_RevertWhen_CooldownPeriodHasNotPassed() external whenOracleIsInitiated {
        // Initialize oracle
        vm.prank(OWNER);
        oracle.startTwapPeriod(INITIAL_PRICE);

        uint256 cooldownPeriod = oracle.priceUpdateCooldownPeriod();
        assertEq(cooldownPeriod, DEFAULT_COOLDOWN_PERIOD); // 1 hour

        // Try to update immediately (cooldown not passed)
        vm.expectRevert(IAltoRewardsOracleErrors.AltoRewardsOracleTooEarlyToUpdatePrice.selector);
        oracle.updatePrice();

        // Try to update just before cooldown period ends
        vm.warp(block.timestamp + cooldownPeriod - 1);
        vm.expectRevert(IAltoRewardsOracleErrors.AltoRewardsOracleTooEarlyToUpdatePrice.selector);
        oracle.updatePrice();
    }

    function test_RevertWhen_CalledInSameBlockAsLastPriceUpdateTimestamp() external whenOracleIsInitiated {
        // Initialize oracle
        vm.prank(OWNER);
        oracle.startTwapPeriod(INITIAL_PRICE);

        uint256 cooldownPeriod = oracle.priceUpdateCooldownPeriod();

        // Move time forward by just after the cooldown period
        vm.warp(block.timestamp + cooldownPeriod + 1);

        oracle.updatePrice();

        vm.expectRevert(IAltoRewardsOracleErrors.AltoRewardsOracleTooEarlyToUpdatePrice.selector);
        oracle.updatePrice();
    }

    function test_WhenCooldownPeriodHasPassed() external whenOracleIsInitiated {
        // Initialize oracle
        vm.prank(OWNER);
        oracle.startTwapPeriod(INITIAL_PRICE);

        uint256 cooldownPeriod = oracle.priceUpdateCooldownPeriod();

        // Move time forward by just after the cooldown period
        vm.warp(block.timestamp + cooldownPeriod + 1);

        oracle.updatePrice();
    }
}
