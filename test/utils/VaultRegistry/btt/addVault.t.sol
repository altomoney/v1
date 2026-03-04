// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {VaultRegistry} from "@alto/utils/VaultRegistry.sol";
import {IVaultRegistry} from "@alto/utils/interfaces/IVaultRegistry.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract VaultRegistry_AddVault_Test is Test {
    address internal immutable OWNER = makeAddr("Owner");
    address internal immutable NON_OWNER = makeAddr("NonOwner");

    VaultRegistry internal vaultRegistry;

    event VaultAdded(address indexed vault);

    function setUp() public {
        vaultRegistry = new VaultRegistry(OWNER);
    }

    function test_RevertWhen_CallerIsNotOwner() public {
        vm.prank(NON_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NON_OWNER));
        vaultRegistry.addVault(makeAddr("Vault"));
    }

    function test_RevertWhen_VaultIsZero() public {
        vm.prank(OWNER);
        vm.expectRevert(IVaultRegistry.VaultRegistryZeroAddress.selector);
        vaultRegistry.addVault(address(0));
    }

    function test_RevertWhen_VaultAlreadyRegistered() public {
        address vault = makeAddr("Vault");
        vm.prank(OWNER);
        vaultRegistry.addVault(vault);

        vm.prank(OWNER);
        vm.expectRevert(IVaultRegistry.VaultRegistryVaultAlreadyExists.selector);
        vaultRegistry.addVault(vault);
    }

    function test_AddVault_WhenVaultIsNotRegistered() public {
        address vault = makeAddr("Vault");
        vm.prank(OWNER);
        vm.expectEmit(true, false, false, true);
        emit VaultAdded(vault);
        vaultRegistry.addVault(vault);

        assertTrue(vaultRegistry.isVault(vault));
        assertEq(vaultRegistry.getVaultListLength(), 1);
        assertEq(vaultRegistry.getVaultList()[0], vault);
        assertEq(vaultRegistry.getVaultAtIndex(0), vault);
    }
}
