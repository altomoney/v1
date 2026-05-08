// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {AltoERC4626RatioLinearDiscountOracleCommon} from "./AltoERC4626RatioLinearDiscountOracleCommon.t.sol";
import {MockAltoERC4626RatioLinearDiscountOracle} from "../mocks/MockAltoERC4626RatioLinearDiscountOracle.sol";
import {MockPTToken} from "../mocks/MockPTToken.sol";
import {ModuleERC4626Ratio} from "@alto/oracles/modules/ModuleERC4626Ratio.sol";
import {ModuleLinearDiscount} from "@alto/oracles/modules/ModuleLinearDiscount.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {
    IAltoERC4626RatioLinearDiscountOracleEvents
} from "@alto/oracles/interfaces/IAltoERC4626RatioLinearDiscountOracle.sol";
import {ERC4626RatioNode, LinearDiscountNode} from "@alto/oracles/interfaces/IModuleNode.sol";
import {SECONDS_PER_YEAR} from "@alto/oracles/modules/ModuleLinearDiscount.sol";

/// @dev BTT: constructor.tree
contract AltoERC4626RatioLinearDiscountOracleConstructor is AltoERC4626RatioLinearDiscountOracleCommon {
    modifier givenInvalidInputs() {
        _;
    }

    modifier givenValidInputs() {
        _;
    }

    function test_RevertWhen_ERC4626RatioNodeInitialRatioIsZero() external givenInvalidInputs {
        uint256 pastTimestamp = block.timestamp > 1 hours ? block.timestamp - 1 hours : block.timestamp;
        ERC4626RatioNode memory ratioNode =
            _createValidERC4626RatioNode(0, pastTimestamp, DEFAULT_MAX_YEARLY_GROWTH_RATIO_WAD);
        LinearDiscountNode memory discountNode = _createValidLinearDiscountNode();

        vm.expectRevert(ModuleERC4626Ratio.ModuleERC4626RatioInvalidInput.selector);
        new MockAltoERC4626RatioLinearDiscountOracle(OWNER, ratioNode, discountNode, 1.05 ether);
    }

    function test_RevertWhen_ERC4626RatioNodeInitialTimestampIsGreaterThanBlockTimestamp() external givenInvalidInputs {
        ERC4626RatioNode memory ratioNode = _createValidERC4626RatioNode(
            DEFAULT_INITIAL_RATIO, block.timestamp + 1, DEFAULT_MAX_YEARLY_GROWTH_RATIO_WAD
        );
        LinearDiscountNode memory discountNode = _createValidLinearDiscountNode();

        vm.expectRevert(ModuleERC4626Ratio.ModuleERC4626RatioInvalidInput.selector);
        new MockAltoERC4626RatioLinearDiscountOracle(OWNER, ratioNode, discountNode, 1.05 ether);
    }

    function test_RevertWhen_ERC4626RatioNodeMaxYearlyGrowthRatioWadIsZero() external givenInvalidInputs {
        uint256 pastTimestamp = block.timestamp > 1 hours ? block.timestamp - 1 hours : block.timestamp;
        ERC4626RatioNode memory ratioNode = _createValidERC4626RatioNode(DEFAULT_INITIAL_RATIO, pastTimestamp, 0);
        LinearDiscountNode memory discountNode = _createValidLinearDiscountNode();

        vm.expectRevert(ModuleERC4626Ratio.ModuleERC4626RatioInvalidInput.selector);
        new MockAltoERC4626RatioLinearDiscountOracle(OWNER, ratioNode, discountNode, 1.05 ether);
    }

    function test_RevertWhen_LinearDiscountNodeMaturityIsNotInFuture() external givenInvalidInputs {
        ERC4626RatioNode memory ratioNode = _createValidERC4626RatioNode();
        // maturity = block.timestamp is NOT strictly in the future - fails before ptToken check
        LinearDiscountNode memory discountNode = LinearDiscountNode({
            ptToken: address(new MockPTToken(block.timestamp)),
            maturity: block.timestamp,
            baseDiscountPerYear: DEFAULT_BASE_DISCOUNT_PER_YEAR,
            inDecimals: 18,
            outDecimals: 36
        });

        vm.expectRevert(ModuleLinearDiscount.ModuleLinearDiscountInvalidInput.selector);
        new MockAltoERC4626RatioLinearDiscountOracle(OWNER, ratioNode, discountNode, 1.05 ether);
    }

    function test_RevertWhen_LinearDiscountNodePTTokenIsZeroAddress() external givenInvalidInputs {
        ERC4626RatioNode memory ratioNode = _createValidERC4626RatioNode();
        LinearDiscountNode memory discountNode = LinearDiscountNode({
            ptToken: address(0),
            maturity: block.timestamp + SECONDS_PER_YEAR,
            baseDiscountPerYear: DEFAULT_BASE_DISCOUNT_PER_YEAR,
            inDecimals: 18,
            outDecimals: 36
        });

        vm.expectRevert(ModuleLinearDiscount.ModuleLinearDiscountInvalidInput.selector);
        new MockAltoERC4626RatioLinearDiscountOracle(OWNER, ratioNode, discountNode, 1.05 ether);
    }

    function test_RevertWhen_LinearDiscountNodePTTokenExpiryDoesNotMatchMaturity() external givenInvalidInputs {
        ERC4626RatioNode memory ratioNode = _createValidERC4626RatioNode();
        uint256 maturity = block.timestamp + SECONDS_PER_YEAR;
        // Deploy PT token whose expiry differs from the node's maturity
        address ptToken = address(new MockPTToken(maturity + 1));
        LinearDiscountNode memory discountNode = LinearDiscountNode({
            ptToken: ptToken,
            maturity: maturity,
            baseDiscountPerYear: DEFAULT_BASE_DISCOUNT_PER_YEAR,
            inDecimals: 18,
            outDecimals: 36
        });

        vm.expectRevert(ModuleLinearDiscount.ModuleLinearDiscountInvalidInput.selector);
        new MockAltoERC4626RatioLinearDiscountOracle(OWNER, ratioNode, discountNode, 1.05 ether);
    }

    function test_RevertWhen_LinearDiscountNodeBaseDiscountPerYearExceedsMathPrecision() external givenInvalidInputs {
        ERC4626RatioNode memory ratioNode = _createValidERC4626RatioNode();
        // 1e18 + 1 exceeds MATH_PRECISION (1e18)
        LinearDiscountNode memory discountNode =
            _createValidLinearDiscountNode(block.timestamp + SECONDS_PER_YEAR, 1e18 + 1, 18, 36);

        vm.expectRevert(ModuleLinearDiscount.ModuleLinearDiscountInvalidInput.selector);
        new MockAltoERC4626RatioLinearDiscountOracle(OWNER, ratioNode, discountNode, 1.05 ether);
    }

    function test_RevertWhen_LinearDiscountNodeDecimalSumExceeds54() external givenInvalidInputs {
        ERC4626RatioNode memory ratioNode = _createValidERC4626RatioNode();
        // 30 + 25 = 55 > 54
        LinearDiscountNode memory discountNode =
            _createValidLinearDiscountNode(block.timestamp + SECONDS_PER_YEAR, DEFAULT_BASE_DISCOUNT_PER_YEAR, 30, 25);

        vm.expectRevert(ModuleLinearDiscount.ModuleLinearDiscountInvalidInput.selector);
        new MockAltoERC4626RatioLinearDiscountOracle(OWNER, ratioNode, discountNode, 1.05 ether);
    }

    function test_RevertWhen_OwnerIsZeroAddress() external givenInvalidInputs {
        ERC4626RatioNode memory ratioNode = _createValidERC4626RatioNode();
        LinearDiscountNode memory discountNode = _createValidLinearDiscountNode();

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new MockAltoERC4626RatioLinearDiscountOracle(address(0), ratioNode, discountNode, 1.05 ether);
    }

    function test_WhenValidInputsAreProvided() external givenValidInputs {
        ERC4626RatioNode memory ratioNode = _createValidERC4626RatioNode();
        LinearDiscountNode memory discountNode = _createValidLinearDiscountNode();

        vm.expectEmit(true, true, true, true);
        emit IAltoERC4626RatioLinearDiscountOracleEvents.SetERC4626RatioNode(ERC4626RatioNode(0, 0, 0), ratioNode);

        vm.expectEmit(true, true, true, true);
        emit IAltoERC4626RatioLinearDiscountOracleEvents.SetLinearDiscountNode(
            LinearDiscountNode(address(0), 0, 0, 0, 0), discountNode
        );

        MockAltoERC4626RatioLinearDiscountOracle oracle =
            new MockAltoERC4626RatioLinearDiscountOracle(OWNER, ratioNode, discountNode, 1.05 ether);

        (uint256 initialRatio, uint256 initialTimestamp, uint256 maxYearlyGrowthRatioWad) = oracle.erc4626RatioNode();
        assertEq(initialRatio, DEFAULT_INITIAL_RATIO);
        uint256 expectedTimestamp = block.timestamp > 1 hours ? block.timestamp - 1 hours : block.timestamp;
        assertEq(initialTimestamp, expectedTimestamp);
        assertEq(maxYearlyGrowthRatioWad, DEFAULT_MAX_YEARLY_GROWTH_RATIO_WAD);

        (address ptToken, uint256 maturity, uint256 baseDiscountPerYear, uint8 inDecimals, uint8 outDecimals) =
            oracle.linearDiscountNode();
        assertEq(ptToken, discountNode.ptToken);
        assertEq(maturity, block.timestamp + SECONDS_PER_YEAR / 4);
        assertEq(baseDiscountPerYear, DEFAULT_BASE_DISCOUNT_PER_YEAR);
        assertEq(inDecimals, DEFAULT_IN_DECIMALS);
        assertEq(outDecimals, DEFAULT_OUT_DECIMALS);

        // it should set owner correctly
        assertEq(oracle.owner(), OWNER);
    }
}
