// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {VaultRegistry} from "@alto/utils/VaultRegistry.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract VaultRegistry_Constructor_Test is Test {
    address internal immutable OWNER = makeAddr("Owner");

    function test_RevertWhen_OwnerIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new VaultRegistry(address(0));
    }

    function test_Constructor_SetsOwnerAndInitialState() public {
        VaultRegistry vaultRegistry = new VaultRegistry(OWNER);
        assertEq(vaultRegistry.owner(), OWNER);
        assertEq(vaultRegistry.getVaultListLength(), 0);

        address[] memory list = vaultRegistry.getVaultList();
        assertEq(list.length, 0);
    }
}
