// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AltoBorrowMarket, LiquidationConfiguration} from "@alto/lending/AltoBorrowMarket.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {OracleMock} from "@alto/oracles/mocks/OracleMock.sol";
import {ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {
    AltoLeverage,
    FlashBorrowLeverageData,
    FlashRemoveCollateralLeverageData
} from "@alto/lending/leverage/AltoLeverage.sol";
import {IAltoLeverageSwapper} from "@alto/lending/interfaces/IAltoLeverageSwapper.sol";
import {IMarket, Position, IMarketErrors} from "@alto/lending/interfaces/IMarket.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SwapperSimpleMock} from "@alto/lending/mocks/SwapperSimpleMock.sol";

import {ERC20Mock} from "@alto-test/helpers/ERC20Mock.sol";
import {FixedPointMath} from "@alto/lending/libraries/FixedPointMath.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";

contract AltoLeverageBTTTest is Test {
    using FixedPointMath for uint256;
    using AssetShareConversionMath for uint256;

    IMarket market;
    ERC20Mock borrowToken;
    ERC20Mock collateralToken;
    AltoLeverage leverage;
    SwapperSimpleMock swapper;
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address owner = address(0x1234);
    address notOwner = address(0x5678);
    uint256 constant INITIAL_AMOUNT = 100000000000 ether;
    address oracle;

    function setUp() public {
        borrowToken = new ERC20Mock("Borrow Token", "BTKN");
        collateralToken = new ERC20Mock("Collateral Token", "CTKN");
        swapper = new SwapperSimpleMock(address(this));
        leverage = new AltoLeverage(address(swapper), owner);

        address irm = address(new FixedRateIrm(0.04 ether / uint256(365 days), address(this)));
        oracle = address(new OracleMock());
        OracleMock(oracle).setPrice(1 * ORACLE_PRICE_PRECISION);

        market = IMarket(
            address(
                new AltoBorrowMarket(
                    address(borrowToken),
                    address(collateralToken),
                    address(irm),
                    address(this),
                    address(oracle),
                    0.8 ether,
                    0,
                    address(this),
                    LiquidationConfiguration({
                        maxLiquidationLtv: 0.8 ether,
                        dynamicBonusFeeStart: 0.03 ether,
                        ltvForCompleteLiquidation: 0.9 ether,
                        dynamicBonusFeeDecaySteepness: 5 ether,
                        liquidationBaseFee: 0.05 ether,
                        minPenaltyPercentage: 0.01 ether,
                        isEnabledPriorityLiquidation: true,
                        disablePriorityLiquidationAbovePositionLtv: 0.95 ether,
                        priorityLiquidationGracePeriod: 5 minutes,
                        taggerLiquidationGracePeriod: 2 minutes,
                        liquidationWindowTag: 3 days
                    })
                )
            )
        );

        swapper.setWhitelisted(address(leverage), true);
        // Setup initial balances for test accounts
        deal(address(borrowToken), alice, INITIAL_AMOUNT);
        deal(address(collateralToken), alice, INITIAL_AMOUNT);
        deal(address(borrowToken), address(swapper), type(uint128).max);
        deal(address(collateralToken), address(swapper), type(uint128).max);
        deal(address(borrowToken), address(leverage), 1000 ether);
        deal(address(collateralToken), address(leverage), 1000 ether);

        vm.startPrank(alice);
        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);
        vm.stopPrank();

        market.setAuthorizedCallback(address(leverage), true);

        // Setup market with owner permissions
        vm.prank(owner);
        leverage.setMarket(address(market), true);
    }

    modifier givenCallerIsOwner() {
        vm.startPrank(owner);
        _;
        vm.stopPrank();
    }

    modifier givenCallerIsNotOwner() {
        vm.startPrank(notOwner);
        _;
        vm.stopPrank();
    }

    modifier givenMarketIsSupported() {
        vm.prank(owner);
        leverage.setMarket(address(market), true);
        _;
    }

    modifier givenMarketIsNotSupported() {
        vm.prank(owner);
        leverage.setMarket(address(market), false);
        _;
    }

    modifier givenUserHasCollateralAndDebt() {
        vm.startPrank(alice);
        market.addSupply(10000000000 ether, 0, alice);
        market.addCollateral(1000 ether, alice);
        market.borrow(500 ether, 0, alice, alice, "");
        vm.stopPrank();
        _;
    }
}
