// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {MarketType, MarketCommon} from "../../MarketCommon.t.sol";
import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract AltoMintMarketSetDusdOracle is MarketCommon {
    constructor() MarketCommon(MarketType.MINT) {}

    AltoMintMarket internal mintMarket;
    address internal constant NEW_DUSD_ORACLE = address(0x1234);

    modifier whenCallerIsNotOwner() {
        vm.startPrank(USER);
        _;
        vm.stopPrank();
    }

    modifier whenCallerIsOwner() {
        vm.startPrank(OWNER);
        _;
        vm.stopPrank();
    }

    modifier whenDusdOracleIsZeroAddress() {
        _;
    }

    modifier whenDusdOracleIsValidAddress() {
        _;
    }

    function setUp() public override {
        super.setUp();
        mintMarket = AltoMintMarket(address(market));
    }

    function test_RevertWhen_CallerIsNotOwner() external whenCallerIsNotOwner {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER));
        mintMarket.setDusdOracle(NEW_DUSD_ORACLE);
    }

    function test_RevertWhen_DusdOracleIsZeroAddress() external whenCallerIsOwner whenDusdOracleIsZeroAddress {
        vm.expectRevert(AltoMintMarket.AltoMintMarketInvalidInput.selector);
        mintMarket.setDusdOracle(address(0));
    }

    function test_WhenAllConditionsAreMetForValidUpdate() external whenCallerIsOwner whenDusdOracleIsValidAddress {
        address oldDusdOracle = mintMarket.dusdOracle();

        vm.expectEmit(true, true, true, true);
        emit AltoMintMarket.SetDusdOracle(oldDusdOracle, NEW_DUSD_ORACLE);

        mintMarket.setDusdOracle(NEW_DUSD_ORACLE);

        // it should update dusdOracle state variable to new address
        assertEq(mintMarket.dusdOracle(), NEW_DUSD_ORACLE);
    }
}
