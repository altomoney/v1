// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MarketCommon, MarketType} from "../MarketCommon.t.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IMarketErrors, IMarketEvents, LiquidationConfiguration} from "@alto/lending/interfaces/IMarket.sol";
import {MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";
import {AltoBorrowMarket} from "@alto/lending/AltoBorrowMarket.sol";
import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";

contract AltoMarketSetBorrowOpeningFee is MarketCommon {
    constructor(MarketType _marketType) MarketCommon(_marketType) {}

    function test_RevertWhen_CallerIsNotOwner() external {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        if (marketType == MarketType.BORROW) {
            AltoBorrowMarket(address(market)).setBorrowOpeningFee(0.1 ether);
        } else {
            AltoMintMarket(address(market)).setBorrowOpeningFee(0.1 ether);
        }
    }

    modifier whenCallerIsOwner() {
        vm.startPrank(OWNER);
        _;
        vm.stopPrank();
    }

    function test_WhenCallerIsOwner() external whenCallerIsOwner {
        uint256 oldBorrowOpeningFee = market.borrowOpeningFee();
        uint256 newBorrowOpeningFee = oldBorrowOpeningFee + 1;

        // it should emit SetBorrowOpeningFee event
        vm.expectEmit();
        if (marketType == MarketType.BORROW) {
            emit AltoBorrowMarket.SetBorrowOpeningFee(oldBorrowOpeningFee, newBorrowOpeningFee);
            AltoBorrowMarket(address(market)).setBorrowOpeningFee(newBorrowOpeningFee);
        } else {
            emit AltoMintMarket.SetBorrowOpeningFee(oldBorrowOpeningFee, newBorrowOpeningFee);
            AltoMintMarket(address(market)).setBorrowOpeningFee(newBorrowOpeningFee);
        }

        // it should update borrowOpeningFee
        assertEq(market.borrowOpeningFee(), newBorrowOpeningFee);
    }

    function test_RevertWhen_BorrowOpeningFeeIsGreaterThanMATH_PRECISION() external whenCallerIsOwner {
        // it should revert
        if (marketType == MarketType.BORROW) {
            vm.expectRevert(abi.encodeWithSelector(AltoBorrowMarket.AltoBorrowMarketInvalidInput.selector));
            AltoBorrowMarket(address(market)).setBorrowOpeningFee(MATH_PRECISION + 1);
        } else {
            vm.expectRevert(abi.encodeWithSelector(AltoMintMarket.AltoMintMarketInvalidInput.selector));
            AltoMintMarket(address(market)).setBorrowOpeningFee(MATH_PRECISION + 1);
        }
    }

    function test_RevertWhen_FeeRecipientIsNotSetAndBorrowOpeningFeeIsGreaterThan0() external whenCallerIsOwner {
        LiquidationConfiguration memory liquidationConfiguration = market.liquidationConfiguration();
        liquidationConfiguration.protocolFeePercentage = 0;
        market.setLiquidationConfiguration(liquidationConfiguration);
        if (marketType == MarketType.BORROW) {
            AltoBorrowMarket(address(market)).setBorrowOpeningFee(0);
        } else {
            AltoMintMarket(address(market)).setBorrowOpeningFee(0);
        }
        market.setIrm(address(0));
        market.setFeeRecipient(address(0));

        // it should revert
        if (marketType == MarketType.BORROW) {
            vm.expectRevert(abi.encodeWithSelector(AltoBorrowMarket.AltoBorrowMarketInvalidInput.selector));
            AltoBorrowMarket(address(market)).setBorrowOpeningFee(0.1 ether);
        } else {
            vm.expectRevert(abi.encodeWithSelector(AltoMintMarket.AltoMintMarketInvalidInput.selector));
            AltoMintMarket(address(market)).setBorrowOpeningFee(0.1 ether);
        }
    }
}
