// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MarketType, MarketCommon} from "../../MarketCommon.t.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IMarketErrors, IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";

contract SetFeeRecipientTestBorrow is MarketCommon {
    constructor() MarketCommon(MarketType.BORROW) {}

    function test_RevertWhen_CallerIsNotOwner() external {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        market.setFeeRecipient(address(0));
    }

    modifier whenCallerIsOwner() {
        vm.startPrank(OWNER);
        _;
        vm.stopPrank();
    }

    function test_WhenCallerIsOwner() external whenCallerIsOwner {
        address oldFeeRecipient = market.feeRecipient();
        address newFeeRecipient = address(USER);

        // it should emit SetFeeRecipient event
        vm.expectEmit();
        emit IMarketEvents.SetFeeRecipient(oldFeeRecipient, newFeeRecipient);

        market.setFeeRecipient(newFeeRecipient);

        // it should update feeRecipient
        assertEq(market.feeRecipient(), newFeeRecipient);
    }

    function test_RevertWhen_FeeRecipientIsZeroAddressAndBorrowOpeningFeeIsGreaterThanZero()
        external
        whenCallerIsOwner
    {
        market.setBorrowOpeningFee(1);

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IMarketErrors.AltoBaseMarketInvalidInput.selector));
        market.setFeeRecipient(address(0));
    }
}
