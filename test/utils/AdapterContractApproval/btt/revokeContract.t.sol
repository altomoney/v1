// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {AdapterContractApprovalInstance} from "../AdapterContractApprovalInstance.sol";

contract AdapterContractApproval_RevokeContract_Test is Test {
    address internal immutable OWNER = makeAddr("Owner");
    address internal immutable NON_OWNER = makeAddr("NonOwner");

    AdapterContractApprovalInstance internal inst;

    event AdapterContractRevoked(address indexed contractAddress);

    function setUp() public {
        inst = new AdapterContractApprovalInstance(OWNER);
        vm.prank(OWNER);
        inst.approveContract(makeAddr("PreApproved"));
    }

    function test_RevertWhen_CallerIsNotOwner() public {
        vm.prank(NON_OWNER);
        vm.expectRevert();
        inst.revokeContract(makeAddr("X"));
    }

    function test_RevertWhen_ContractAddressZero() public {
        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSignature("AdapterContractApprovalInvalidInput()"));
        inst.revokeContract(address(0));
    }

    function test_RevertWhen_ContractNotApproved() public {
        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSignature("AdapterContractApprovalInvalidInput()"));
        inst.revokeContract(makeAddr("NotApproved"));
    }

    function test_Revoke_SetsStateAndEmitsEvent() public {
        address target = makeAddr("PreApproved");
        assertTrue(inst.isApprovedContract(target));

        vm.prank(OWNER);
        vm.expectEmit(true, false, false, true);
        emit AdapterContractRevoked(target);
        inst.revokeContract(target);

        assertFalse(inst.isApprovedContract(target));
    }
}
