// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {MintCurveConvexPosition} from "@alto/positions/MintCurveConvexPosition.sol";
import {MintCurveConvexConfig} from "@alto/positions/interfaces/IMintCurveConvexPositionFactory.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract MintCurveConvexPosition_Constructor_Test is Test {
    function test_WhenImplementationIsDeployed_LeavesOwnershipUnsetAndEmitsInitialized() public {
        vm.recordLogs();
        MintCurveConvexPosition implementation = new MintCurveConvexPosition();
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
        MintCurveConvexPosition implementation = new MintCurveConvexPosition();
        address owner = makeAddr("Owner");
        address factory = makeAddr("Factory");
        address market = makeAddr("Market");
        MintCurveConvexConfig memory config = MintCurveConvexConfig({
            curvePool: makeAddr("CurvePool"),
            convexBooster: makeAddr("ConvexBooster"),
            convexRewardPool: makeAddr("ConvexRewardPool"),
            convexPid: 1,
            crv: makeAddr("CRV"),
            cvx: makeAddr("CVX")
        });

        // The constructor lock rejects calls before initialization reads the market or pool.
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initialize(owner, factory, market, config);

        vm.prank(owner);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initialize(owner, factory, market, config);
    }
}
