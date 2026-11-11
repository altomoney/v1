// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import {AltoERC4626RatioLinearDiscountOracleCommon} from "./AltoERC4626RatioLinearDiscountOracleCommon.t.sol";
import {MockAltoERC4626RatioLinearDiscountOracle} from "../mocks/MockAltoERC4626RatioLinearDiscountOracle.sol";
import {MockPTToken} from "../mocks/MockPTToken.sol";
import {ModuleLinearDiscount} from "@alto/oracles/modules/ModuleLinearDiscount.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {
    IAltoERC4626RatioLinearDiscountOracleEvents
} from "@alto/oracles/interfaces/IAltoERC4626RatioLinearDiscountOracle.sol";
import {ERC4626RatioNode, LinearDiscountNode} from "@alto/oracles/interfaces/IModuleNode.sol";
import {SECONDS_PER_YEAR} from "@alto/oracles/modules/ModuleLinearDiscount.sol";

contract AltoERC4626RatioLinearDiscountOracleUpdateLinearDiscountNode is AltoERC4626RatioLinearDiscountOracleCommon {
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
        LinearDiscountNode memory node = _createValidLinearDiscountNode();
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NON_OWNER));
        oracle.updateLinearDiscountNode(node);
    }

    function test_RevertWhen_MaturityIsNotInFuture() external givenCallerIsOwner {
        // maturity = block.timestamp is NOT strictly in the future - fails before ptToken check
        LinearDiscountNode memory invalidNode = LinearDiscountNode({
            ptToken: address(new MockPTToken(block.timestamp)),
            maturity: block.timestamp,
            baseDiscountPerYear: DEFAULT_BASE_DISCOUNT_PER_YEAR,
            inDecimals: 18,
            outDecimals: 36
        });

        vm.prank(OWNER);
        vm.expectRevert(ModuleLinearDiscount.ModuleLinearDiscountInvalidInput.selector);
        oracle.updateLinearDiscountNode(invalidNode);
    }

    function test_RevertWhen_PTTokenIsZeroAddress() external givenCallerIsOwner {
        LinearDiscountNode memory invalidNode = LinearDiscountNode({
            ptToken: address(0),
            maturity: block.timestamp + SECONDS_PER_YEAR,
            baseDiscountPerYear: DEFAULT_BASE_DISCOUNT_PER_YEAR,
            inDecimals: 18,
            outDecimals: 36
        });

        vm.prank(OWNER);
        vm.expectRevert(ModuleLinearDiscount.ModuleLinearDiscountInvalidInput.selector);
        oracle.updateLinearDiscountNode(invalidNode);
    }

    function test_RevertWhen_PTTokenExpiryDoesNotMatchMaturity() external givenCallerIsOwner {
        uint256 maturity = block.timestamp + SECONDS_PER_YEAR;
        // Deploy PT token whose expiry differs from the node's maturity
        address ptToken = address(new MockPTToken(maturity + 1));
        LinearDiscountNode memory invalidNode = LinearDiscountNode({
            ptToken: ptToken,
            maturity: maturity,
            baseDiscountPerYear: DEFAULT_BASE_DISCOUNT_PER_YEAR,
            inDecimals: 18,
            outDecimals: 36
        });

        vm.prank(OWNER);
        vm.expectRevert(ModuleLinearDiscount.ModuleLinearDiscountInvalidInput.selector);
        oracle.updateLinearDiscountNode(invalidNode);
    }

    function test_RevertWhen_BaseDiscountPerYearExceedsMathPrecision() external givenCallerIsOwner {
        LinearDiscountNode memory invalidNode =
            _createValidLinearDiscountNode(block.timestamp + SECONDS_PER_YEAR, 1e18 + 1, 18, 36);

        vm.prank(OWNER);
        vm.expectRevert(ModuleLinearDiscount.ModuleLinearDiscountInvalidInput.selector);
        oracle.updateLinearDiscountNode(invalidNode);
    }

    function test_RevertWhen_DecimalSumExceeds54() external givenCallerIsOwner {
        // 30 + 25 = 55 > 54
        LinearDiscountNode memory invalidNode =
            _createValidLinearDiscountNode(block.timestamp + SECONDS_PER_YEAR, DEFAULT_BASE_DISCOUNT_PER_YEAR, 30, 25);

        vm.prank(OWNER);
        vm.expectRevert(ModuleLinearDiscount.ModuleLinearDiscountInvalidInput.selector);
        oracle.updateLinearDiscountNode(invalidNode);
    }

    function test_WhenNodeIsValid() external givenCallerIsOwner {
        // Capture old node for event assertion
        (
            address oldPTToken,
            uint256 oldMaturity,
            uint256 oldBaseDiscountPerYear,
            uint8 oldInDecimals,
            uint8 oldOutDecimals
        ) = oracle.linearDiscountNode();
        LinearDiscountNode memory oldNode = LinearDiscountNode({
            ptToken: oldPTToken,
            maturity: oldMaturity,
            baseDiscountPerYear: oldBaseDiscountPerYear,
            inDecimals: oldInDecimals,
            outDecimals: oldOutDecimals
        });

        uint256 newMaturity = block.timestamp + SECONDS_PER_YEAR / 2;
        uint256 newBaseDiscountPerYear = 0.05 ether; // 5%/year
        LinearDiscountNode memory newNode = _createValidLinearDiscountNode(newMaturity, newBaseDiscountPerYear, 18, 36);

        // it should emit SetLinearDiscountNode with old and new node
        vm.expectEmit(true, true, true, true);
        emit IAltoERC4626RatioLinearDiscountOracleEvents.SetLinearDiscountNode(oldNode, newNode);

        vm.prank(OWNER);
        oracle.updateLinearDiscountNode(newNode);

        // it should update linearDiscountNode storage correctly
        (, uint256 maturity, uint256 baseDiscountPerYear, uint8 inDecimals, uint8 outDecimals) =
            oracle.linearDiscountNode();
        assertEq(maturity, newMaturity);
        assertEq(baseDiscountPerYear, newBaseDiscountPerYear);
        assertEq(inDecimals, 18);
        assertEq(outDecimals, 36);
    }

    /// @dev Demonstrates that updateLinearDiscountNode is callable even after the current PT has matured,
    /// allowing the oracle to be reconfigured for a new issuance without redeployment.
    function test_WhenCurrentMaturityHasPassedAndNewNodeHasFutureMaturity() external givenCallerIsOwner {
        // Warp past the current stored maturity
        (, uint256 currentMaturity,,,) = oracle.linearDiscountNode();
        vm.warp(currentMaturity + 1);

        // New node with a future maturity - should succeed despite current maturity being stale
        uint256 newMaturity = block.timestamp + SECONDS_PER_YEAR;
        LinearDiscountNode memory newNode = _createValidLinearDiscountNode(newMaturity, 0.08 ether, 18, 36);

        vm.prank(OWNER);
        oracle.updateLinearDiscountNode(newNode);

        (, uint256 maturity, uint256 baseDiscountPerYear,,) = oracle.linearDiscountNode();
        assertEq(maturity, newMaturity);
        assertEq(baseDiscountPerYear, 0.08 ether);
    }
}
