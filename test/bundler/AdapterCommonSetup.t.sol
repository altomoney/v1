// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

import {AltoAdapter} from "@alto-monorepo/bundler/AltoAdapter.sol";
import {IMarket, LiquidationConfiguration} from "@alto-monorepo/lending/interfaces/IMarket.sol";
import {FixedRateIrm} from "@alto-monorepo/lending/FixedRateIrm.sol";

import {AdapterCommon} from "./AdapterCommon.t.sol";
import {Erc20Mock} from "../helpers/Erc20Mock.sol";

import {AssetShareConversionMath} from "@alto-monorepo/lending/libraries/AssetShareConversionMath.sol";
import {FixedPointMath} from "@alto-monorepo/lending/libraries/FixedPointMath.sol";

// needed for deployCode (and Test)
import "forge-std/Test.sol";

uint256 constant MIN_AMOUNT = 1000;
uint256 constant MAX_AMOUNT = 2 ** 64; // Must be less than or equal to type(uint160).max.
uint256 constant SIGNATURE_DEADLINE = type(uint32).max;

abstract contract AdapterCommonSetup is AdapterCommon {
    using FixedPointMath for uint256;
    using AssetShareConversionMath for uint256;
    //using stdStorage for StdStorage;

    Erc20Mock internal borrowToken;
    Erc20Mock internal collateralToken;

    IMarket internal market;

    uint256 internal constant LTV = 0.75 ether;

    function setUp() public virtual override {
        super.setUp();

        borrowToken = new Erc20Mock("borrow", "B");
        vm.label(address(borrowToken), "borrowToken");
        collateralToken = new Erc20Mock("collateral", "C");
        vm.label(address(collateralToken), "collateralToken");

        vm.startPrank(OWNER);
        address irm = address(new FixedRateIrm(0.04 ether / uint256(365 days), address(this)));
        market = IMarket(
            deployCode(
                "MarketInstance.sol",
                abi.encode(
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
                )
            )
        );

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
}
