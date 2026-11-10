// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {MarketType, MarketCommon} from "../../MarketCommon.t.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IMarketErrors, IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";
import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";

contract SetFeeRecipientTestMint is MarketCommon {
    AltoMintMarket public mintMarket;

    constructor() MarketCommon(MarketType.MINT) {}

    function setUp() public override {
        super.setUp();
        mintMarket = AltoMintMarket(address(market));
    }

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

    function test_RevertWhen_FeeRecipientIsZeroAddressAndBorrowOpeningFeeIsGreaterThanZeroOrIrmIsSet()
        external
        whenCallerIsOwner
    {
        mintMarket.setBorrowOpeningFee(1);

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(AltoMintMarket.AltoMintMarketInvalidInput.selector));
        mintMarket.setFeeRecipient(address(0));

        mintMarket.setBorrowOpeningFee(0);

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(AltoMintMarket.AltoMintMarketInvalidInput.selector));
        mintMarket.setFeeRecipient(address(0));
    }

    function test_RevertWhen_FeeRecipientIsZeroAddressAndProtocolFeePercentageIsGreaterThanZero()
        external
        whenCallerIsOwner
    {
        mintMarket.setBorrowOpeningFee(0.01 ether);

        // it should revert (default protocol fee percentage is 0.075 ether in tests)
        vm.expectRevert(abi.encodeWithSelector(AltoMintMarket.AltoMintMarketInvalidInput.selector));
        mintMarket.setFeeRecipient(address(0));
    }
}
