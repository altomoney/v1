// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MarketType, MarketCommon} from "../../MarketCommon.t.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IMarketErrors, IMarketEvents, LiquidationConfiguration} from "@alto/lending/interfaces/IMarket.sol";
import {MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";
import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";

contract SetBorrowOpeningFeeTestMint is MarketCommon {
    AltoMintMarket public mintMarket;

    constructor() MarketCommon(MarketType.MINT) {}

    function setUp() public override {
        super.setUp();
        mintMarket = AltoMintMarket(address(market));
    }

    function test_RevertWhen_CallerIsNotOwner() external {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        mintMarket.setBorrowOpeningFee(0.1 ether);
    }

    modifier whenCallerIsOwner() {
        vm.startPrank(OWNER);
        _;
        vm.stopPrank();
    }

    function test_WhenCallerIsOwner() external whenCallerIsOwner {
        uint256 oldBorrowOpeningFee = mintMarket.borrowOpeningFee();
        uint256 newBorrowOpeningFee = oldBorrowOpeningFee + 1;

        // it should emit SetBorrowOpeningFee event
        vm.expectEmit();
        emit AltoMintMarket.SetBorrowOpeningFee(oldBorrowOpeningFee, newBorrowOpeningFee);

        mintMarket.setBorrowOpeningFee(newBorrowOpeningFee);

        // it should update borrowOpeningFee
        assertEq(mintMarket.borrowOpeningFee(), newBorrowOpeningFee);
    }

    function test_RevertWhen_BorrowOpeningFeeIsGreaterThanMATH_PRECISION() external whenCallerIsOwner {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(AltoMintMarket.AltoMintMarketInvalidInput.selector));
        mintMarket.setBorrowOpeningFee(MATH_PRECISION + 1);
    }

    function test_RevertWhen_FeeRecipientIsNotSetAndBorrowOpeningFeeIsGreaterThan0() external whenCallerIsOwner {
        LiquidationConfiguration memory liquidationConfiguration = market.liquidationConfiguration();
        liquidationConfiguration.protocolFeePercentage = 0;
        mintMarket.setLiquidationConfiguration(liquidationConfiguration);
        mintMarket.setBorrowOpeningFee(0);
        mintMarket.setIrm(address(0), false);
        mintMarket.setFeeRecipient(address(0));

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(AltoMintMarket.AltoMintMarketInvalidInput.selector));
        mintMarket.setBorrowOpeningFee(0.1 ether);
    }
}
