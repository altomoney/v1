// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import {FixedPointMath} from "@alto/utils/FixedPointMath.sol";

import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {OracleMock} from "@alto-test/helpers/OracleMock.sol";
import {LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {IMarket, IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";
import {LiquidationConfiguration} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {IrmCommon} from "./IrmCommon.t.sol";
import {MockMarketDeployer, MockMarket} from "@alto-test/helpers/MockMarket.sol";

uint256 constant MIN_AMOUNT = 1000;
uint256 constant MAX_AMOUNT = 2 ** 64;

contract FixedRateIrmUpdateTest is IrmCommon {
    using FixedPointMath for uint256;

    uint256 MAX_BORROW_RATE = new FixedRateIrm(0.01 ether / uint256(365 days), address(1)).MAX_BORROW_RATE();

    MockMarket market;
    MockMarket newMarket;

    function setUp() public override {
        super.setUp();

        address oracle = address(new OracleMock());
        OracleMock(oracle).setPrice(LENDING_ORACLE_PRICE_PRECISION);

        LiquidationConfiguration memory liquidationConfig = LiquidationConfiguration({
            maxLiquidationLtv: 0.8 ether,
            dynamicBonusFeeStart: 0.03 ether,
            ltvForCompleteLiquidation: 0.9 ether,
            dynamicBonusFeeDecaySteepness: 5 ether,
            liquidationBaseFee: 0.05 ether,
            minPenaltyPercentage: 0.01 ether,
            protocolFeePercentage: 0.075 ether,
            isEnabledPriorityLiquidation: true,
            disablePriorityLiquidationAbovePositionLtv: 0.95 ether,
            priorityLiquidationGracePeriod: 5 minutes,
            taggerLiquidationGracePeriod: 2 minutes,
            liquidationWindowTag: 3 days
        });

        market = MockMarket(
            MockMarketDeployer.deployMarket(
                address(borrowToken),
                address(collateralToken),
                address(0),
                address(this),
                address(oracle),
                LTV,
                0,
                address(this),
                liquidationConfig
            )
        );

        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);

        vm.prank(USER);
        market.setAuthorization(address(this), true);

        // Liquidation engine will be set after new market deployment
        newMarket = MockMarket(
            MockMarketDeployer.deployMarket(
                address(borrowToken),
                address(collateralToken),
                address(0),
                address(this),
                address(oracle),
                LTV,
                0,
                address(this),
                liquidationConfig
            )
        );
    }

    function _getAccruedInterest(uint256 borrowedAmount, uint256 borrowRate, uint256 time)
        internal
        pure
        returns (uint256)
    {
        return uint256(borrowedAmount).multiplyWithPrecision(borrowRate.calculateCompoundInterest(time));
    }

    function testAccrueInterest(bool executeMoreThanOnce, uint256 borrowedAmount, uint256 borrowRate) public {
        borrowRate = bound(borrowRate, 1, MAX_BORROW_RATE);
        borrowedAmount = bound(borrowedAmount, MIN_AMOUNT, MAX_AMOUNT);

        address irm = address(new FixedRateIrm(borrowRate, address(this)));
        market.setIrm(address(irm), false);

        market.addSupply(borrowedAmount, 0, USER);
        market.addCollateral(100 ether, USER);
        market.borrow(borrowedAmount, 0, USER, USER, "");

        uint256 expectedInterest = _getAccruedInterest(borrowedAmount, borrowRate, 10 minutes);

        vm.warp(block.timestamp + 10 minutes);
        FixedRateIrm.IRState memory irState = FixedRateIrm.IRState({borrowRate: borrowRate, lastUpdate: 0});
        irState.lastUpdate = uint48(block.timestamp);
        vm.expectEmit(true, true, true, true, address(irm));
        emit FixedRateIrm.IRStateUpdated(irState);
        market.accrueInterest();
        if (executeMoreThanOnce) {
            vm.expectEmit(true, true, true, true, address(irm));
            emit FixedRateIrm.IRStateUpdated(irState);
            market.accrueInterest();
        }
        assertEq(IMarket(address(market)).totalBorrowed().assets, borrowedAmount + expectedInterest);
    }

    /// @notice Test the update of the interest rate both from market and IRM side
    function testUpdateInterestRate(
        bool testIrmSwap,
        uint256 elapsedTime,
        uint256 borrowRate,
        uint256 newBorrowRate,
        uint256 borrowedAmount,
        uint256 toRepay
    ) public {
        elapsedTime = bound(elapsedTime, 0 seconds, 365 days);
        borrowRate = bound(borrowRate, 1, MAX_BORROW_RATE);
        newBorrowRate = bound(newBorrowRate, 1, MAX_BORROW_RATE);
        borrowedAmount = bound(borrowedAmount, MIN_AMOUNT, MAX_AMOUNT);

        address irm = address(new FixedRateIrm(borrowRate, address(this)));
        market.setIrm(address(irm), false);

        deal(address(borrowToken), address(this), borrowedAmount);

        uint256 collateralAmount = borrowedAmount.divideWithPrecisionUp(LTV);

        market.addSupply(borrowedAmount, 0, USER);
        market.addCollateral(collateralAmount, USER);
        market.borrow(borrowedAmount, 0, USER, USER, "");

        assertEq(IMarket(address(market)).totalBorrowed().assets, borrowedAmount);
        uint256 expectedInterest = _getAccruedInterest(borrowedAmount, borrowRate, elapsedTime);

        FixedRateIrm.IRState memory irState = FixedRateIrm.IRState({borrowRate: borrowRate, lastUpdate: 0});

        vm.warp(block.timestamp + elapsedTime);
        irState.lastUpdate = uint48(block.timestamp);
        vm.expectEmit(true, true, true, true, address(irm));
        emit FixedRateIrm.IRStateUpdated(irState);
        market.accrueInterest();

        uint256 totalBorrowed = IMarket(address(market)).totalBorrowed().assets;
        assertEq(totalBorrowed, borrowedAmount + expectedInterest);

        uint256 expectedInterestAfterIrmUpdate = _getAccruedInterest(totalBorrowed, newBorrowRate, elapsedTime);

        // change borrow rate either via irm or market
        if (testIrmSwap) {
            irState.borrowRate = newBorrowRate;
            vm.expectEmit(true, true, true, true, address(irm));
            emit FixedRateIrm.IRStateUpdated(irState);
            FixedRateIrm(irm).setBorrowRate(newBorrowRate);
        } else {
            address irm2 = address(new FixedRateIrm(newBorrowRate, address(this)));
            market.setIrm(address(irm2), false);
        }
        assertEq(totalBorrowed, borrowedAmount + expectedInterest);

        vm.warp(block.timestamp + elapsedTime);
        irState.borrowRate = newBorrowRate;
        irState.lastUpdate = uint48(block.timestamp);
        vm.expectEmit(true, true, true, true);
        emit FixedRateIrm.IRStateUpdated(irState);
        market.accrueInterest();
        assertEq(IMarket(address(market)).totalBorrowed().assets, totalBorrowed + expectedInterestAfterIrmUpdate);

        toRepay = bound(toRepay, 1, borrowedAmount);
        uint256 totalBorrowedAfterIrmUpdateAndRepay = IMarket(address(market)).totalBorrowed().assets - toRepay;
        uint256 expectedInterestAfterRepay =
            _getAccruedInterest(totalBorrowedAfterIrmUpdateAndRepay, newBorrowRate, elapsedTime);

        // repay and check if new borrow rate interest is accrued correctly
        deal(address(borrowToken), address(this), toRepay);
        market.repay(toRepay, 0, USER);

        vm.warp(block.timestamp + elapsedTime);
        irState.lastUpdate = uint48(block.timestamp);
        vm.expectEmit(true, true, true, false);
        emit FixedRateIrm.IRStateUpdated(irState);
        market.accrueInterest();
        assertEq(
            IMarket(address(market)).totalBorrowed().assets,
            totalBorrowedAfterIrmUpdateAndRepay + expectedInterestAfterRepay
        );
    }
}
