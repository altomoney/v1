// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {TOBTestBase, ITapiocaOptionBroker} from "../TOBTestBase.t.sol";

contract TapiocaOptionBrokerAdvanceWeekTest is TOBTestBase {
    function setUp() public override {
        super.setUp();
    }

    function test_revertWhen_lastEpochEqualsCurrentEpoch() public {
        // Mock TAP oracle
        uint256 tapPrice = 100e18;
        vm.mockCall(address(tapOracle), abi.encodeWithSignature("get(bytes)"), abi.encode(true, tapPrice));

        // Mock emitForWeek
        vm.mockCall(address(tapToken), abi.encodeWithSignature("emitForWeek()"), abi.encode());

        // Mock cluster and penrose
        vm.mockCall(address(cluster), abi.encodeWithSignature("getActiveMarkets()"), abi.encode(new address[](0)));
        vm.mockCall(
            address(report.penrose),
            abi.encodeWithSignature("singularityBigBangMarkets()"),
            abi.encode(new address[](0))
        );

        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSelector(ITapiocaOptionBroker.NotValid.selector));
        tob.advanceWeek();
        vm.stopPrank();
    }

    function test_advanceWeek_validConditions() public {
        // Store initial values
        uint256 initialTapBalance = tapToken.balanceOf(address(tob));

        // Mock TAP oracle
        uint256 tapPrice = 100e18;
        vm.mockCall(address(tapOracle), abi.encodeWithSignature("get(bytes)"), abi.encode(true, tapPrice));

        // Mock emitForWeek
        vm.mockCall(address(tapToken), abi.encodeWithSignature("emitForWeek()"), abi.encode());

        // Mock cluster and penrose
        vm.mockCall(address(cluster), abi.encodeWithSignature("getActiveMarkets()"), abi.encode(new address[](0)));
        vm.mockCall(
            address(report.penrose),
            abi.encodeWithSignature("singularityBigBangMarkets()"),
            abi.encode(new address[](0))
        );

        // Advance time to next epoch
        vm.warp(block.timestamp + EPOCH_DURATION);

        // Get current epoch
        uint256 epoch = tob.currentEpoch();

        // Expect NewEpoch event
        vm.expectEmit(true, true, true, true);
        emit ITapiocaOptionBroker.NewEpoch(epoch, epoch + 1, tapPrice);

        // Advance week
        vm.startPrank(owner);
        tob.advanceWeek();
        vm.stopPrank();

        // Verify lastEpoch updated
        assertEq(tob.lastEpoch(), epoch, "Last epoch should be updated");

        // Verify TAP valuation updated
        assertEq(tob._epochTAPValuation(), tapPrice, "TAP valuation should be updated");
    }

    function test_revertWhen_tapOracleCallFails() public {
        // Mock TAP oracle to fail
        vm.mockCall(address(tapOracle), abi.encodeWithSignature("get(bytes)"), abi.encode(false, 0));

        // Mock cluster and penrose
        vm.mockCall(address(cluster), abi.encodeWithSignature("getActiveMarkets()"), abi.encode(new address[](0)));
        vm.mockCall(
            address(report.penrose),
            abi.encodeWithSignature("singularityBigBangMarkets()"),
            abi.encode(new address[](0))
        );

        // Advance time to next epoch
        vm.warp(block.timestamp + EPOCH_DURATION);

        // Try to advance week
        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSelector(ITapiocaOptionBroker.Failed.selector));
        tob.advanceWeek();
        vm.stopPrank();
    }

    event NewEpoch(uint256 indexed epoch, uint256 epochTAPValuation);
}
