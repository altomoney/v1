// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {TOBTestBase} from "../TOBTestBase.t.sol";

contract TapiocaOptionBrokerSetClusterTest is TOBTestBase {
    function setUp() public override {
        super.setUp();
    }

    function test_revertWhen_callerIsNotOwner() public {
        address notOwner = makeAddr("notOwner");
        vm.startPrank(notOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        tob.setCluster(address(cluster));
        vm.stopPrank();
    }

    function test_revertWhen_clusterAddressIsZero() public {
        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSignature("NotValid()"));
        tob.setCluster(address(0));
        vm.stopPrank();
    }

    function test_setCluster_validConditions() public {
        address newCluster = makeAddr("newCluster");

        // Set cluster
        vm.startPrank(owner);
        tob.setCluster(newCluster);
        vm.stopPrank();

        // Verify cluster updated
        assertEq(address(tob._cluster()), newCluster, "Cluster should be updated");
    }
}
