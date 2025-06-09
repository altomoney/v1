// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "../../../helpers/ERC20Mock.sol";
import {AltoBorrowMarket, LiquidationConfiguration} from "@alto/lending/AltoBorrowMarket.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OracleMock} from "@alto/oracles/mocks/OracleMock.sol";
import {ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {IPausable} from "@alto/utils/Pausable.sol";
import {IMarketErrors} from "@alto/lending/interfaces/IMarket.sol";
import {PAUSED_MARKET, FROZEN_MARKET} from "@alto/utils/Constants.sol";

contract AddCollateralTest is Test {
    AltoBorrowMarket market;
    ERC20Mock borrowToken;
    ERC20Mock collateralToken;
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address owner = address(this);
    uint256 constant INITIAL_AMOUNT = 10000 ether;

    function setUp() public {
        // Deploy mock contracts
        borrowToken = new ERC20Mock("Borrow Token", "BTKN");
        collateralToken = new ERC20Mock("Collateral Token", "CTKN");

        address irm = address(new FixedRateIrm(0.04 ether / uint256(365 days), owner));
        address oracle = address(new OracleMock());
        OracleMock(oracle).setPrice(ORACLE_PRICE_PRECISION);

        market = new AltoBorrowMarket(
            address(borrowToken),
            address(collateralToken),
            address(irm),
            owner,
            address(oracle),
            0.75 ether,
            0,
            owner,
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
        );

        // Set owner as pauser for both pause types
        market.setPauser(owner, PAUSED_MARKET, true);
        market.setPauser(owner, FROZEN_MARKET, true);

        // Setup initial balances for test accounts
        deal(address(collateralToken), alice, INITIAL_AMOUNT);
        deal(address(collateralToken), bob, INITIAL_AMOUNT);

        // Approve market to spend tokens
        vm.startPrank(alice);
        collateralToken.approve(address(market), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        collateralToken.approve(address(market), type(uint256).max);
        vm.stopPrank();
    }

    function test_RevertWhen_MarketIsPaused() public {
        vm.startPrank(owner);
        market.pause(PAUSED_MARKET, true);
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSED_MARKET));
        market.addCollateral(100 ether, alice);
        vm.stopPrank();
    }

    function test_RevertWhen_MarketIsFrozen() public {
        vm.startPrank(owner);
        market.pause(FROZEN_MARKET, true);
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, FROZEN_MARKET));
        market.addCollateral(100 ether, alice);
        vm.stopPrank();
    }

    function test_RevertWhen_OnBehalfIsZeroAddress() public {
        vm.startPrank(alice);
        vm.expectRevert(IMarketErrors.AltoBorrowMarketInvalidInput.selector);
        market.addCollateral(100 ether, address(0));
        vm.stopPrank();
    }

    function test_RevertWhen_AmountIsZero() public {
        vm.startPrank(alice);
        vm.expectRevert(IMarketErrors.AltoBorrowMarketInvalidInput.selector);
        market.addCollateral(0, alice);
        vm.stopPrank();
    }

    function test_RevertWhen_UserHasInsufficientBalance() public {
        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSignature(
                "ERC20InsufficientBalance(address,uint256,uint256)", alice, INITIAL_AMOUNT, INITIAL_AMOUNT + 1
            )
        );
        market.addCollateral(INITIAL_AMOUNT + 1, alice);
        vm.stopPrank();
    }

    function test_AddCollateral() public {
        uint256 collateralAmount = 100 ether;

        vm.startPrank(alice);

        // Initial state check
        assertEq(collateralToken.balanceOf(alice), INITIAL_AMOUNT);
        assertEq(collateralToken.balanceOf(address(market)), 0);

        // Add collateral
        market.addCollateral(collateralAmount, alice);

        // Verify assets were transferred
        assertEq(collateralToken.balanceOf(alice), INITIAL_AMOUNT - collateralAmount);
        assertEq(collateralToken.balanceOf(address(market)), collateralAmount);

        // Verify position was updated correctly
        (uint128 supplyShares, uint128 borrowShares, uint128 collateralAssets) = market.position(alice);
        assertEq(supplyShares, uint128(0));
        assertEq(borrowShares, uint128(0));
        assertEq(collateralAssets, uint128(collateralAmount));

        vm.stopPrank();
    }
}
