// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./TestGhoBase.t.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract TestGsmFixedFeeStrategy is TestGhoBase {
    function testRevertAboveMaximumFee() public {
        vm.expectRevert("INVALID_BUY_FEE");
        FixedFeeStrategy feeStrategy = new FixedFeeStrategy(5000, DEFAULT_GSM_SELL_FEE, address(this));

        vm.expectRevert("INVALID_SELL_FEE");
        feeStrategy = new FixedFeeStrategy(DEFAULT_GSM_BUY_FEE, 5000, address(this));
    }

    function testZeroBuyFee() public {
        FixedFeeStrategy feeStrategy = new FixedFeeStrategy(0, DEFAULT_GSM_SELL_FEE, address(this));
        uint256 fee = feeStrategy.getBuyFee(DEFAULT_GSM_GHO_AMOUNT);
        assertEq(fee, 0, "Unexpected non-zero fee");
        assertEq(feeStrategy.getGrossAmountFromTotalBought(DEFAULT_GSM_GHO_AMOUNT + fee), DEFAULT_GSM_GHO_AMOUNT);
    }

    function testZeroSellFee() public {
        FixedFeeStrategy feeStrategy = new FixedFeeStrategy(DEFAULT_GSM_BUY_FEE, 0, address(this));
        uint256 fee = feeStrategy.getSellFee(DEFAULT_GSM_GHO_AMOUNT);
        assertEq(fee, 0, "Unexpected non-zero fee");
        assertEq(feeStrategy.getGrossAmountFromTotalSold(DEFAULT_GSM_GHO_AMOUNT + fee), DEFAULT_GSM_GHO_AMOUNT);
    }

    function testRevertBothFeesZero() public {
        vm.expectRevert("MUST_HAVE_ONE_NONZERO_FEE");
        new FixedFeeStrategy(0, 0, address(this));
    }

    function testOwnerCanUpdateFee() public {
        FixedFeeStrategy feeStrategy = new FixedFeeStrategy(DEFAULT_GSM_BUY_FEE, DEFAULT_GSM_SELL_FEE, address(this));
        vm.startPrank(address(this));
        feeStrategy.setFee(DEFAULT_GSM_BUY_FEE + 1000, DEFAULT_GSM_SELL_FEE + 1000);
        vm.stopPrank();

        vm.startPrank(address(ALICE));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, ALICE, feeStrategy.CONFIGURATOR_ROLE()
            )
        );
        feeStrategy.setFee(DEFAULT_GSM_BUY_FEE + 2000, DEFAULT_GSM_SELL_FEE + 2000);
    }
}
