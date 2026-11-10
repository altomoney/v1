// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {BaseMarketInitParams, IMarketBase} from "@alto/lending/interfaces/IMarket.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {FixedPointMath} from "@alto/utils/FixedPointMath.sol";
import {MockMarket} from "@alto-test/helpers/MockMarket.sol";

abstract contract FixedRateIrmCommon is Test {
    using FixedPointMath for uint256;

    error MarketCallFailed();

    address internal constant OWNER = address(0xA11CE);
    address internal constant OTHER = address(0xB0B);
    uint256 internal constant START = 1_000_000;
    uint256 internal constant INITIAL_RATE = 1e9;
    uint256 internal constant MAX_RATE = 8e18 / uint256(365 days);

    FixedRateIrm internal irm;
    MockMarket internal market;

    function setUp() public virtual {
        vm.warp(START);
        irm = new FixedRateIrm(INITIAL_RATE, OWNER);
        market = new MockMarket();
        market.initialize(
            BaseMarketInitParams({
                borrowToken: address(0xB001),
                collateralToken: address(0xC011),
                irm: address(0),
                owner: OWNER,
                emergencyAdmin: OWNER,
                oracle: address(0x0A11),
                maxLtv: 0.75e18,
                feeRecipient: OWNER,
                liquidationEngine: address(0)
            }),
            0
        );
        market.modifyTotalSupply(1000 ether);
        market.modifyTotalBorrowed(800 ether);
    }

    function _bindMarket() internal {
        vm.prank(OWNER);
        market.setIrm(address(irm), true);
    }

    function _pauseMarket() internal {
        vm.prank(OWNER);
        market.pause(PAUSE_TYPE, true);
        vm.expectCall(address(market), abi.encodeCall(IMarketBase.accrueInterest, ()), 0);
    }

    function _mockPauseQueryFailure() internal {
        vm.mockCallRevert(
            address(market),
            abi.encodeCall(IPausable.paused, (PAUSE_TYPE)),
            abi.encodeWithSelector(MarketCallFailed.selector)
        );
    }

    /// @dev Interest fits uint128 and the supply addition succeeds, but adding
    /// it to saturated borrowed assets reverts after the real IRM callback.
    function _prepareMarketAccrualOverflow() internal returns (uint256 supply, uint256 borrowed) {
        borrowed = type(uint128).max;
        supply = borrowed * 9 / 10;
        market.modifyTotalSupply(supply - 1000 ether);
        market.modifyTotalBorrowed(borrowed - 800 ether);
    }

    function _assertMarketBalances(uint256 expectedSupply, uint256 expectedBorrowed) internal view {
        (uint128 supplyAssets, uint128 supplyShares) = market.totalSupply();
        (uint128 borrowedAssets, uint128 borrowedShares) = market.totalBorrowed();
        assertEq(supplyAssets, expectedSupply, "market supply assets");
        assertEq(borrowedAssets, expectedBorrowed, "market borrowed assets");
        assertEq(supplyShares, 0, "market supply shares");
        assertEq(borrowedShares, 0, "market borrowed shares");
    }

    function _assertState(uint256 rate, uint48 timestamp) internal view {
        (uint256 actualRate, uint48 actualTimestamp) = irm.irState();
        assertEq(actualRate, rate, "borrowRate");
        assertEq(actualTimestamp, timestamp, "lastUpdate");
    }

    function _assertStateLog(Vm.Log memory entry, uint256 rate, uint48 timestamp) internal view {
        assertEq(entry.emitter, address(irm));
        assertEq(entry.topics.length, 1);
        assertEq(entry.topics[0], FixedRateIrm.IRStateUpdated.selector);
        assertEq(entry.data, abi.encode(FixedRateIrm.IRState(rate, timestamp)));
    }

    function _expectedInterest(uint256 debt, uint256 rate, uint256 elapsed) internal pure returns (uint256) {
        return debt.multiplyWithPrecision(rate.calculateCompoundInterest(elapsed));
    }
}
