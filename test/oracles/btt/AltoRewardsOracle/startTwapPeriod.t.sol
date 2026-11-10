// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import {AltoRewardsOracleCommon} from "./AltoRewardsOracleCommon.t.sol";
import {AltoRewardsOracle} from "@alto/oracles/AltoRewardsOracle.sol";
import {
    AltoRewardsOracleInitParams,
    IAltoRewardsOracleErrors,
    IAltoRewardsOracleEvents
} from "@alto/oracles/interfaces/IAltoRewardsOracle.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract AltoRewardsOracleStartTwapPeriod is AltoRewardsOracleCommon {
    AltoRewardsOracle oracle;

    function setUp() public override {
        super.setUp();

        AltoRewardsOracleInitParams memory params = _createValidInitParams();
        oracle = new AltoRewardsOracle(params);
    }

    modifier whenCallerIsNotOwner() {
        _;
    }

    modifier givenCallerIsOwner() {
        _;
    }

    modifier givenOracleIsAlreadyInitiated() {
        _;
    }

    modifier givenOracleIsNotInitiated() {
        _;
    }

    modifier whenInitialPriceIsZero() {
        _;
    }

    function test_RevertWhen_CallerIsNotOwner() external whenCallerIsNotOwner {
        uint256 initialPrice = 1000e8;

        vm.prank(NON_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NON_OWNER));
        oracle.startTwapPeriod(initialPrice);
    }

    function test_RevertWhen_LastPriceUpdateTimestampIsNotZero()
        external
        givenCallerIsOwner
        givenOracleIsAlreadyInitiated
    {
        uint256 initialPrice = 2e8;

        // First initialization
        vm.startPrank(OWNER);
        oracle.startTwapPeriod(initialPrice);

        // Verify it's initiated
        assertGt(oracle.lastPriceUpdateTimestamp(), 0);

        // Try to initialize again
        vm.expectRevert(IAltoRewardsOracleErrors.AltoRewardsOracleAlreadyStartedTwapPeriod.selector);
        oracle.startTwapPeriod(initialPrice);
        vm.stopPrank();
    }

    function test_RevertWhen_InitialPriceIsZero()
        external
        givenCallerIsOwner
        givenOracleIsNotInitiated
        whenInitialPriceIsZero
    {
        uint256 initialPrice = 0;

        // Verify oracle is not initiated
        assertEq(oracle.lastPriceUpdateTimestamp(), 0);
        assertEq(oracle.cachedPrice(), 0);

        vm.prank(OWNER);
        vm.expectRevert(IAltoRewardsOracleErrors.AltoRewardsOracleInvalidInput.selector);
        oracle.startTwapPeriod(initialPrice);
    }

    function test_WhenLastPriceUpdateTimestampIsZero() external givenCallerIsOwner givenOracleIsNotInitiated {
        uint256 initialPrice = 1000e8;
        uint256 timestampBefore = block.timestamp;

        // Verify oracle is not initiated
        assertEq(oracle.lastPriceUpdateTimestamp(), 0);
        assertEq(oracle.cachedPrice(), 0);

        vm.expectEmit(true, true, true, true);
        emit IAltoRewardsOracleEvents.PriceUpdated(block.timestamp, 0, initialPrice);

        vm.prank(OWNER);
        oracle.startTwapPeriod(initialPrice);

        // it should set lastPriceUpdateTimestamp to current block timestamp
        assertEq(oracle.lastPriceUpdateTimestamp(), timestampBefore);

        // it should set cachedPrice to provided initial price
        assertEq(oracle.cachedPrice(), initialPrice);
    }

    function test_StartTwapPeriodWithDifferentPrices() external givenCallerIsOwner givenOracleIsNotInitiated {
        uint256[] memory testPrices = new uint256[](3);
        testPrices[0] = 1; // Minimum non-zero
        testPrices[1] = 1000e8; // Normal price (1000 USD)
        testPrices[2] = type(uint256).max; // Maximum value

        for (uint256 i = 0; i < testPrices.length; i++) {
            // Deploy new oracle for each test
            AltoRewardsOracleInitParams memory params = _createValidInitParams();
            AltoRewardsOracle testOracle = new AltoRewardsOracle(params);

            uint256 timestamp = block.timestamp;

            vm.expectEmit(true, true, true, true);
            emit IAltoRewardsOracleEvents.PriceUpdated(timestamp, 0, testPrices[i]);

            vm.prank(OWNER);
            testOracle.startTwapPeriod(testPrices[i]);

            assertEq(testOracle.lastPriceUpdateTimestamp(), timestamp);
            assertEq(testOracle.cachedPrice(), testPrices[i]);
        }
    }
}
