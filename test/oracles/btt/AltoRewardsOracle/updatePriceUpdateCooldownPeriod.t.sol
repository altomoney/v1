// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {AltoRewardsOracleCommon} from "./AltoRewardsOracleCommon.t.sol";
import {AltoRewardsOracle} from "@alto/oracles/AltoRewardsOracle.sol";
import {
    AltoRewardsOracleInitParams,
    IAltoRewardsOracleEvents,
    IAltoRewardsOracleErrors
} from "@alto/oracles/interfaces/IAltoRewardsOracle.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract AltoRewardsOracleUpdatePriceUpdateCooldownPeriod is AltoRewardsOracleCommon {
    AltoRewardsOracle oracle;

    function setUp() public override {
        super.setUp();

        AltoRewardsOracleInitParams memory params = _createValidInitParams();
        oracle = new AltoRewardsOracle(params);
    }

    modifier whenCallerIsNotOwner() {
        _;
    }

    function test_RevertWhen_CallerIsNotOwner() external whenCallerIsNotOwner {
        uint256 newCooldownPeriod = 2 hours;

        vm.prank(NON_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NON_OWNER));
        oracle.updatePriceUpdateCooldownPeriod(newCooldownPeriod);
    }

    modifier whenCallerIsOwner() {
        vm.startPrank(OWNER);
        _;
        vm.stopPrank();
    }

    function test_RevertWhen_NewCooldownPeriodIsZero() external whenCallerIsOwner {
        uint256 oldCooldownPeriod = oracle.priceUpdateCooldownPeriod();
        uint256 newCooldownPeriod = 0;

        vm.expectRevert(IAltoRewardsOracleErrors.AltoRewardsOracleInvalidInput.selector);
        oracle.updatePriceUpdateCooldownPeriod(newCooldownPeriod);
    }

    function test_WhenNewCooldownPeriodIsSameAsCurrent() external whenCallerIsOwner {
        uint256 currentCooldownPeriod = oracle.priceUpdateCooldownPeriod();

        vm.expectRevert(IAltoRewardsOracleErrors.AltoRewardsOracleInvalidInput.selector);
        oracle.updatePriceUpdateCooldownPeriod(currentCooldownPeriod);

        // priceUpdateCooldownPeriod should not change
        assertEq(oracle.priceUpdateCooldownPeriod(), currentCooldownPeriod);
    }

    function test_WhenNewCooldownPeriodIsDifferentFromCurrent() external whenCallerIsOwner {
        uint256 oldCooldownPeriod = oracle.priceUpdateCooldownPeriod();
        uint256 newCooldownPeriod = 2 days;

        vm.expectEmit(false, false, false, true);
        emit IAltoRewardsOracleEvents.PriceUpdateCooldownPeriodUpdated(oldCooldownPeriod, newCooldownPeriod);

        oracle.updatePriceUpdateCooldownPeriod(newCooldownPeriod);

        // it should update priceUpdateCooldownPeriod to new value
        assertEq(oracle.priceUpdateCooldownPeriod(), newCooldownPeriod);
    }
}
