// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MarketType, MarketCommon} from "../../MarketCommon.t.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IMarketErrors, IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";
import {AltoBorrowMarket} from "@alto/lending/AltoBorrowMarket.sol";
import {IAltoLiquidationEngine} from "@alto/lending/interfaces/IAltoLiquidationEngine.sol";

contract SetFeeRecipientTestBorrow is MarketCommon {
    AltoBorrowMarket public borrowMarket;

    constructor() MarketCommon(MarketType.BORROW) {}

    function setUp() public override {
        super.setUp();
        borrowMarket = AltoBorrowMarket(address(market));
    }

    function test_RevertWhen_CallerIsNotOwner() external {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        borrowMarket.setFeeRecipient(address(0));
    }

    modifier whenCallerIsOwner() {
        vm.startPrank(OWNER);
        _;
        vm.stopPrank();
    }

    function test_WhenCallerIsOwner() external whenCallerIsOwner {
        address oldFeeRecipient = borrowMarket.feeRecipient();
        address newFeeRecipient = address(USER);

        // it should emit SetFeeRecipient event
        vm.expectEmit();
        emit IMarketEvents.SetFeeRecipient(oldFeeRecipient, newFeeRecipient);

        borrowMarket.setFeeRecipient(newFeeRecipient);

        // it should update feeRecipient
        assertEq(borrowMarket.feeRecipient(), newFeeRecipient);
    }

    function test_RevertWhen_FeeRecipientIsZeroAddressAndBorrowOpeningFeeIsGreaterThanZero()
        external
        whenCallerIsOwner
    {
        borrowMarket.setBorrowOpeningFee(1);

        vm.expectRevert(abi.encodeWithSelector(AltoBorrowMarket.AltoBorrowMarketInvalidInput.selector));
        borrowMarket.setFeeRecipient(address(0));
    }

    function test_RevertWhen_FeeRecipientIsZeroAddressAndProtocolFeePercentageIsGreaterThanZero()
        external
        whenCallerIsOwner
    {
        // Ensure borrowOpeningFee and interestFee are zero to isolate protocolFeePercentage check
        borrowMarket.setBorrowOpeningFee(0);
        borrowMarket.setInterestFee(0, true);

        // Assert that protocolFeePercentage is greater than 0
        uint256 protocolFeePercentage = IAltoLiquidationEngine(borrowMarket.liquidationEngine()).protocolFeePercentage();
        assertGt(protocolFeePercentage, 0, "protocolFeePercentage should be greater than 0");

        // it should revert (default protocol fee percentage is 0.075 ether in tests)
        vm.expectRevert(abi.encodeWithSelector(AltoBorrowMarket.AltoBorrowMarketInvalidInput.selector));
        borrowMarket.setFeeRecipient(address(0));
    }

    function test_RevertWhen_FeeRecipientIsZeroAddressAndInterestFeeIsGreaterThanZero() external whenCallerIsOwner {
        borrowMarket.setInterestFee(0.01 ether, true);

        vm.expectRevert(abi.encodeWithSelector(AltoBorrowMarket.AltoBorrowMarketInvalidInput.selector));
        borrowMarket.setFeeRecipient(address(0));
    }
}
