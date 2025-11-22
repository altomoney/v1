// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MarketType, MarketCommon} from "../../MarketCommon.t.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IMarketErrors, IMarketEvents, LiquidationConfiguration} from "@alto/lending/interfaces/IMarket.sol";
import {MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";
import {AltoDaoMintMarket} from "@alto/lending/AltoDaoMintMarket.sol";

contract SetBorrowOpeningFeeTestMint is MarketCommon {
    AltoDaoMintMarket public daoMintMarket;

    constructor() MarketCommon(MarketType.DAO_MINT) {}

    function setUp() public override {
        super.setUp();
        daoMintMarket = AltoDaoMintMarket(address(market));
    }

    function test_RevertWhen_CallerIsNotOwner() external {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        daoMintMarket.setBorrowOpeningFee(0.1 ether);
    }

    modifier whenCallerIsOwner() {
        vm.startPrank(OWNER);
        _;
        vm.stopPrank();
    }

    function test_WhenCallerIsOwner() external whenCallerIsOwner {
        uint256 oldBorrowOpeningFee = daoMintMarket.borrowOpeningFee();
        uint256 newBorrowOpeningFee = oldBorrowOpeningFee + 1;

        // it should emit SetBorrowOpeningFee event
        vm.expectEmit();
        emit AltoDaoMintMarket.SetBorrowOpeningFee(oldBorrowOpeningFee, newBorrowOpeningFee);

        daoMintMarket.setBorrowOpeningFee(newBorrowOpeningFee);

        // it should update borrowOpeningFee
        assertEq(daoMintMarket.borrowOpeningFee(), newBorrowOpeningFee);
    }

    function test_RevertWhen_BorrowOpeningFeeIsGreaterThanMATH_PRECISION() external whenCallerIsOwner {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(AltoDaoMintMarket.AltoDaoMintMarketInvalidInput.selector));
        daoMintMarket.setBorrowOpeningFee(MATH_PRECISION + 1);
    }

    function test_RevertWhen_FeeRecipientIsNotSetAndBorrowOpeningFeeIsGreaterThan0() external whenCallerIsOwner {
        LiquidationConfiguration memory liquidationConfiguration = market.liquidationConfiguration();
        liquidationConfiguration.protocolFeePercentage = 0;
        daoMintMarket.setLiquidationConfiguration(liquidationConfiguration);
        daoMintMarket.setBorrowOpeningFee(0);
        daoMintMarket.setIrm(address(0), false);
        daoMintMarket.setFeeRecipient(address(0));

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(AltoDaoMintMarket.AltoDaoMintMarketInvalidInput.selector));
        daoMintMarket.setBorrowOpeningFee(0.1 ether);
    }
}
