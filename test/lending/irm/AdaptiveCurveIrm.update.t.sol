// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

// needed for deployCode (and Test)
import "forge-std/Test.sol";

import {FixedPointMath} from "@alto/lending/libraries/FixedPointMath.sol";

import {AdaptiveCurveIrm} from "@alto/lending/irm/AdaptiveCurveIrm.sol";
import {ERC20Mock} from "../../helpers/ERC20Mock.sol";
import {OracleMock} from "@alto/oracles/mocks/OracleMock.sol";
import {ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {IMarket, LiquidationConfiguration} from "@alto/lending/interfaces/IMarket.sol";
import {AltoBorrowMarket} from "@alto/lending/AltoBorrowMarket.sol";
import {IrmCommon} from "./IrmCommon.t.sol";

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

contract AltoBorrowMarketMock is AltoBorrowMarket {
    constructor(
        address _borrowToken,
        address _collateralToken,
        address _irm,
        address _owner,
        address _oracle,
        uint256 _maxLtv,
        uint256 _borrowOpeningFee,
        address _feeRecipient,
        LiquidationConfiguration memory _liquidationConfiguration
    )
        AltoBorrowMarket(
            _borrowToken,
            _collateralToken,
            _irm,
            _owner,
            _oracle,
            _maxLtv,
            _borrowOpeningFee,
            _feeRecipient,
            _liquidationConfiguration
        )
    {}

    function modifyTotalBorrowed(uint256 amount) external {
        totalBorrowed.assets += uint128(amount);
    }

    function modifyTotalSupply(uint256 amount) external {
        totalSupply.assets += uint128(amount);
    }
}

contract AdaptiveCurveIrmUpdateTest is IrmCommon {
    using FixedPointMath for uint256;

    function _createMarketWithIrm(address irm) internal returns (AltoBorrowMarketMock) {
        address oracle = address(new OracleMock());
        OracleMock(oracle).setPrice(ORACLE_PRICE_PRECISION);

        AltoBorrowMarketMock market = new AltoBorrowMarketMock(
            address(borrowToken),
            address(collateralToken),
            address(irm),
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
                minPenaltyPercentage: 0.01 ether
            })
        );

        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);

        vm.prank(USER);
        market.setAuthorization(address(this), true);

        return market;
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
        AltoBorrowMarketMock market = _createMarketWithIrm(address(irm));

        targetLtv = bound(targetLtv, 0.001 ether, LTV);
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        market.addSupply(amount, 0, USER);
        market.addCollateral(amount, USER);

        uint256 borrowAmount = amount.multiplyWithPrecision(targetLtv);
        market.borrow(borrowAmount, 0, USER, USER, "");

        (uint256 expectedInterest,) = irm.updateInterestRateViewTimeElapsed(amount, borrowAmount, elapsedTime);

        vm.warp(block.timestamp + elapsedTime);
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
        AltoBorrowMarketMock market = _createMarketWithIrm(address(irm));

        market.addSupply(amount, 0, USER);
        market.addCollateral(amount, USER);
        market.borrow(toBorrowAmount, 0, USER, USER, "");

        vm.warp(block.timestamp + elapsedTime);
        market.accrueInterest();
        uint256 marketBorrowed = IMarket(address(market)).totalBorrowed().assets;
        uint256 marketSupply = IMarket(address(market)).totalSupply().assets;

        MockAdaptiveCurveIrm newIrm = new MockAdaptiveCurveIrm(newIrmConfig, address(this));
        AltoBorrowMarketMock newMarket = _createMarketWithIrm(address(newIrm));

        newMarket.modifyTotalBorrowed(IMarket(address(market)).totalBorrowed().assets);
        newMarket.modifyTotalSupply(IMarket(address(market)).totalSupply().assets);
        newMarket.accrueInterest();

        // get fresh market to the same state as the other one
        assertEq(IMarket(address(newMarket)).totalBorrowed().assets, marketBorrowed);
        assertEq(IMarket(address(newMarket)).totalSupply().assets, marketSupply);

        // change borrow rate either via irm or market
        if (testIrmSwap) {
            irm.setIrmConfig(newIrmConfig);
        } else {
            MockAdaptiveCurveIrm newIrmForMarket = new MockAdaptiveCurveIrm(newIrmConfig, address(this));
            market.setIrm(address(newIrmForMarket));
        }

        assertEq(
            IMockAdaptiveCurveIrm(address(irm)).irState().lastUpdate,
            IMockAdaptiveCurveIrm(address(newIrm)).irState().lastUpdate
        );

        vm.warp(block.timestamp + elapsedTime);
        market.accrueInterest();
        newMarket.accrueInterest();

        assertEq(IMarket(address(market)).totalBorrowed().assets, IMarket(address(newMarket)).totalBorrowed().assets);
    }
}
