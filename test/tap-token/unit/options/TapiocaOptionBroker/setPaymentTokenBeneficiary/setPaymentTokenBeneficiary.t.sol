// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {TOBTestBase} from "../TOBTestBase.t.sol";

contract TapiocaOptionBrokerSetPaymentTokenBeneficiaryTest is TOBTestBase {
    function setUp() public override {
        super.setUp();
    }

    function test_revertWhen_callerIsNotOwner() public {
        address notOwner = makeAddr("notOwner");
        vm.startPrank(notOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        tob.setPaymentTokenBeneficiary(address(1));
        vm.stopPrank();
    }

    function test_setPaymentTokenBeneficiary_validConditions() public {
        address newBeneficiary = makeAddr("newBeneficiary");

        // Set payment token beneficiary
        vm.startPrank(owner);
        tob.setPaymentTokenBeneficiary(newBeneficiary);
        vm.stopPrank();

        // Verify beneficiary updated
        assertEq(tob._paymentTokenBeneficiary(), newBeneficiary, "Beneficiary should be updated");
    }
}
