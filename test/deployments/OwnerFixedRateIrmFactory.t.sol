// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {OwnerFixedRateIrmFactory} from "@alto/deployments/ethereum-mainnet/OwnerFixedRateIrmFactory.sol";

contract OwnerFixedRateIrmFactoryTest is Test {
    address internal owner = makeAddr("owner");
    address internal market = makeAddr("market");

    OwnerFixedRateIrmFactory internal factory;

    function setUp() public {
        factory = new OwnerFixedRateIrmFactory(owner);
    }

    function test_predictIrmAddressReturnsExactExistingDeployment() public {
        uint256 borrowRate = 1e9;

        vm.prank(owner);
        address irm = factory.deploy(market, 1, borrowRate);

        assertEq(factory.predictIrmAddress(market, 1, borrowRate), irm);
    }

    function test_predictIrmAddressRejectsDifferentRateForExistingVersion() public {
        uint256 borrowRate = 1e9;

        vm.prank(owner);
        factory.deploy(market, 1, borrowRate);

        vm.expectRevert(bytes("Version already used"));
        factory.predictIrmAddress(market, 1, borrowRate + 1);
    }

    function test_predictIrmAddressRejectsDifferentFactoryOwnerForExistingVersion() public {
        uint256 borrowRate = 1e9;

        vm.prank(owner);
        factory.deploy(market, 1, borrowRate);

        vm.prank(owner);
        factory.transferOwnershipSkip2Step(makeAddr("newOwner"));

        vm.expectRevert(bytes("Version already used"));
        factory.predictIrmAddress(market, 1, borrowRate);
    }
}
