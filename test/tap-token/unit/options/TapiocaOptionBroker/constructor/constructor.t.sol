// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

contract TapiocaOptionBroker_constructortree is Test {
    function test_RevertWhen_TapOFTIsZeroAddress() external {
        // it should revert
        vm.skip(true);
    }

    function test_RevertWhen_PaymentTokenBeneficiaryIsZeroAddress() external {
        // it should revert
        vm.skip(true);
    }

    function test_RevertWhen_EpochDurationIsZero() external {
        // it should revert
        vm.skip(true);
    }

    function test_RevertWhen_PearlmitIsZeroAddress() external {
        // it should revert
        vm.skip(true);
    }

    function test_RevertWhen_YieldboxIsZeroAddress() external {
        // it should revert
        vm.skip(true);
    }

    function test_RevertWhen_AdminIsZeroAddress() external {
        // it should revert
        vm.skip(true);
    }

    function test_WhenAllParametersAreValid() external {
        // it should set TAP_TOKEN
        // it should set YIELD_BOX
        // it should set _paymentTokenBeneficiary
        // it should initialize PearlmitHandler
        // it should initialize TWLBase
        // it should transfer ownership to admin
        vm.skip(true);
    }
}
