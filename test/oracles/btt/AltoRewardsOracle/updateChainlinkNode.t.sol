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
import {ModuleChainlink} from "@alto/oracles/lending/modules/ModuleChainlink.sol";
import {ChainlinkNode} from "@alto/oracles/interfaces/IModuleNode.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract AltoRewardsOracleUpdateChainlinkNode is AltoRewardsOracleCommon {
    AltoRewardsOracle oracle;

    function setUp() public override {
        super.setUp();
        AltoRewardsOracleInitParams memory params = _createValidInitParams();
        oracle = new AltoRewardsOracle(params);
    }

    modifier givenCallerIsNotOwner() {
        vm.startPrank(NON_OWNER);
        _;
        vm.stopPrank();
    }

    modifier givenCallerIsOwner() {
        vm.startPrank(OWNER);
        _;
        vm.stopPrank();
    }

    function _createValidChainlinkNode() internal view returns (ChainlinkNode memory) {
        return ChainlinkNode({
            feed: AggregatorV3Interface(address(mockFeed)),
            stalePeriod: DEFAULT_STALE_PERIOD,
            inDecimals: 18,
            outDecimals: 18,
            multiplied: 1
        });
    }

    function test_RevertWhen_CallerIsNotOwner() external givenCallerIsNotOwner {
        ChainlinkNode memory validNode = _createValidChainlinkNode();

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NON_OWNER));
        oracle.updateChainlinkNode(validNode);
    }

    function test_RevertWhen_FeedIsZeroAddress() external givenCallerIsOwner {
        ChainlinkNode memory invalidNode = _createValidChainlinkNode();
        invalidNode.feed = AggregatorV3Interface(address(0));

        vm.expectRevert(ModuleChainlink.ModuleChainlinkInvalidInput.selector);
        oracle.updateChainlinkNode(invalidNode);
    }

    function test_RevertWhen_StalePeriodIsZero() external givenCallerIsOwner {
        ChainlinkNode memory invalidNode = _createValidChainlinkNode();
        invalidNode.stalePeriod = 0;

        vm.expectRevert(ModuleChainlink.ModuleChainlinkInvalidInput.selector);
        oracle.updateChainlinkNode(invalidNode);
    }

    function test_RevertWhen_InDecimalsPlusOutDecimalsIsGreaterThan54() external givenCallerIsOwner {
        ChainlinkNode memory invalidNode = _createValidChainlinkNode();
        invalidNode.inDecimals = 100;
        invalidNode.outDecimals = 5;

        vm.expectRevert(ModuleChainlink.ModuleChainlinkInvalidInput.selector);
        oracle.updateChainlinkNode(invalidNode);
    }

    function test_RevertWhen_MultipliedIsNotZeroOrOne() external givenCallerIsOwner {
        ChainlinkNode memory invalidNode = _createValidChainlinkNode();
        invalidNode.multiplied = 2; // Invalid value

        vm.expectRevert(ModuleChainlink.ModuleChainlinkInvalidInput.selector);
        oracle.updateChainlinkNode(invalidNode);
    }

    function test_ShouldEmitSetChainlinkNodeEvent_WhenChainlinkNodeIsValid() external givenCallerIsOwner {
        ChainlinkNode memory newChainlinkNode = _createValidChainlinkNode();
        newChainlinkNode.stalePeriod = 2 days; // Different value to ensure change
        newChainlinkNode.multiplied = 0; // Different value to ensure change
        newChainlinkNode.inDecimals = 10; // Different value to ensure change
        newChainlinkNode.outDecimals = 10; // Different value to ensure change

        // Get current chainlink node
        (AggregatorV3Interface feed, uint8 multiplied, uint32 stalePeriod, uint8 inDecimals, uint8 outDecimals) =
            oracle.chainlinkNode();
        ChainlinkNode memory oldChainlinkNode = ChainlinkNode({
            feed: feed,
            stalePeriod: stalePeriod,
            inDecimals: inDecimals,
            outDecimals: outDecimals,
            multiplied: multiplied
        });

        vm.expectEmit(true, true, true, true);
        emit IAltoRewardsOracleEvents.SetChainlinkNode(oldChainlinkNode, newChainlinkNode);

        oracle.updateChainlinkNode(newChainlinkNode);

        (feed, multiplied, stalePeriod, inDecimals, outDecimals) = oracle.chainlinkNode();
        assertEq(address(feed), address(newChainlinkNode.feed), "Feed should be updated");
        assertEq(multiplied, newChainlinkNode.multiplied, "Multiplied should be updated");
        assertEq(stalePeriod, newChainlinkNode.stalePeriod, "Stale period should be updated");
        assertEq(inDecimals, newChainlinkNode.inDecimals, "In decimals should be updated");
        assertEq(outDecimals, newChainlinkNode.outDecimals, "Out decimals should be updated");
    }
}
