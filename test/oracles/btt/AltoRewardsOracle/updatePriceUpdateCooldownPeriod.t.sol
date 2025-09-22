// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {AltoRewardsOracleCommon} from "./AltoRewardsOracleCommon.t.sol";
import {AltoRewardsOracle} from "@alto/oracles/AltoRewardsOracle.sol";
import {AltoRewardsOracleInitParams, IAltoRewardsOracleEvents} from "@alto/oracles/interfaces/IAltoRewardsOracle.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract AltoRewardsOracleUpdatePriceUpdateCooldownPeriod is AltoRewardsOracleCommon {
    AltoRewardsOracle oracle;

    function setUp() public override {
        super.setUp();

        AltoRewardsOracleInitParams memory params = _createValidInitParams();
        oracle = new AltoRewardsOracle(params);
    }

    function test_RevertWhen_CallerIsNotOwner() external {
        uint256 newCooldownPeriod = 2 hours;

        vm.prank(NON_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NON_OWNER));
        oracle.updatePriceUpdateCooldownPeriod(newCooldownPeriod);
    }

    modifier whenCallerIsOwner() {
        _;
    }

    function test_WhenNewCooldownPeriodIsZero() external whenCallerIsOwner {
        uint256 oldCooldownPeriod = oracle.priceUpdateCooldownPeriod();
        uint256 newCooldownPeriod = 0;

        vm.expectEmit(true, true, true, true);
        emit IAltoRewardsOracleEvents.PriceUpdateCooldownPeriodUpdated(oldCooldownPeriod, newCooldownPeriod);

        vm.prank(OWNER);
        oracle.updatePriceUpdateCooldownPeriod(newCooldownPeriod);

        // it should set priceUpdateCooldownPeriod to zero
        assertEq(oracle.priceUpdateCooldownPeriod(), 0);
    }

    function test_WhenNewCooldownPeriodIsSameAsCurrent() external whenCallerIsOwner {
        uint256 currentCooldownPeriod = oracle.priceUpdateCooldownPeriod();

        vm.expectEmit(true, true, true, true);
        emit IAltoRewardsOracleEvents.PriceUpdateCooldownPeriodUpdated(currentCooldownPeriod, currentCooldownPeriod);

        vm.prank(OWNER);
        oracle.updatePriceUpdateCooldownPeriod(currentCooldownPeriod);

        // it should set priceUpdateCooldownPeriod to the same value
        assertEq(oracle.priceUpdateCooldownPeriod(), currentCooldownPeriod);
    }

    function test_WhenNewCooldownPeriodIsDifferent() external whenCallerIsOwner {
        uint256 oldCooldownPeriod = oracle.priceUpdateCooldownPeriod();
        uint256 newCooldownPeriod = 2 days;

        vm.expectEmit(true, true, true, true);
        emit IAltoRewardsOracleEvents.PriceUpdateCooldownPeriodUpdated(oldCooldownPeriod, newCooldownPeriod);

        vm.prank(OWNER);
        oracle.updatePriceUpdateCooldownPeriod(newCooldownPeriod);

        // it should update priceUpdateCooldownPeriod to new value
        assertEq(oracle.priceUpdateCooldownPeriod(), newCooldownPeriod);
    }

    function test_MultipleCooldownUpdates() external whenCallerIsOwner {
        uint256[] memory testCooldowns = new uint256[](5);
        testCooldowns[0] = 0; // Zero
        testCooldowns[1] = 1 minutes; // Very short
        testCooldowns[2] = 1 hours; // Default
        testCooldowns[3] = 1 days; // Long
        testCooldowns[4] = 1 weeks; // Very long

        uint256 previousCooldown = oracle.priceUpdateCooldownPeriod();

        for (uint256 i = 0; i < testCooldowns.length; i++) {
            vm.expectEmit(true, true, true, true);
            emit IAltoRewardsOracleEvents.PriceUpdateCooldownPeriodUpdated(previousCooldown, testCooldowns[i]);

            vm.prank(OWNER);
            oracle.updatePriceUpdateCooldownPeriod(testCooldowns[i]);

            assertEq(oracle.priceUpdateCooldownPeriod(), testCooldowns[i]);
            previousCooldown = testCooldowns[i];
        }
    }

    function test_MaximumCooldownPeriod() external whenCallerIsOwner {
        uint256 oldCooldownPeriod = oracle.priceUpdateCooldownPeriod();
        uint256 maxCooldownPeriod = type(uint256).max;

        vm.expectEmit(true, true, true, true);
        emit IAltoRewardsOracleEvents.PriceUpdateCooldownPeriodUpdated(oldCooldownPeriod, maxCooldownPeriod);

        vm.prank(OWNER);
        oracle.updatePriceUpdateCooldownPeriod(maxCooldownPeriod);

        assertEq(oracle.priceUpdateCooldownPeriod(), maxCooldownPeriod);
    }

    function test_CooldownPeriodEventEmission() external whenCallerIsOwner {
        uint256 oldPeriod = oracle.priceUpdateCooldownPeriod();
        uint256 newPeriod = 12 hours;

        // Test that event is emitted with correct parameters
        vm.expectEmit(true, true, true, true);
        emit IAltoRewardsOracleEvents.PriceUpdateCooldownPeriodUpdated(oldPeriod, newPeriod);

        vm.prank(OWNER);
        oracle.updatePriceUpdateCooldownPeriod(newPeriod);

        // Verify the state change occurred
        assertEq(oracle.priceUpdateCooldownPeriod(), newPeriod);
    }

    function test_OnlyOwnerCanUpdate() external {
        uint256 newCooldownPeriod = 3 hours;
        address[] memory nonOwners = new address[](3);
        nonOwners[0] = address(0x123);
        nonOwners[1] = address(0x456);
        nonOwners[2] = address(0x789);

        for (uint256 i = 0; i < nonOwners.length; i++) {
            vm.prank(nonOwners[i]);
            vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwners[i]));
            oracle.updatePriceUpdateCooldownPeriod(newCooldownPeriod);
        }

        // Verify state hasn't changed
        assertEq(oracle.priceUpdateCooldownPeriod(), DEFAULT_COOLDOWN_PERIOD);
    }
}
