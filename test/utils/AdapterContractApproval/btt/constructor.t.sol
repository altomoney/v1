// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {AdapterContractApprovalInstance} from "../AdapterContractApprovalInstance.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract AdapterContractApproval_Constructor_Test is Test {
    address internal immutable OWNER = makeAddr("Owner");

    function test_RevertWhen_OwnerIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new AdapterContractApprovalInstance(address(0));
    }

    function test_Constructor_SetsOwnerAndInitialState() public {
        AdapterContractApprovalInstance inst = new AdapterContractApprovalInstance(OWNER);
        assertEq(inst.owner(), OWNER);

        address random = makeAddr("Random");
        // mapping default false
        assertEq(inst.isApprovedContract(random), false);
    }
}
