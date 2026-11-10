// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import {AltoChainlinkERC4626RatioMultiplierOracleCommon} from "./AltoChainlinkERC4626RatioMultiplierOracleCommon.t.sol";
import {
    AltoChainlinkERC4626RatioMultiplierOracle
} from "@alto/oracles/AltoChainlinkERC4626RatioMultiplierOracle/AltoChainlinkERC4626RatioMultiplierOracle.sol";
import {ModuleMultiplier} from "@alto/oracles/modules/ModuleMultiplier.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {
    IAltoChainlinkERC4626RatioMultiplierOracleEvents
} from "@alto/oracles/interfaces/IAltoChainlinkERC4626RatioMultiplierOracle.sol";
import {MultiplierNode} from "@alto/oracles/interfaces/IModuleNode.sol";

contract AltoChainlinkERC4626RatioMultiplierOracleUpdateMultiplierNode is
    AltoChainlinkERC4626RatioMultiplierOracleCommon
{
    AltoChainlinkERC4626RatioMultiplierOracle oracle;

    function setUp() public override {
        super.setUp();
        oracle = _deployOracle();
    }

    modifier givenCallerIsNotOwner() {
        vm.startPrank(NON_OWNER);
        _;
        vm.stopPrank();
    }

    modifier givenCallerIsOwner() {
        _;
    }

    function test_RevertWhen_CallerIsNotOwner() external givenCallerIsNotOwner {
        MultiplierNode memory validNode = _createValidMultiplierNode();

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NON_OWNER));
        oracle.updateMultiplierNode(validNode);
    }

    function test_RevertWhen_NodeMultiplierIsZero() external givenCallerIsOwner {
        MultiplierNode memory invalidNode = _createValidMultiplierNode(0);

        vm.prank(OWNER);
        vm.expectRevert(ModuleMultiplier.ModuleMultiplierInvalidInput.selector);
        oracle.updateMultiplierNode(invalidNode);
    }

    function test_RevertWhen_NodeMultiplierIsGreaterThan1e54() external givenCallerIsOwner {
        MultiplierNode memory invalidNode = _createValidMultiplierNode(1e55);

        vm.prank(OWNER);
        vm.expectRevert(ModuleMultiplier.ModuleMultiplierInvalidInput.selector);
        oracle.updateMultiplierNode(invalidNode);
    }

    function test_RevertWhen_NodeMultiplierIsNotDivisibleBy10() external givenCallerIsOwner {
        MultiplierNode memory invalidNode = _createValidMultiplierNode(11);

        vm.prank(OWNER);
        vm.expectRevert(ModuleMultiplier.ModuleMultiplierInvalidInput.selector);
        oracle.updateMultiplierNode(invalidNode);
    }

    function test_WhenMultiplierNodeIsValid() external givenCallerIsOwner {
        (uint256 oldMultiplier) = oracle.multiplierNode();
        MultiplierNode memory oldNode = MultiplierNode({multiplier: oldMultiplier});

        uint256 newMultiplier = 1000;
        MultiplierNode memory newNode = _createValidMultiplierNode(newMultiplier);

        vm.expectEmit(true, true, true, true);
        emit IAltoChainlinkERC4626RatioMultiplierOracleEvents.SetMultiplierNode(oldNode, newNode);

        vm.prank(OWNER);
        oracle.updateMultiplierNode(newNode);

        (uint256 multiplier) = oracle.multiplierNode();
        assertEq(multiplier, newMultiplier);
    }
}
