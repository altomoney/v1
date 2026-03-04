// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {VaultRegistry} from "@alto/utils/VaultRegistry.sol";
import {IVaultRegistry} from "@alto/utils/interfaces/IVaultRegistry.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract VaultRegistry_RemoveVault_Test is Test {
    address internal immutable OWNER = makeAddr("Owner");
    address internal immutable NON_OWNER = makeAddr("NonOwner");

    VaultRegistry internal vaultRegistry;

    event VaultRemoved(address indexed vault);

    function setUp() public {
        vaultRegistry = new VaultRegistry(OWNER);
        address vault = makeAddr("RegisteredVault");
        vm.prank(OWNER);
        vaultRegistry.addVault(vault);
    }

    function test_RevertWhen_CallerIsNotOwner() public {
        address vault = vaultRegistry.getVaultAtIndex(0);
        vm.prank(NON_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NON_OWNER));
        vaultRegistry.removeVault(vault);
    }

    function test_RevertWhen_VaultIsZero() public {
        vm.prank(OWNER);
        vm.expectRevert(IVaultRegistry.VaultRegistryZeroAddress.selector);
        vaultRegistry.removeVault(address(0));
    }

    function test_RevertWhen_VaultNotRegistered() public {
        vm.prank(OWNER);
        vm.expectRevert(IVaultRegistry.VaultRegistryVaultDoesNotExist.selector);
        vaultRegistry.removeVault(makeAddr("NotRegistered"));
    }

    function test_RemoveVault_WhenVaultIsNotRegistered() public {
        address vault = vaultRegistry.getVaultAtIndex(0);
        assertTrue(vaultRegistry.isVault(vault));

        vm.prank(OWNER);
        vm.expectEmit(true, false, false, true);
        emit VaultRemoved(vault);
        vaultRegistry.removeVault(vault);

        assertFalse(vaultRegistry.isVault(vault));
        assertEq(vaultRegistry.getVaultListLength(), 0);
    }
}
