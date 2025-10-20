// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {AdapterContractApprovalInstance} from "../AdapterContractApprovalInstance.sol";

contract AdapterContractApproval_ApproveContract_Test is Test {
    address internal immutable OWNER = makeAddr("Owner");
    address internal immutable NON_OWNER = makeAddr("NonOwner");

    AdapterContractApprovalInstance internal inst;

    event AdapterContractApproved(address indexed contractAddress);

    function setUp() public {
        inst = new AdapterContractApprovalInstance(OWNER);
    }

    function test_RevertWhen_CallerIsNotOwner() public {
        vm.prank(NON_OWNER);
        vm.expectRevert();
        inst.approveContract(makeAddr("X"));
    }

    function test_RevertWhen_ContractAddressZero() public {
        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSignature("AdapterContractApprovalInvalidInput()"));
        inst.approveContract(address(0));
    }

    function test_RevertWhen_ContractAlreadyApproved() public {
        address target = makeAddr("Target");
        vm.prank(OWNER);
        inst.approveContract(target);

        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSignature("AdapterContractApprovalInvalidInput()"));
        inst.approveContract(target);
    }

    function test_Approve_SetsStateAndEmitsEvent() public {
        address target = makeAddr("Target");
        vm.prank(OWNER);
        vm.expectEmit(true, false, false, true);
        emit AdapterContractApproved(target);
        inst.approveContract(target);

        assertTrue(inst.isApprovedContract(target));
    }
}
