// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {MarketType, MarketCommon} from "../../MarketCommon.t.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AltoDaoMintMarket} from "@alto/lending/AltoDaoMintMarket.sol";
import {IMarketErrors, IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {Vm} from "forge-std/Vm.sol";

contract SetDebtCeilingTestMint is MarketCommon {
    AltoDaoMintMarket public daoMintMarket;

    constructor() MarketCommon(MarketType.DAO_MINT) {}

    function setUp() public override {
        super.setUp();
        daoMintMarket = AltoDaoMintMarket(address(market));

        vm.startPrank(OWNER);
        daoMintMarket.setAuthorizedController(address(this), true);
        vm.stopPrank();
    }

    function test_RevertWhen_CallerIsNotOwner() external {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        daoMintMarket.setDebtCeiling(1);
    }

    modifier whenCallerIsOwner() {
        deal(address(collateralToken), address(this), 1000 ether);
        market.addCollateral(1000 ether, USER);
        market.borrow(500 ether, 0, USER, USER, hex"");

        vm.startPrank(OWNER);
        _;
        vm.stopPrank();
    }

    function test_WhenMarketIsNotPaused() external whenCallerIsOwner {
        // it should update totalSupply assets
        uint256 oldDebtCeiling = market.totalSupply().assets;
        uint256 newDebtCeiling = oldDebtCeiling + 1000 ether;

        // it should emit AccrueInterest event
        vm.expectEmit(false, false, false, false);
        emit IMarketEvents.AccrueInterest(0, 0, 0, 0);

        // it should emit SetDebtCeiling event
        vm.expectEmit();
        emit AltoDaoMintMarket.SetDebtCeiling(oldDebtCeiling, newDebtCeiling);

        daoMintMarket.setDebtCeiling(newDebtCeiling);

        // it should update totalSupply assets
        assertEq(market.totalSupply().assets, newDebtCeiling);
    }

    function test_WhenMarketIsPaused() external whenCallerIsOwner {
        market.pause(PAUSE_TYPE, true);

        // it should update totalSupply assets
        uint256 oldDebtCeiling = market.totalSupply().assets;
        uint256 newDebtCeiling = oldDebtCeiling + 1000 ether;

        // it should emit SetDebtCeiling event
        vm.expectEmit();
        emit AltoDaoMintMarket.SetDebtCeiling(oldDebtCeiling, newDebtCeiling);

        vm.recordLogs();
        daoMintMarket.setDebtCeiling(newDebtCeiling);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        // Assert that no AccrueInterest events were emitted
        for (uint256 i = 0; i < logs.length; i++) {
            assertFalse(logs[i].topics[0] == IMarketEvents.AccrueInterest.selector);
        }
        // it should update totalSupply assets
        assertEq(market.totalSupply().assets, newDebtCeiling);
    }

    function test_RevertWhen_TotalSupplyAssetsIsGreaterThanDebtCeiling() external whenCallerIsOwner {
        uint256 newDebtCeiling = market.totalBorrowed().assets / 2;
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IMarketErrors.AltoBaseMarketInsufficientMarketLiquidity.selector));
        daoMintMarket.setDebtCeiling(newDebtCeiling);
    }
}
