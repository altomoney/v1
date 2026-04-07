// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {AltoCappedChainlinkOracleCommon} from "./AltoCappedChainlinkOracleCommon.t.sol";
import {AltoCappedChainlinkOracle} from "@alto/oracles/AltoCappedChainlinkOracle/AltoCappedChainlinkOracle.sol";
import {ModuleERC4626Ratio} from "@alto/oracles/modules/ModuleERC4626Ratio.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAltoCappedChainlinkOracleEvents} from "@alto/oracles/interfaces/IAltoCappedChainlinkOracle.sol";
import {ERC4626RatioNode} from "@alto/oracles/interfaces/IModuleNode.sol";

contract AltoCappedChainlinkOracleUpdateERC4626RatioNode is AltoCappedChainlinkOracleCommon {
    AltoCappedChainlinkOracle oracle;

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
        ERC4626RatioNode memory validNode = _createValidERC4626RatioNode();

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NON_OWNER));
        oracle.updateERC4626RatioNode(validNode);
    }

    function test_RevertWhen_NodeInitialRatioIsZero() external givenCallerIsOwner {
        uint256 pastTimestamp = block.timestamp > 1 hours ? block.timestamp - 1 hours : block.timestamp;
        ERC4626RatioNode memory invalidNode =
            _createValidERC4626RatioNode(0, pastTimestamp, DEFAULT_MAX_YEARLY_GROWTH_RATIO_WAD);

        vm.prank(OWNER);
        vm.expectRevert(ModuleERC4626Ratio.ModuleERC4626RatioInvalidInput.selector);
        oracle.updateERC4626RatioNode(invalidNode);
    }

    function test_RevertWhen_NodeInitialTimestampIsGreaterThanBlockTimestamp() external givenCallerIsOwner {
        ERC4626RatioNode memory invalidNode = _createValidERC4626RatioNode(
            DEFAULT_INITIAL_RATIO, block.timestamp + 1, DEFAULT_MAX_YEARLY_GROWTH_RATIO_WAD
        );

        vm.prank(OWNER);
        vm.expectRevert(ModuleERC4626Ratio.ModuleERC4626RatioInvalidInput.selector);
        oracle.updateERC4626RatioNode(invalidNode);
    }

    function test_RevertWhen_NodeMaxYearlyGrowthRatioWadIsZero() external givenCallerIsOwner {
        uint256 pastTimestamp = block.timestamp > 1 hours ? block.timestamp - 1 hours : block.timestamp;
        ERC4626RatioNode memory invalidNode = _createValidERC4626RatioNode(DEFAULT_INITIAL_RATIO, pastTimestamp, 0);

        vm.prank(OWNER);
        vm.expectRevert(ModuleERC4626Ratio.ModuleERC4626RatioInvalidInput.selector);
        oracle.updateERC4626RatioNode(invalidNode);
    }

    function test_WhenERC4626RatioNodeIsValid() external givenCallerIsOwner {
        (uint256 oldInitialRatio, uint256 oldInitialTimestamp, uint256 oldMaxYearlyGrowthRatioWad) =
            oracle.erc4626RatioNode();
        ERC4626RatioNode memory oldNode = ERC4626RatioNode({
            initialRatio: oldInitialRatio,
            initialTimestamp: oldInitialTimestamp,
            maxYearlyGrowthRatioWad: oldMaxYearlyGrowthRatioWad
        });

        uint256 newInitialRatio = 2 ether;
        uint256 newInitialTimestamp = block.timestamp > 1 days ? block.timestamp - 1 days : block.timestamp;
        uint256 newMaxYearlyGrowthRatioWad = 0.2 ether;
        ERC4626RatioNode memory newNode =
            _createValidERC4626RatioNode(newInitialRatio, newInitialTimestamp, newMaxYearlyGrowthRatioWad);

        vm.expectEmit(true, true, true, true);
        emit IAltoCappedChainlinkOracleEvents.SetERC4626RatioNode(oldNode, newNode);

        vm.prank(OWNER);
        oracle.updateERC4626RatioNode(newNode);

        (uint256 initialRatio, uint256 initialTimestamp, uint256 maxYearlyGrowthRatioWad) = oracle.erc4626RatioNode();
        assertEq(initialRatio, newInitialRatio);
        assertEq(initialTimestamp, newInitialTimestamp);
        assertEq(maxYearlyGrowthRatioWad, newMaxYearlyGrowthRatioWad);
    }
}
