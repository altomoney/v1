// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./TestDusdBase.t.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IUsmFeeStrategy} from "@alto/usm/interfaces/IUsmFeeStrategy.sol";

contract TestUsmFixedFeeStrategy is TestDusdBase {
    function testRevertAboveMaximumFee() public {
        vm.expectRevert("INVALID_BUY_FEE");
        FixedFeeStrategy feeStrategy = new FixedFeeStrategy(5000, DEFAULT_USM_SELL_FEE, address(this));

        vm.expectRevert("INVALID_SELL_FEE");
        feeStrategy = new FixedFeeStrategy(DEFAULT_USM_BUY_FEE, 5000, address(this));
    }

    function testRevertZeroAdmin() public {
        vm.expectRevert("ZERO_ADDRESS_NOT_VALID");
        new FixedFeeStrategy(DEFAULT_USM_BUY_FEE, DEFAULT_USM_SELL_FEE, address(0));
    }

    function testZeroBuyFee() public {
        FixedFeeStrategy feeStrategy = new FixedFeeStrategy(0, DEFAULT_USM_SELL_FEE, address(this));
        uint256 fee = feeStrategy.getBuyFee(DEFAULT_USM_DUSD_AMOUNT);
        assertEq(fee, 0, "Unexpected non-zero fee");
        assertEq(feeStrategy.getGrossAmountFromTotalBought(DEFAULT_USM_DUSD_AMOUNT + fee), DEFAULT_USM_DUSD_AMOUNT);
    }

    function testZeroSellFee() public {
        FixedFeeStrategy feeStrategy = new FixedFeeStrategy(DEFAULT_USM_BUY_FEE, 0, address(this));
        uint256 fee = feeStrategy.getSellFee(DEFAULT_USM_DUSD_AMOUNT);
        assertEq(fee, 0, "Unexpected non-zero fee");
        assertEq(feeStrategy.getGrossAmountFromTotalSold(DEFAULT_USM_DUSD_AMOUNT + fee), DEFAULT_USM_DUSD_AMOUNT);
    }

    function testRevertBothFeesZero() public {
        vm.expectRevert("MUST_HAVE_ONE_NONZERO_FEE");
        new FixedFeeStrategy(0, 0, address(this));
    }

    function testOwnerCanUpdateFee() public {
        FixedFeeStrategy feeStrategy = new FixedFeeStrategy(DEFAULT_USM_BUY_FEE, DEFAULT_USM_SELL_FEE, address(this));
        vm.startPrank(address(this));
        vm.expectEmit(true, true, true, true, address(feeStrategy));
        emit IUsmFeeStrategy.FeeSet(
            DEFAULT_USM_BUY_FEE, DEFAULT_USM_BUY_FEE + 1000, DEFAULT_USM_SELL_FEE, DEFAULT_USM_SELL_FEE + 1000
        );
        feeStrategy.setFee(DEFAULT_USM_BUY_FEE + 1000, DEFAULT_USM_SELL_FEE + 1000);
        vm.stopPrank();

        vm.startPrank(address(ALICE));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, ALICE, feeStrategy.CONFIGURATOR_ROLE()
            )
        );
        feeStrategy.setFee(DEFAULT_USM_BUY_FEE + 2000, DEFAULT_USM_SELL_FEE + 2000);
    }
}
