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
import {PAUSED_MARKET} from "@alto/utils/Constants.sol";

contract RemoveSupplyTest is Test {
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

        // Set owner as pauser for PAUSED_MARKET
        market.setPauser(owner, PAUSED_MARKET, true);

        // Setup initial balances for test accounts
        borrowToken.mint(alice, INITIAL_AMOUNT);
        borrowToken.mint(bob, INITIAL_AMOUNT);

        // Approve market to spend tokens
        vm.startPrank(alice);
        borrowToken.approve(address(market), type(uint256).max);
        market.addSupply(100 ether, 0, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        borrowToken.approve(address(market), type(uint256).max);
        market.addSupply(100 ether, 0, bob);
        vm.stopPrank();
    }

    function test_RevertWhen_MarketIsPaused() public {
        vm.startPrank(owner);
        market.pause(PAUSED_MARKET, true);
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSED_MARKET));
        market.removeSupply(50 ether, 0, alice, alice);
        vm.stopPrank();
    }

    function test_RevertWhen_BothAssetsAndSharesProvided() public {
        vm.startPrank(alice);
        vm.expectRevert(IMarketErrors.AltoBorrowMarketInvalidInput.selector);
        market.removeSupply(50 ether, 25 ether, alice, alice);
        vm.stopPrank();
    }

    function test_RevertWhen_ReceiverIsZeroAddress() public {
        vm.startPrank(alice);
        vm.expectRevert(IMarketErrors.AltoBorrowMarketInvalidInput.selector);
        market.removeSupply(50 ether, 0, alice, address(0));
        vm.stopPrank();
    }

    function test_RevertWhen_SenderIsNotAuthorized() public {
        vm.startPrank(bob);
        vm.expectRevert(IMarketErrors.AltoBorrowMarketUnauthorized.selector);
        market.removeSupply(50 ether, 0, alice, alice);
        vm.stopPrank();
    }

    function test_RevertWhen_AssetsIsZero() public {
        vm.startPrank(alice);
        vm.expectRevert(IMarketErrors.AltoBorrowMarketInvalidInput.selector);
        market.removeSupply(0, 0, alice, alice);
        vm.stopPrank();
    }

    function test_RevertWhen_UserHasInsufficientSupply() public {
        vm.startPrank(alice);
        vm.expectRevert();
        market.removeSupply(150 ether, 0, alice, alice);
        vm.stopPrank();
    }

    function test_RemoveSupplyWithAssets() public {
        uint256 removeAmount = 50 ether;

        vm.startPrank(alice);

        // Initial state check
        uint256 initialBalance = borrowToken.balanceOf(alice);
        (uint128 supplyShares, uint128 borrowShares, uint128 collateralAssets) = market.position(alice);
        uint256 initialSupplyShares = supplyShares;

        // Remove supply with assets
        (uint256 removedAssets, uint256 removedShares) = market.removeSupply(removeAmount, 0, alice, alice);

        // Verify assets were transferred back
        assertEq(borrowToken.balanceOf(alice), initialBalance + removedAssets);

        // Verify shares were burned correctly
        (supplyShares, borrowShares, collateralAssets) = market.position(alice);
        assertEq(supplyShares, uint128(initialSupplyShares - removedShares));
        assertEq(borrowShares, uint128(0));
        assertEq(collateralAssets, uint128(0));

        vm.stopPrank();
    }

    function test_RevertWhen_SharesIsZero() public {
        vm.startPrank(alice);
        vm.expectRevert(IMarketErrors.AltoBorrowMarketInvalidInput.selector);
        market.removeSupply(0, 0, alice, alice);
        vm.stopPrank();
    }

    function test_RemoveSupplyWithShares() public {
        uint256 shareAmount = 25 ether;

        vm.startPrank(alice);

        // Initial state check
        uint256 initialBalance = borrowToken.balanceOf(alice);
        (uint128 supplyShares, uint128 borrowShares, uint128 collateralAssets) = market.position(alice);
        uint256 initialSupplyShares = supplyShares;

        // Remove supply with shares
        (uint256 removedAssets, uint256 removedShares) = market.removeSupply(0, shareAmount, alice, alice);

        // Verify assets were transferred back
        assertEq(borrowToken.balanceOf(alice), initialBalance + removedAssets);

        // Verify shares were burned correctly
        (supplyShares, borrowShares, collateralAssets) = market.position(alice);
        assertEq(supplyShares, uint128(initialSupplyShares - removedShares));
        assertEq(borrowShares, uint128(0));
        assertEq(collateralAssets, uint128(0));

        vm.stopPrank();
    }
}
