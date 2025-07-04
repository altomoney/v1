// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";

import {FixedPointMath} from "@alto/utils/FixedPointMath.sol";

import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {ERC20Mock} from "@alto-test/helpers/ERC20Mock.sol";
import {OracleMock} from "@alto/oracles/mocks/OracleMock.sol";
import {ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {IMarket, LiquidationConfiguration} from "@alto/lending/interfaces/IMarket.sol";
import {IrmCommon} from "./IrmCommon.t.sol";
import {MockMarketDeployer, MockMarket} from "@alto-test/helpers/MockMarket.sol";
import {RiskParams} from "@alto/lending/interfaces/IMarket.sol";

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
        OracleMock(oracle).setPrice(ORACLE_PRICE_PRECISION);

        market = MockMarket(
            MockMarketDeployer.deployMarket(
                RiskParams({
                    borrowToken: address(borrowToken),
                    collateralToken: address(collateralToken),
                    irm: address(0),
                    owner: address(this),
                    oracle: address(oracle),
                    maxLtv: LTV,
                    debtCeiling: 0,
                    feeRecipient: address(this),
                    borrowOpeningFee: 0
                }),
                LiquidationConfiguration({
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
                })
            )
        );

        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);

        vm.prank(USER);
        market.setAuthorization(address(this), true);

        newMarket = MockMarket(
            MockMarketDeployer.deployMarket(
                RiskParams({
                    borrowToken: address(borrowToken),
                    collateralToken: address(collateralToken),
                    irm: address(0),
                    owner: address(this),
                    oracle: address(oracle),
                    maxLtv: LTV,
                    debtCeiling: 0,
                    feeRecipient: address(this),
                    borrowOpeningFee: 0
                }),
                LiquidationConfiguration({
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
                })
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
        market.setIrm(address(irm));

        market.addSupply(borrowedAmount, 0, USER);
        market.addCollateral(100 ether, USER);
        market.borrow(borrowedAmount, 0, USER, USER, "");

        uint256 expectedInterest = _getAccruedInterest(borrowedAmount, borrowRate, 10 minutes);

        vm.warp(block.timestamp + 10 minutes);
        market.accrueInterest();
        if (executeMoreThanOnce) {
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
        market.setIrm(address(irm));

        deal(address(borrowToken), address(this), borrowedAmount);

        uint256 collateralAmount = borrowedAmount.divideWithPrecisionUp(LTV);

        market.addSupply(borrowedAmount, 0, USER);
        market.addCollateral(collateralAmount, USER);
        market.borrow(borrowedAmount, 0, USER, USER, "");

        assertEq(IMarket(address(market)).totalBorrowed().assets, borrowedAmount);
        uint256 expectedInterest = _getAccruedInterest(borrowedAmount, borrowRate, elapsedTime);

        vm.warp(block.timestamp + elapsedTime);
        market.accrueInterest();

        uint256 totalBorrowed = IMarket(address(market)).totalBorrowed().assets;
        assertEq(totalBorrowed, borrowedAmount + expectedInterest);

        uint256 expectedInterestAfterIrmUpdate = _getAccruedInterest(totalBorrowed, newBorrowRate, elapsedTime);

        // change borrow rate either via irm or market
        if (testIrmSwap) {
            FixedRateIrm(irm).setBorrowRate(newBorrowRate);
        } else {
            address irm2 = address(new FixedRateIrm(newBorrowRate, address(this)));
            market.setIrm(address(irm2));
        }
        assertEq(totalBorrowed, borrowedAmount + expectedInterest);

        vm.warp(block.timestamp + elapsedTime);
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
        market.accrueInterest();
        assertEq(
            IMarket(address(market)).totalBorrowed().assets,
            totalBorrowedAfterIrmUpdateAndRepay + expectedInterestAfterRepay
        );
    }
}
