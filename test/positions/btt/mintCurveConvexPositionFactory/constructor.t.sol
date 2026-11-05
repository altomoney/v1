// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {MintCurveConvexPositionFactory} from "@alto/positions/MintCurveConvexPositionFactory.sol";
import {MintCurveConvexConfig} from "@alto/positions/interfaces/IMintCurveConvexPositionFactory.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract MintCurveConvexPositionFactory_Constructor_Test is Test {
    function test_WhenImplementationIsDeployed_LeavesOwnershipUnsetAndEmitsInitialized() public {
        vm.recordLogs();
        MintCurveConvexPositionFactory implementation = new MintCurveConvexPositionFactory();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(implementation.owner(), address(0));
        assertEq(implementation.pendingOwner(), address(0));
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(implementation));
        assertEq(logs[0].topics.length, 1);
        assertEq(logs[0].topics[0], Initializable.Initialized.selector);
        assertEq(logs[0].data, abi.encode(type(uint64).max));
    }

    function test_GivenDeployedImplementation_WhenDeployerOrAnotherAccountInitializesDirectly_Reverts() public {
        MintCurveConvexPositionFactory implementation = new MintCurveConvexPositionFactory();
        address admin = makeAddr("Admin");
        address registry = makeAddr("MarketRegistry");
        MintCurveConvexConfig memory config = MintCurveConvexConfig({
            curvePool: makeAddr("CurvePool"),
            convexBooster: makeAddr("ConvexBooster"),
            convexRewardPool: makeAddr("ConvexRewardPool"),
            convexPid: 1,
            crv: makeAddr("CRV"),
            cvx: makeAddr("CVX")
        });

        // The constructor lock rejects calls before initialization validates the external configuration.
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initialize(admin, registry, config);

        vm.prank(admin);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initialize(admin, registry, config);
    }
}
