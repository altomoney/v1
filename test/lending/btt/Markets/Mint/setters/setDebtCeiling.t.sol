// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {MarketType, MarketCommon} from "../../MarketCommon.t.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";
import {IMarketErrors, IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";

contract SetDebtCeilingTestMint is MarketCommon {
    AltoMintMarket public mintMarket;

    constructor() MarketCommon(MarketType.MINT) {}

    function setUp() public override {
        super.setUp();
        mintMarket = AltoMintMarket(address(market));
    }

    function test_RevertWhen_CallerIsNotOwner() external {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        mintMarket.setDebtCeiling(1);
    }

    modifier whenCallerIsOwner() {
        deal(address(collateralToken), address(this), 1000 ether);
        market.addCollateral(1000 ether, USER);
        market.borrow(500 ether, 0, USER, USER, hex"");
        vm.stopPrank();

        vm.startPrank(OWNER);
        _;
        vm.stopPrank();
    }

    function test_WhenCallerIsOwner() external whenCallerIsOwner {
        // it should update totalSupply assets
        uint256 oldDebtCeiling = market.totalSupply().assets;
        uint256 newDebtCeiling = oldDebtCeiling + 1000 ether;

        // it should emit AccrueInterest event
        vm.expectEmit(false, false, false, false);
        emit IMarketEvents.AccrueInterest(0, 0, 0, 0);

        // it should emit SetDebtCeiling event
        vm.expectEmit();
        emit AltoMintMarket.SetDebtCeiling(oldDebtCeiling, newDebtCeiling);

        mintMarket.setDebtCeiling(newDebtCeiling);

        // it should update totalSupply assets
        assertEq(market.totalSupply().assets, newDebtCeiling);
    }

    function test_RevertWhen_TotalSupplyAssetsIsGreaterThanDebtCeiling() external whenCallerIsOwner {
        uint256 newDebtCeiling = market.totalBorrowed().assets / 2;
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IMarketErrors.AltoBorrowMarketInsufficientMarketLiquidity.selector));
        mintMarket.setDebtCeiling(newDebtCeiling);
    }
}
