// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {TOBTestBase} from "../TOBTestBase.t.sol";

contract TapiocaOptionBrokerCollectPaymentTokensTest is TOBTestBase {
    function setUp() public override {
        super.setUp();
    }

    function test_revertWhen_callerIsNotOwner() public {
        address notOwner = makeAddr("notOwner");
        address[] memory tokens = new address[](1);
        tokens[0] = address(paymentToken);

        vm.startPrank(notOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        tob.collectPaymentTokens(tokens);
        vm.stopPrank();
    }

    function test_revertWhen_paymentTokenBeneficiaryIsZeroAddress() public {
        // Set payment token beneficiary to zero address
        vm.startPrank(owner);
        tob.setPaymentTokenBeneficiary(address(0));

        address[] memory tokens = new address[](1);
        tokens[0] = address(paymentToken);

        // Set payment token first
        tob.setPaymentToken(address(paymentToken), paymentTokenOracle, "");

        vm.expectRevert(abi.encodeWithSignature("PaymentTokenNotSupported()"));
        tob.collectPaymentTokens(tokens);
        vm.stopPrank();
    }

    function test_collectPaymentTokens_validConditions() public {
        // Setup payment token balance
        uint256 amount = 1000e18;
        deal(address(paymentToken), address(tob), amount);

        // Store initial balances
        uint256 initialBeneficiaryBalance = paymentToken.balanceOf(dao);
        uint256 initialTOBBalance = paymentToken.balanceOf(address(tob));

        address[] memory tokens = new address[](1);
        tokens[0] = address(paymentToken);

        // Set payment token first
        vm.startPrank(owner);
        tob.setPaymentToken(address(paymentToken), paymentTokenOracle, "");

        // Collect payment tokens
        tob.collectPaymentTokens(tokens);
        vm.stopPrank();

        // Verify balances
        assertEq(paymentToken.balanceOf(dao), initialBeneficiaryBalance + amount, "Beneficiary balance should increase");
        assertEq(paymentToken.balanceOf(address(tob)), 0, "TOB balance should be 0");
    }
}
