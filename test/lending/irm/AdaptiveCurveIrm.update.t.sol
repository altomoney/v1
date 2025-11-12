// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {FixedPointMath} from "@alto/utils/FixedPointMath.sol";

import {AdaptiveCurveIrm} from "@alto/lending/irm/AdaptiveCurveIrm.sol";
import {OracleMock} from "@alto/oracles/mocks/OracleMock.sol";
import {LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {IMarket, LiquidationConfiguration} from "@alto/lending/interfaces/IMarket.sol";
import {IrmCommon} from "./IrmCommon.t.sol";
import {MockMarketDeployer, MockMarket} from "@alto-test/helpers/MockMarket.sol";

contract MockAdaptiveCurveIrm is AdaptiveCurveIrm {
    constructor(AdaptiveCurveIrm.AdaptiveCurveIrmConfig memory _irmConfig, address _owner)
        AdaptiveCurveIrm(_irmConfig, _owner)
    {}

    uint256 internal currentTimeElapsed;

    function _getCurrentTimeElapsed() internal view override returns (uint256) {
        return currentTimeElapsed == 0 ? block.timestamp - irState.lastUpdate : currentTimeElapsed;
    }

    function updateInterestRateViewTimeElapsed(
        uint256 _totalSupply,
        uint256 _totalBorrowed,
        uint256 _currentTimeElapsed
    ) external returns (uint256, uint256) {
        uint256 oldTimeElapsed = currentTimeElapsed;
        currentTimeElapsed = _currentTimeElapsed;
        (uint256 interest, uint256 newBorrowRate) = this.updateInterestRateView(_totalSupply, _totalBorrowed);
        currentTimeElapsed = oldTimeElapsed;
        return (interest, newBorrowRate);
    }
}

interface IMockAdaptiveCurveIrm {
    function irState() external view returns (AdaptiveCurveIrm.IRState memory);
}

contract AdaptiveCurveIrmUpdateTest is IrmCommon {
    using FixedPointMath for uint256;

    MockMarket market;
    MockMarket newMarket;

    function setUp() public override {
        super.setUp();

        address oracle = address(new OracleMock());
        OracleMock(oracle).setPrice(LENDING_ORACLE_PRICE_PRECISION);

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
    }

    function testAccrueInterest(
        AdaptiveCurveIrm.AdaptiveCurveIrmConfig memory irmConfig,
        uint256 targetLtv,
        uint256 amount,
        uint256 elapsedTime
    ) public {
        elapsedTime = bound(elapsedTime, 0 seconds, 365 days);
        _fuzzAdaptiveCurveConfig(irmConfig);

        MockAdaptiveCurveIrm irm = new MockAdaptiveCurveIrm(irmConfig, address(this));
        market.setIrm(address(irm), false);

        targetLtv = bound(targetLtv, 0.001 ether, LTV);
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        market.addSupply(amount, 0, USER);
        market.addCollateral(amount, USER);

        uint256 borrowAmount = amount.multiplyWithPrecision(targetLtv);
        market.borrow(borrowAmount, 0, USER, USER, "");

        (uint256 expectedInterest,) = irm.updateInterestRateViewTimeElapsed(amount, borrowAmount, elapsedTime);

        vm.warp(block.timestamp + elapsedTime);
        AdaptiveCurveIrm.IRState memory irState =
            AdaptiveCurveIrm.IRState({rateAtTarget: 0, lastUpdate: uint48(block.timestamp)});
        vm.expectEmit(true, true, true, false, address(irm));
        emit AdaptiveCurveIrm.IRStateUpdated(irState);
        market.accrueInterest();

        assertEq(IMarket(address(market)).totalBorrowed().assets, borrowAmount + expectedInterest);
    }

    /// @notice Test the update of the interest rate both from market and IRM side
    /// @dev This is supposed to test the update of the interest rate configuration.
    ///      This is done by comparing the market with changed IRM config and market
    ///      with same IRM config from start.
    function testUpdateInterestRate(
        AdaptiveCurveIrm.AdaptiveCurveIrmConfig memory irmConfig,
        AdaptiveCurveIrm.AdaptiveCurveIrmConfig memory newIrmConfig,
        uint256 elapsedTime,
        uint256 targetLtv,
        uint256 amount,
        bool testIrmSwap
    ) public {
        elapsedTime = bound(elapsedTime, 0 seconds, 365 days);
        targetLtv = bound(targetLtv, 0.001 ether, LTV);
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);
        uint256 toBorrowAmount = amount.multiplyWithPrecision(targetLtv);
        deal(address(borrowToken), address(this), type(uint256).max);
        deal(address(collateralToken), address(this), type(uint256).max);

        _fuzzAdaptiveCurveConfig(irmConfig);
        _fuzzAdaptiveCurveConfig(newIrmConfig);

        MockAdaptiveCurveIrm irm = new MockAdaptiveCurveIrm(irmConfig, address(this));
        AdaptiveCurveIrm.IRState memory irState =
            AdaptiveCurveIrm.IRState({rateAtTarget: 0, lastUpdate: uint48(block.timestamp)});
        vm.expectEmit(true, true, true, false, address(irm));
        emit AdaptiveCurveIrm.IRStateUpdated(irState);
        market.setIrm(address(irm), false);

        market.addSupply(amount, 0, USER);
        market.addCollateral(amount, USER);
        market.borrow(toBorrowAmount, 0, USER, USER, "");

        vm.warp(block.timestamp + elapsedTime);
        vm.expectEmit(true, true, true, false, address(irm));
        emit AdaptiveCurveIrm.IRStateUpdated(irState);
        market.accrueInterest();
        uint256 marketBorrowed = IMarket(address(market)).totalBorrowed().assets;
        uint256 marketSupply = IMarket(address(market)).totalSupply().assets;

        MockAdaptiveCurveIrm newIrm = new MockAdaptiveCurveIrm(newIrmConfig, address(this));
        vm.expectEmit(true, true, true, false, address(newIrm));
        emit AdaptiveCurveIrm.IRStateUpdated(irState);
        newMarket.setIrm(address(newIrm), false);

        newMarket.modifyTotalBorrowed(IMarket(address(market)).totalBorrowed().assets);
        newMarket.modifyTotalSupply(IMarket(address(market)).totalSupply().assets);
        vm.expectEmit(true, true, true, false, address(newIrm));
        emit AdaptiveCurveIrm.IRStateUpdated(irState);
        newMarket.accrueInterest();

        // get fresh market to the same state as the other one
        assertEq(IMarket(address(newMarket)).totalBorrowed().assets, marketBorrowed);
        assertEq(IMarket(address(newMarket)).totalSupply().assets, marketSupply);

        // change borrow rate either via irm or market
        if (testIrmSwap) {
            vm.expectEmit(true, true, true, false, address(irm));
            emit AdaptiveCurveIrm.IRStateUpdated(irState);
            irm.setIrmConfig(newIrmConfig);
        } else {
            MockAdaptiveCurveIrm newIrmForMarket = new MockAdaptiveCurveIrm(newIrmConfig, address(this));
            vm.expectEmit(true, true, true, false, address(newIrmForMarket));
            emit AdaptiveCurveIrm.IRStateUpdated(irState);
            market.setIrm(address(newIrmForMarket), false);
        }

        assertEq(
            IMockAdaptiveCurveIrm(address(irm)).irState().lastUpdate,
            IMockAdaptiveCurveIrm(address(newIrm)).irState().lastUpdate
        );

        vm.warp(block.timestamp + elapsedTime);
        vm.expectEmit(true, true, true, false);
        emit AdaptiveCurveIrm.IRStateUpdated(irState);
        market.accrueInterest();
        vm.expectEmit(true, true, true, false);
        emit AdaptiveCurveIrm.IRStateUpdated(irState);
        newMarket.accrueInterest();

        assertEq(IMarket(address(market)).totalBorrowed().assets, IMarket(address(newMarket)).totalBorrowed().assets);
    }
}
