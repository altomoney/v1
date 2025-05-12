// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

// needed for deployCode (and Test)
import "forge-std/Test.sol";

import {FixedPointMath} from "@alto-monorepo/lending/libraries/FixedPointMath.sol";

import {FixedRateIrm} from "@alto-monorepo/lending/FixedRateIrm.sol";
import {Erc20Mock} from "../../helpers/Erc20Mock.sol";
import {OracleMock} from "@alto-monorepo/lending/mocks/OracleMock.sol";
import {ORACLE_PRICE_PRECISION} from "@alto-monorepo/lending/interfaces/IOracle.sol";
import {IMarket, LiquidationConfiguration} from "@alto-monorepo/lending/interfaces/IMarket.sol";

uint256 constant MIN_AMOUNT = 1000;
uint256 constant MAX_AMOUNT = 2 ** 64;

contract FixedRateIrmUpdateTest is Test {
    using FixedPointMath for uint256;

    Erc20Mock internal borrowToken;
    Erc20Mock internal collateralToken;

    address internal immutable USER = makeAddr("User");

    uint256 constant INITIAL_AMOUNT = 1000000 ether;

    uint256 MAX_BORROW_RATE = new FixedRateIrm(0.01 ether / uint256(365 days), address(1)).MAX_BORROW_RATE();

    uint256 internal constant LTV = 0.75 ether;

    function setUp() public {
        borrowToken = new Erc20Mock("borrow", "B");
        vm.label(address(borrowToken), "borrowToken");
        collateralToken = new Erc20Mock("collateral", "C");
        vm.label(address(collateralToken), "collateralToken");

        deal(address(borrowToken), address(this), INITIAL_AMOUNT);
        deal(address(collateralToken), address(this), INITIAL_AMOUNT);
    }

    function _getAccruedInterest(uint256 borrowedAmount, uint256 borrowRate, uint256 time)
        internal
        view
        returns (uint256)
    {
        return uint256(borrowedAmount).multiplyWithPrecision(borrowRate.calculateCompoundInterest(time));
    }

    function createMarketWithIrm(address irm) internal returns (IMarket) {
        address oracle = address(new OracleMock());
        OracleMock(oracle).setPrice(ORACLE_PRICE_PRECISION);

        IMarket market = IMarket(
            deployCode(
                "AltoBorrowMarket.sol",
                abi.encode(
                    address(borrowToken),
                    address(collateralToken),
                    address(irm),
                    address(this),
                    address(oracle),
                    LTV,
                    LiquidationConfiguration({
                        maxLiquidationLtv: 0.8 ether,
                        dynamicBonusFeeStart: 0.03 ether,
                        ltvForCompleteLiquidation: 0.9 ether,
                        dynamicBonusFeeDecaySteepness: 5 ether,
                        liquidationBaseFee: 0.05 ether,
                        minPenaltyPercentage: 0.01 ether
                    })
                )
            )
        );

        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);

        vm.prank(USER);
        market.setAuthorization(address(this), true);

        return market;
    }

    function testAccrueInterest(bool executeMoreThanOnce, uint256 borrowedAmount, uint256 borrowRate) public {
        borrowRate = bound(borrowRate, 1, MAX_BORROW_RATE);
        borrowedAmount = bound(borrowedAmount, MIN_AMOUNT, MAX_AMOUNT);

        address irm = address(new FixedRateIrm(borrowRate, address(this)));
        IMarket market = createMarketWithIrm(irm);

        market.addSupply(borrowedAmount, 0, USER);
        market.addCollateral(100 ether, USER);
        market.borrow(borrowedAmount, 0, USER, USER);

        uint256 expectedInterest = _getAccruedInterest(borrowedAmount, borrowRate, 10 minutes);

        vm.warp(block.timestamp + 10 minutes);
        market.accrueInterest();
        if (executeMoreThanOnce) {
            market.accrueInterest();
        }
        assertEq(market.totalBorrowed().assets, borrowedAmount + expectedInterest);
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
        IMarket market = createMarketWithIrm(irm);

        deal(address(borrowToken), address(this), borrowedAmount);

        uint256 collateralAmount = borrowedAmount.divideWithPrecisionUp(LTV);

        market.addSupply(borrowedAmount, 0, USER);
        market.addCollateral(collateralAmount, USER);
        market.borrow(borrowedAmount, 0, USER, USER);

        assertEq(market.totalBorrowed().assets, borrowedAmount);
        uint256 expectedInterest = _getAccruedInterest(borrowedAmount, borrowRate, elapsedTime);

        vm.warp(block.timestamp + elapsedTime);
        market.accrueInterest();

        uint256 totalBorrowed = market.totalBorrowed().assets;
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
        assertEq(market.totalBorrowed().assets, totalBorrowed + expectedInterestAfterIrmUpdate);

        toRepay = bound(toRepay, 1, borrowedAmount);
        uint256 totalBorrowedAfterIrmUpdateAndRepay = market.totalBorrowed().assets - toRepay;
        uint256 expectedInterestAfterRepay =
            _getAccruedInterest(totalBorrowedAfterIrmUpdateAndRepay, newBorrowRate, elapsedTime);

        // repay and check if new borrow rate interest is accrued correctly
        deal(address(borrowToken), address(this), toRepay);
        market.repay(toRepay, 0, USER);

        vm.warp(block.timestamp + elapsedTime);
        market.accrueInterest();
        assertEq(market.totalBorrowed().assets, totalBorrowedAfterIrmUpdateAndRepay + expectedInterestAfterRepay);
    }
}
