// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {AltoAdapter} from "@alto/utils/AltoAdapter.sol";
import {IMarket, LiquidationConfiguration} from "@alto/lending/interfaces/IMarket.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {MarketInstance} from "./MarketInstance.sol";

import {AdapterCommon} from "./AdapterCommon.t.sol";
import {ERC20Mock} from "@alto-test/helpers/ERC20Mock.sol";

import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";
import {FixedPointMath} from "@alto/lending/libraries/FixedPointMath.sol";

import {AltoLeverage} from "@alto/lending/leverage/AltoLeverage.sol";
import {SwapperSimpleMock} from "@alto/lending/mocks/SwapperSimpleMock.sol";
import {FlashBorrowLeverageData} from "@alto/lending/leverage/AltoLeverage.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "forge-std/Test.sol";

uint256 constant MIN_AMOUNT = 1000;
uint256 constant MAX_AMOUNT = 2 ** 64; // Must be less than or equal to type(uint160).max.
uint256 constant SIGNATURE_DEADLINE = type(uint32).max;

abstract contract AdapterCommonSetup is AdapterCommon {
    using FixedPointMath for uint256;
    using AssetShareConversionMath for uint256;
    //using stdStorage for StdStorage;

    ERC20Mock internal borrowToken;
    ERC20Mock internal collateralToken;

    IMarket internal market;
    SwapperSimpleMock swapper;
    AltoLeverage leverage;

    uint256 internal constant LTV = 0.75 ether;

    function setUp() public virtual override {
        super.setUp();

        borrowToken = new ERC20Mock("borrow", "B");
        vm.label(address(borrowToken), "borrowToken");
        collateralToken = new ERC20Mock("collateral", "C");
        vm.label(address(collateralToken), "collateralToken");

        vm.startPrank(OWNER);
        swapper = new SwapperSimpleMock(address(OWNER));
        leverage = new AltoLeverage(address(swapper), address(OWNER));

        address irm = address(new FixedRateIrm(0.04 ether / uint256(365 days), address(this)));
        market = IMarket(
            address(
                new MarketInstance(
                    address(borrowToken),
                    address(collateralToken),
                    address(irm),
                    address(OWNER),
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
                        priorityLiquidationGracePeriod: 5 minutes,
                        taggerLiquidationGracePeriod: 2 minutes,
                        liquidationWindowTag: 3 days
                    })
                )
            )
        );

        deal(address(borrowToken), address(swapper), type(uint128).max);
        deal(address(collateralToken), address(swapper), type(uint128).max);
        swapper.setWhitelisted(address(leverage), true);
        market.setAuthorizedCallback(address(leverage), true);
        leverage.setMarket(address(market), true);

        vm.stopPrank();

        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);

        vm.startPrank(SUPPLIER);
        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);
        market.setAuthorization(address(this), true);

        vm.stopPrank();

        vm.prank(USER);
        // So tests can borrow/withdraw on behalf of USER without pranking it.
        market.setAuthorization(address(this), true);
    }

    function _marketPrepareLeverageData(
        uint256 minAmountOut,
        address receiver,
        bytes memory swapData,
        bool isBuyCollateral
    ) internal view returns (bytes memory) {
        // Prepare FlashBorrowLeverageData
        FlashBorrowLeverageData memory leverageData =
            FlashBorrowLeverageData({onBehalf: receiver, minAmountOut: minAmountOut, swapData: hex""});
        return abi.encode(leverageData);
    }
}
