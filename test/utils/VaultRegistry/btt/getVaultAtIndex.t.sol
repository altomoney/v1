// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {VaultRegistry} from "@alto/utils/VaultRegistry.sol";
import {IVaultRegistry} from "@alto/utils/interfaces/IVaultRegistry.sol";

contract VaultRegistry_GetVaultAtIndex_Test is Test {
    address internal immutable OWNER = makeAddr("Owner");

    VaultRegistry internal vaultRegistry;

    address internal vaultA;
    address internal vaultB;
    address internal vaultC;

    function setUp() public {
        vaultRegistry = new VaultRegistry(OWNER);
        vaultA = makeAddr("VaultA");
        vaultB = makeAddr("VaultB");
        vaultC = makeAddr("VaultC");

        vm.startPrank(OWNER);
        vaultRegistry.addVault(vaultA);
        vaultRegistry.addVault(vaultB);
        vaultRegistry.addVault(vaultC);
        vm.stopPrank();
    }

    function test_RevertWhen_IndexIsEqualToLength() public {
        vm.expectRevert(IVaultRegistry.VaultRegistryInvalidIndex.selector);
        vaultRegistry.getVaultAtIndex(3);
    }

    function test_RevertWhen_IndexIsGreaterThanLength() public {
        vm.expectRevert(IVaultRegistry.VaultRegistryInvalidIndex.selector);
        vaultRegistry.getVaultAtIndex(100);
    }

    function test_RevertWhen_ListIsEmpty() public {
        VaultRegistry emptyRegistry = new VaultRegistry(OWNER);
        vm.expectRevert(IVaultRegistry.VaultRegistryInvalidIndex.selector);
        emptyRegistry.getVaultAtIndex(0);
    }

    function test_GetVaultAtIndex_WhenIndexIsValid() public view {
        assertEq(vaultRegistry.getVaultAtIndex(0), vaultA);
        assertEq(vaultRegistry.getVaultAtIndex(1), vaultB);
        assertEq(vaultRegistry.getVaultAtIndex(2), vaultC);
    }
}
