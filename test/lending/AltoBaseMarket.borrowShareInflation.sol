// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AltoMarketBorrow} from "./btt/Markets/borrow.t.sol";
import {MarketType} from "./btt/Markets/MarketCommon.t.sol";
import {LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {Balance, IMarketErrors} from "@alto/lending/interfaces/IMarket.sol";

contract BorrowShareInflation is AltoMarketBorrow {
    uint256 internal constant TEST_INITIAL_SUPPLY = 1000 ether;
    uint256 internal constant COLLATERAL = 10 ether;
    uint256 internal constant VIRTUAL_SHARES = 1_000_000;

    constructor() AltoMarketBorrow(MarketType.BORROW) {}

    function setUp() public override {
        super.setUp();

        // Provide liquidity for borrowing
        deal(address(borrowToken), SUPPLIER, TEST_INITIAL_SUPPLY);
        vm.startPrank(SUPPLIER);
        borrowToken.approve(address(market), type(uint256).max);
        market.addSupply(TEST_INITIAL_SUPPLY, 0, SUPPLIER);
        vm.stopPrank();

        // Provide collateral for attacker and victim
        deal(address(collateralToken), USER, COLLATERAL);
        deal(address(collateralToken), USER_2, COLLATERAL);
        vm.startPrank(USER);
        collateralToken.approve(address(market), type(uint256).max);
        market.addCollateral(COLLATERAL, USER);
        vm.stopPrank();

        vm.startPrank(USER_2);
        collateralToken.approve(address(market), type(uint256).max);
        market.addCollateral(COLLATERAL, USER_2);
        vm.stopPrank();

        // Ensure oracle price = 1.0
        vm.prank(OWNER);
        oracle.setPrice(LENDING_ORACLE_PRICE_PRECISION);
    }

    function test_ShareInflationWithZeroAssets_causesBorrowRevert() external {
        // Attempt to inflate totalBorrowed.shares while keeping totalBorrowed.assets at 0
        // This attack is now prevented by the fix: shares-only borrows that compute to zero assets revert
        Balance memory totalBorrowed = market.totalBorrowed();
        assertEq(totalBorrowed.assets, 0, "totalBorrowed.assets should be 0 initially");
        assertEq(totalBorrowed.shares, 0, "totalBorrowed.shares should be 0 initially");

        // Attempt to borrow shares when totalBorrowed.assets is 0
        // This would compute to zero assets, so the fix should prevent it
        uint256 sharesToBorrow = VIRTUAL_SHARES - 1;

        vm.prank(USER);
        // The fix prevents this attack: when assets == 0 after conversion from shares, it reverts
        vm.expectRevert(abi.encodeWithSelector(IMarketErrors.AltoBaseMarketInvalidInput.selector));
        market.borrow(0, sharesToBorrow, USER, USER, "");

        // Verify that the attack was prevented - totalBorrowed should remain unchanged
        Balance memory finalBorrowed = market.totalBorrowed();
        assertEq(finalBorrowed.assets, 0, "totalBorrowed.assets should still be 0");
        assertEq(finalBorrowed.shares, 0, "totalBorrowed.shares should still be 0 - attack prevented");
    }
}
