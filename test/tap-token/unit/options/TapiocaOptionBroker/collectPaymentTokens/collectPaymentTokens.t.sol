// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

contract TapiocaOptionBroker_collectPaymentTokenstree is Test {
    function test_RevertWhen_CallerIsNotOwner() external {
        // it should revert
        vm.skip(true);
    }

    function test_WhenPaymentTokenBeneficiaryIsZeroAddress() external {
        // it should revert with PaymentTokenNotSupported
        vm.skip(true);
    }

    function test_WhenConditionsAreMet() external {
        // it should get token balance
        // it should transfer balance to beneficiary
        // it should emit PaymentCollection event
        vm.skip(true);
    }
}
