// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {MockAltoERC4626RatioLinearDiscountOracle} from "../mocks/MockAltoERC4626RatioLinearDiscountOracle.sol";
import {MockPTToken} from "../mocks/MockPTToken.sol";
import {ERC4626RatioNode, LinearDiscountNode} from "@alto/oracles/interfaces/IModuleNode.sol";
import {SECONDS_PER_YEAR} from "@alto/oracles/modules/ModuleLinearDiscount.sol";

contract AltoERC4626RatioLinearDiscountOracleCommon is Test {
    address constant OWNER = address(0x1);
    address constant NON_OWNER = address(0x2);

    uint256 constant DEFAULT_INITIAL_RATIO = 1 ether;
    uint256 constant DEFAULT_MAX_YEARLY_GROWTH_RATIO_WAD = 0.1 ether; // 10%/year
    uint256 constant DEFAULT_BASE_DISCOUNT_PER_YEAR = 0.1 ether; // 10%/year
    uint8 constant DEFAULT_IN_DECIMALS = 18;
    uint8 constant DEFAULT_OUT_DECIMALS = 36;

    function _createValidERC4626RatioNode(
        uint256 initialRatio,
        uint256 initialTimestamp,
        uint256 maxYearlyGrowthRatioWad
    ) internal pure returns (ERC4626RatioNode memory) {
        return ERC4626RatioNode({
            initialRatio: initialRatio,
            initialTimestamp: initialTimestamp,
            maxYearlyGrowthRatioWad: maxYearlyGrowthRatioWad
        });
    }

    function _createValidERC4626RatioNode() internal view returns (ERC4626RatioNode memory) {
        uint256 pastTimestamp = block.timestamp > 1 hours ? block.timestamp - 1 hours : block.timestamp;
        return _createValidERC4626RatioNode(DEFAULT_INITIAL_RATIO, pastTimestamp, DEFAULT_MAX_YEARLY_GROWTH_RATIO_WAD);
    }

    /// @dev Deploys a MockPTToken with the given expiry and builds a LinearDiscountNode using it.
    function _createValidLinearDiscountNode(
        uint256 maturity,
        uint256 baseDiscountPerYear,
        uint8 inDecimals,
        uint8 outDecimals
    ) internal returns (LinearDiscountNode memory) {
        address ptToken = address(new MockPTToken(maturity));
        return LinearDiscountNode({
            ptToken: ptToken,
            maturity: maturity,
            baseDiscountPerYear: baseDiscountPerYear,
            inDecimals: inDecimals,
            outDecimals: outDecimals
        });
    }

    function _createValidLinearDiscountNode() internal returns (LinearDiscountNode memory) {
        return _createValidLinearDiscountNode(
            block.timestamp + SECONDS_PER_YEAR / 4,
            DEFAULT_BASE_DISCOUNT_PER_YEAR,
            DEFAULT_IN_DECIMALS,
            DEFAULT_OUT_DECIMALS
        );
    }
}
