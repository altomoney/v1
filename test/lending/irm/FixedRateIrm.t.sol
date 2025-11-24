// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";

import {FixedPointMath} from "@alto/utils/FixedPointMath.sol";

import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {IIrm} from "@alto/lending/interfaces/IIrm.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {MarketDeployer} from "@alto/utils/MarketDeployer.sol";
import {AltoBorrowMarket} from "@alto/lending/AltoBorrowMarket.sol";
import {
    LiquidationConfiguration,
    BaseMarketInitParams,
    BorrowMarketInitParams
} from "@alto/lending/interfaces/IMarket.sol";
import {OracleMock} from "@alto/oracles/mocks/OracleMock.sol";

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

contract FixedRateIrmTest is Test {
    using FixedPointMath for uint256;

    address internal immutable OWNER = makeAddr("Owner");
    FixedRateIrmMock public fixedRateIrm;
    AltoBorrowMarket public market;

    uint256 constant INITIAL_BORROW_RATE = 1 ether / uint256(365 days);

    function setUp() external {
        fixedRateIrm = new FixedRateIrmMock(INITIAL_BORROW_RATE, address(this));
        address oracle = address(new OracleMock());
        LiquidationConfiguration memory liquidationConfig = LiquidationConfiguration({
            maxLiquidationLtv: 0.8 ether,
            dynamicBonusFeeStart: 0.03 ether,
            ltvForCompleteLiquidation: 0.9 ether,
            dynamicBonusFeeDecaySteepness: 5 ether,
            liquidationBaseFee: 0.05 ether,
            minPenaltyPercentage: 0.01 ether,
            protocolFeePercentage: 0 ether,
            isEnabledPriorityLiquidation: true,
            disablePriorityLiquidationAbovePositionLtv: type(uint256).max,
            priorityLiquidationGracePeriod: 5 minutes,
            taggerLiquidationGracePeriod: 2 minutes,
            liquidationWindowTag: 3 days
        });

        BaseMarketInitParams memory baseMarketInitParams = BaseMarketInitParams({
            borrowToken: address(1),
            collateralToken: address(2),
            irm: address(fixedRateIrm),
            owner: OWNER,
            oracle: address(oracle),
            maxLtv: 0.75 ether,
            feeRecipient: OWNER,
            liquidationConfiguration: liquidationConfig
        });

        BorrowMarketInitParams memory borrowMarketInitParams = BorrowMarketInitParams({
            baseMarketInitParams: baseMarketInitParams, initialBorrowOpeningFee: 0, supplyCapAssets: 0
        });
        market = AltoBorrowMarket(MarketDeployer.deployBorrowMarket(borrowMarketInitParams));

        vm.prank(OWNER);
        market.setPauser(OWNER, PAUSE_TYPE, true);
    }

    function testSetBorrowRateViaConstuctor(uint256 borrowRate) external {
        borrowRate = bound(borrowRate, 1, fixedRateIrm.MAX_BORROW_RATE());

        FixedRateIrmMock newFixedRateIrm = new FixedRateIrmMock(borrowRate, address(this));

        assertEq(newFixedRateIrm.borrowRate(), borrowRate);
    }

    function testSetBorrowRateViaConstuctorZero() external {
        vm.expectRevert(IIrm.IrmInvalidParams.selector);
        new FixedRateIrmMock(0, address(this));
    }

    function testSetBorrowRateViaConstuctorOverMaxBorrowRate(uint256 borrowRate) external {
        borrowRate = bound(borrowRate, fixedRateIrm.MAX_BORROW_RATE() + 1, type(uint256).max);

        vm.expectRevert(IIrm.IrmInvalidParams.selector);
        new FixedRateIrmMock(borrowRate, address(this));
    }

    function testSetMarket() external {
        FixedRateIrmMock irmMock = new FixedRateIrmMock(INITIAL_BORROW_RATE, address(this));

        assertEq(irmMock.lastUpdate(), 0);
        FixedRateIrm.IRState memory irState = FixedRateIrm.IRState({borrowRate: INITIAL_BORROW_RATE, lastUpdate: 0});
        irState.lastUpdate = uint48(block.timestamp);

        vm.expectEmit(true, true, true, true, address(irmMock));
        emit FixedRateIrm.IRStateUpdated(irState);
        irmMock.setMarket(address(1));

        assertEq(irmMock.market(), address(1));
        assertEq(irmMock.lastUpdate(), block.timestamp);
    }

    function testSetMarketRewrite() external {
        FixedRateIrmMock irmMock = new FixedRateIrmMock(INITIAL_BORROW_RATE, address(this));

        FixedRateIrm.IRState memory irState = FixedRateIrm.IRState({borrowRate: INITIAL_BORROW_RATE, lastUpdate: 0});
        irState.lastUpdate = uint48(block.timestamp);

        vm.expectEmit(true, true, true, true, address(irmMock));
        emit FixedRateIrm.IRStateUpdated(irState);
        irmMock.setMarket(address(1));

        vm.expectRevert(IIrm.IrmMarketAlreadySet.selector);
        irmMock.setMarket(address(2));
    }

    function testSetBorrowRate(uint256 borrowRate) external {
        borrowRate = bound(borrowRate, 1, fixedRateIrm.MAX_BORROW_RATE());

        FixedRateIrm.IRState memory irState = FixedRateIrm.IRState({borrowRate: borrowRate, lastUpdate: 0});

        vm.expectEmit(true, true, true, true, address(fixedRateIrm));
        emit FixedRateIrm.SetBorrowRate(borrowRate);
        emit FixedRateIrm.IRStateUpdated(irState);
        fixedRateIrm.setBorrowRate(borrowRate);

        assertEq(fixedRateIrm.borrowRate(), borrowRate);
    }

    function testSetBorrowRateEvent(uint256 borrowRate) external {
        borrowRate = bound(borrowRate, 1, fixedRateIrm.MAX_BORROW_RATE());

        vm.expectEmit(true, true, true, true, address(fixedRateIrm));
        emit FixedRateIrm.SetBorrowRate(borrowRate);
        fixedRateIrm.setBorrowRate(borrowRate);
    }

    function testSetBorrowRateEventMarketPaused(uint256 borrowRate) external {
        vm.startPrank(OWNER);
        market.pause(PAUSE_TYPE, true);
        vm.stopPrank();

        borrowRate = bound(borrowRate, 1, fixedRateIrm.MAX_BORROW_RATE());

        FixedRateIrm.IRState memory irState = FixedRateIrm.IRState({borrowRate: borrowRate, lastUpdate: 0});

        vm.expectEmit(true, true, true, true, address(fixedRateIrm));
        emit FixedRateIrm.SetBorrowRate(borrowRate);
        emit FixedRateIrm.IRStateUpdated(irState);
        fixedRateIrm.setBorrowRate(borrowRate);
    }

    function testSetBorrowRateMarketUnset(uint256 borrowRate) external {
        FixedRateIrmMock irmMock = new FixedRateIrmMock(INITIAL_BORROW_RATE, address(this));

        vm.expectRevert(IIrm.IrmMarketNotSet.selector);
        irmMock.setBorrowRate(borrowRate);
    }

    function testSetBorrowRateZero() external {
        vm.expectRevert(IIrm.IrmInvalidParams.selector);
        fixedRateIrm.setBorrowRate(0);
    }

    function testSetBorrowRateOverMaxBorrowRate(uint256 borrowRate) external {
        borrowRate = bound(borrowRate, fixedRateIrm.MAX_BORROW_RATE() + 1, type(uint256).max);

        vm.expectRevert(IIrm.IrmInvalidParams.selector);
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

        vm.expectRevert(IIrm.IrmMarketNotSet.selector);
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

        FixedRateIrm.IRState memory irState = FixedRateIrm.IRState({borrowRate: INITIAL_BORROW_RATE, lastUpdate: 0});
        irState.lastUpdate = uint48(block.timestamp);

        vm.prank(address(fixedRateIrm.market()));
        vm.expectEmit(true, true, true, true, address(fixedRateIrm));
        emit FixedRateIrm.IRStateUpdated(irState);
        (uint256 interest, uint256 borrowRate) = fixedRateIrm.updateInterestRate(0, 1000 ether);

        assertEq(interest, _getAccruedInterest(1000 ether, INITIAL_BORROW_RATE, 1 days));
        assertEq(borrowRate, INITIAL_BORROW_RATE);
        assertEq(fixedRateIrm.lastUpdate(), block.timestamp);
    }

    function testUnsetMarketInterestRateRevert() external {
        FixedRateIrmMock irmMock = new FixedRateIrmMock(INITIAL_BORROW_RATE, address(this));

        vm.prank(address(fixedRateIrm.market()));
        vm.expectRevert(IIrm.IrmUnauthorized.selector);
        irmMock.updateInterestRate(0, 0);
    }

    function testNonMarketInterestRateRevert() external {
        vm.expectRevert(IIrm.IrmUnauthorized.selector);
        fixedRateIrm.updateInterestRate(0, 0);
    }
}
