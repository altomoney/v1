// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {AltoERC4626RatioLinearDiscountOracleCommon} from "./AltoERC4626RatioLinearDiscountOracleCommon.t.sol";
import {MockAltoERC4626RatioLinearDiscountOracle} from "../mocks/MockAltoERC4626RatioLinearDiscountOracle.sol";
import {ModuleERC4626Ratio} from "@alto/oracles/modules/ModuleERC4626Ratio.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {
    IAltoERC4626RatioLinearDiscountOracleEvents
} from "@alto/oracles/interfaces/IAltoERC4626RatioLinearDiscountOracle.sol";
import {ERC4626RatioNode, LinearDiscountNode} from "@alto/oracles/interfaces/IModuleNode.sol";

contract AltoERC4626RatioLinearDiscountOracleUpdateERC4626RatioNode is AltoERC4626RatioLinearDiscountOracleCommon {
    MockAltoERC4626RatioLinearDiscountOracle internal oracle;

    function setUp() public {
        oracle = new MockAltoERC4626RatioLinearDiscountOracle(
            OWNER, _createValidERC4626RatioNode(), _createValidLinearDiscountNode(), 1.05 ether
        );
    }

    modifier givenCallerIsNotOwner() {
        vm.startPrank(NON_OWNER);
        _;
        vm.stopPrank();
    }

    modifier givenCallerIsOwner() {
        _;
    }

    function test_RevertWhen_CallerIsNotOwner() external givenCallerIsNotOwner {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NON_OWNER));
        oracle.updateERC4626RatioNode(_createValidERC4626RatioNode());
    }

    function test_RevertWhen_InitialRatioIsZero() external givenCallerIsOwner {
        uint256 pastTimestamp = block.timestamp > 1 hours ? block.timestamp - 1 hours : block.timestamp;
        ERC4626RatioNode memory invalidNode =
            _createValidERC4626RatioNode(0, pastTimestamp, DEFAULT_MAX_YEARLY_GROWTH_RATIO_WAD);

        vm.prank(OWNER);
        vm.expectRevert(ModuleERC4626Ratio.ModuleERC4626RatioInvalidInput.selector);
        oracle.updateERC4626RatioNode(invalidNode);
    }

    function test_RevertWhen_InitialTimestampIsGreaterThanBlockTimestamp() external givenCallerIsOwner {
        ERC4626RatioNode memory invalidNode = _createValidERC4626RatioNode(
            DEFAULT_INITIAL_RATIO, block.timestamp + 1, DEFAULT_MAX_YEARLY_GROWTH_RATIO_WAD
        );

        vm.prank(OWNER);
        vm.expectRevert(ModuleERC4626Ratio.ModuleERC4626RatioInvalidInput.selector);
        oracle.updateERC4626RatioNode(invalidNode);
    }

    function test_RevertWhen_MaxYearlyGrowthRatioWadIsZero() external givenCallerIsOwner {
        uint256 pastTimestamp = block.timestamp > 1 hours ? block.timestamp - 1 hours : block.timestamp;
        ERC4626RatioNode memory invalidNode = _createValidERC4626RatioNode(DEFAULT_INITIAL_RATIO, pastTimestamp, 0);

        vm.prank(OWNER);
        vm.expectRevert(ModuleERC4626Ratio.ModuleERC4626RatioInvalidInput.selector);
        oracle.updateERC4626RatioNode(invalidNode);
    }

    function test_WhenNodeIsValid() external givenCallerIsOwner {
        // Capture old node for event assertion
        (uint256 oldInitialRatio, uint256 oldInitialTimestamp, uint256 oldMaxYearlyGrowthRatioWad) =
            oracle.erc4626RatioNode();
        ERC4626RatioNode memory oldNode = ERC4626RatioNode({
            initialRatio: oldInitialRatio,
            initialTimestamp: oldInitialTimestamp,
            maxYearlyGrowthRatioWad: oldMaxYearlyGrowthRatioWad
        });

        uint256 newInitialRatio = 1.1 ether;
        uint256 newInitialTimestamp = block.timestamp > 1 days ? block.timestamp - 1 days : block.timestamp;
        uint256 newMaxYearlyGrowthRatioWad = 0.2 ether;
        ERC4626RatioNode memory newNode =
            _createValidERC4626RatioNode(newInitialRatio, newInitialTimestamp, newMaxYearlyGrowthRatioWad);

        // it should emit SetERC4626RatioNode with old and new node
        vm.expectEmit(true, true, true, true);
        emit IAltoERC4626RatioLinearDiscountOracleEvents.SetERC4626RatioNode(oldNode, newNode);

        vm.prank(OWNER);
        oracle.updateERC4626RatioNode(newNode);

        // it should update erc4626RatioNode storage correctly
        (uint256 initialRatio, uint256 initialTimestamp, uint256 maxYearlyGrowthRatioWad) = oracle.erc4626RatioNode();
        assertEq(initialRatio, newInitialRatio);
        assertEq(initialTimestamp, newInitialTimestamp);
        assertEq(maxYearlyGrowthRatioWad, newMaxYearlyGrowthRatioWad);
    }
}
