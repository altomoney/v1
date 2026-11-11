// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {MarketType, MarketCommon} from "../../MarketCommon.t.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IMarketErrors, IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";
import {
    IDcfDlbPriorityLiquidationEngine,
    LiquidationConfiguration
} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";
import {AltoBorrowMarket} from "@alto/lending/AltoBorrowMarket.sol";
import {IAltoBorrowMarketErrors, IAltoBorrowMarketEvents} from "@alto/lending/interfaces/IAltoBorrowMarket.sol";
import {DlbDcfPriorityLiquidationEngine} from "@alto/lending/liquidation/DlbDcfPriorityLiquidationEngine.sol";

contract SetBorrowOpeningFeeTestBorrow is MarketCommon {
    AltoBorrowMarket public borrowMarket;

    constructor() MarketCommon(MarketType.BORROW) {}

    function setUp() public override {
        super.setUp();
        borrowMarket = AltoBorrowMarket(address(market));
    }

    function test_RevertWhen_CallerIsNotOwner() external {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        borrowMarket.setBorrowOpeningFee(0.1 ether);
    }

    modifier whenCallerIsOwner() {
        vm.startPrank(OWNER);
        _;
        vm.stopPrank();
    }

    function test_WhenCallerIsOwner() external whenCallerIsOwner {
        uint256 oldBorrowOpeningFee = borrowMarket.borrowOpeningFee();
        uint256 newBorrowOpeningFee = oldBorrowOpeningFee + 1;

        // it should emit SetBorrowOpeningFee event
        vm.expectEmit();
        emit IAltoBorrowMarketEvents.SetBorrowOpeningFee(oldBorrowOpeningFee, newBorrowOpeningFee);

        borrowMarket.setBorrowOpeningFee(newBorrowOpeningFee);

        // it should update borrowOpeningFee
        assertEq(borrowMarket.borrowOpeningFee(), newBorrowOpeningFee);
    }

    function test_RevertWhen_BorrowOpeningFeeIsGreaterThanMATH_PRECISION() external whenCallerIsOwner {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IAltoBorrowMarketErrors.AltoBorrowMarketInvalidInput.selector));
        borrowMarket.setBorrowOpeningFee(MATH_PRECISION + 1);
    }

    function test_RevertWhen_FeeRecipientIsNotSetAndBorrowOpeningFeeIsGreaterThan0() external whenCallerIsOwner {
        LiquidationConfiguration memory liquidationConfiguration =
            IDcfDlbPriorityLiquidationEngine(borrowMarket.liquidationEngine()).liquidationConfiguration();
        liquidationConfiguration.protocolFeePercentage = 0;
        IDcfDlbPriorityLiquidationEngine(borrowMarket.liquidationEngine())
            .setLiquidationConfiguration(liquidationConfiguration);
        borrowMarket.setBorrowOpeningFee(0);
        borrowMarket.setIrm(address(0), false);
        borrowMarket.setFeeRecipient(address(0));

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IAltoBorrowMarketErrors.AltoBorrowMarketInvalidInput.selector));
        borrowMarket.setBorrowOpeningFee(0.1 ether);
    }
}
