// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";

import {FixedPointMath} from "@alto/lending/libraries/FixedPointMath.sol";

import {FixedRateIrm} from "@alto/lending/FixedRateIrm.sol";
import {IIrm} from "@alto/lending/interfaces/IIrm.sol";

uint256 constant MIN_AMOUNT = 1000;
uint256 constant MAX_AMOUNT = 2 ** 64;

contract FixedRateIrmMock is FixedRateIrm {
    constructor(uint256 _borrowRate, address _owner) FixedRateIrm(_borrowRate, _owner) {}

    function borrowRate() external view returns (uint256) {
        return irState.borrowRate;
    }

    function lastUpdate() external view returns (uint48) {
        return irState.lastUpdate;
    }
}

contract MockMarket {
    function accrueInterest() external {}
}

contract FixedRateIrmTest is Test {
    using FixedPointMath for uint256;

    FixedRateIrmMock public fixedRateIrm;

    uint256 constant INITIAL_BORROW_RATE = 1 ether / uint256(365 days);

    function setUp() external {
        MockMarket mockMarket = new MockMarket();
        fixedRateIrm = new FixedRateIrmMock(INITIAL_BORROW_RATE, address(this));
        fixedRateIrm.setMarket(address(mockMarket));
    }

    function testSetBorrowRateViaConstuctor(uint256 borrowRate) external {
        borrowRate = bound(borrowRate, 1, fixedRateIrm.MAX_BORROW_RATE());

        FixedRateIrmMock newFixedRateIrm = new FixedRateIrmMock(borrowRate, address(this));

        assertEq(newFixedRateIrm.borrowRate(), borrowRate);
    }

    function testSetBorrowRateViaConstuctorZero() external {
        vm.expectRevert(IIrm.Alto_IrmInvalidParams.selector);
        new FixedRateIrmMock(0, address(this));
    }

    function testSetBorrowRateViaConstuctorOverMaxBorrowRate(uint256 borrowRate) external {
        borrowRate = bound(borrowRate, fixedRateIrm.MAX_BORROW_RATE() + 1, type(uint256).max);

        vm.expectRevert(IIrm.Alto_IrmInvalidParams.selector);
        new FixedRateIrmMock(borrowRate, address(this));
    }

    function testSetMarket() external {
        FixedRateIrmMock irmMock = new FixedRateIrmMock(INITIAL_BORROW_RATE, address(this));

        assertEq(irmMock.lastUpdate(), 0);
        irmMock.setMarket(address(1));
        assertEq(irmMock.market(), address(1));
        assertEq(irmMock.lastUpdate(), block.timestamp);
    }

    function testSetMarketRewrite() external {
        FixedRateIrmMock irmMock = new FixedRateIrmMock(INITIAL_BORROW_RATE, address(this));

        irmMock.setMarket(address(1));
        vm.expectRevert(IIrm.Alto_IrmMarketAlreadySet.selector);
        irmMock.setMarket(address(2));
    }

    function testSetBorrowRate(uint256 borrowRate) external {
        borrowRate = bound(borrowRate, 1, fixedRateIrm.MAX_BORROW_RATE());

        fixedRateIrm.setBorrowRate(borrowRate);

        assertEq(fixedRateIrm.borrowRate(), borrowRate);
    }

    function testSetBorrowRateEvent(uint256 borrowRate) external {
        borrowRate = bound(borrowRate, 1, fixedRateIrm.MAX_BORROW_RATE());

        vm.expectEmit(true, true, true, true, address(fixedRateIrm));
        emit FixedRateIrm.SetBorrowRate(borrowRate);
        fixedRateIrm.setBorrowRate(borrowRate);
    }

    function testSetBorrowRateMarketUnset(uint256 borrowRate) external {
        FixedRateIrmMock irmMock = new FixedRateIrmMock(INITIAL_BORROW_RATE, address(this));

        vm.expectRevert(IIrm.Alto_IrmMarketNotSet.selector);
        irmMock.setBorrowRate(borrowRate);
    }

    function testSetBorrowRateZero() external {
        vm.expectRevert(IIrm.Alto_IrmInvalidParams.selector);
        fixedRateIrm.setBorrowRate(0);
    }

    function testSetBorrowRateOverMaxBorrowRate(uint256 borrowRate) external {
        borrowRate = bound(borrowRate, fixedRateIrm.MAX_BORROW_RATE() + 1, type(uint256).max);

        vm.expectRevert(IIrm.Alto_IrmInvalidParams.selector);
        fixedRateIrm.setBorrowRate(borrowRate);
    }

    function testInterestRateView() external {
        uint256 firstBlockTimestamp = block.timestamp;
        assertEq(fixedRateIrm.lastUpdate(), firstBlockTimestamp);

        vm.warp(block.timestamp + 1 days);
        (uint256 interest, uint256 borrowRate) = fixedRateIrm.updateInterestRateView(0, 0);
        assertEq(interest, 0);
        assertEq(borrowRate, INITIAL_BORROW_RATE);
        assertEq(fixedRateIrm.lastUpdate(), firstBlockTimestamp);
    }

    function testUnsetMarketInterestRateViewRevert() external {
        FixedRateIrmMock irmMock = new FixedRateIrmMock(INITIAL_BORROW_RATE, address(this));

        vm.expectRevert(IIrm.Alto_IrmMarketNotSet.selector);
        irmMock.updateInterestRateView(0, 0);
    }

    function _getAccruedInterest(uint256 borrowedAmount, uint256 borrowRate, uint256 time)
        internal
        view
        returns (uint256)
    {
        return uint256(borrowedAmount).multiplyWithPrecision(borrowRate.calculateCompoundInterest(time));
    }

    function testInterestRate() external {
        assertEq(fixedRateIrm.lastUpdate(), block.timestamp);

        vm.warp(block.timestamp + 1 days);

        vm.prank(address(fixedRateIrm.market()));
        (uint256 interest, uint256 borrowRate) = fixedRateIrm.updateInterestRate(0, 1000 ether);

        assertEq(interest, _getAccruedInterest(1000 ether, INITIAL_BORROW_RATE, 1 days));
        assertEq(borrowRate, INITIAL_BORROW_RATE);
        assertEq(fixedRateIrm.lastUpdate(), block.timestamp);
    }

    function testUnsetMarketInterestRateRevert() external {
        FixedRateIrmMock irmMock = new FixedRateIrmMock(INITIAL_BORROW_RATE, address(this));

        vm.prank(address(fixedRateIrm.market()));
        vm.expectRevert(IIrm.Alto_IrmUnauthorized.selector);
        irmMock.updateInterestRate(0, 0);
    }

    function testNonMarketInterestRateRevert() external {
        vm.expectRevert(IIrm.Alto_IrmUnauthorized.selector);
        fixedRateIrm.updateInterestRate(0, 0);
    }
}
