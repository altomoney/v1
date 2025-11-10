// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ModuleERC4626Ratio} from "@alto/oracles/lending/modules/ModuleERC4626Ratio.sol";
import {IWstEth} from "@alto-test/oracles/interfaces/IWstEth.sol";
import {MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";
import {ERC4626RatioNode} from "@alto/oracles/interfaces/IModuleNode.sol";

contract ModuleERC4626RatioTest is Test {
    ModuleERC4626Ratio moduleERC4626Ratio;
    IWstEth constant WSTETH = IWstEth(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    address OWNER = makeAddr("Alto-multisig");
    uint256 initialRatio;
    uint256 initialTimestamp;
    uint256 currentRatio;

    function setUp() public {
        string memory rpcUrl = vm.rpcUrl("ethereum");
        vm.createSelectFork(rpcUrl, 22219918);

        moduleERC4626Ratio = new ModuleERC4626Ratio();
        vm.makePersistent(address(moduleERC4626Ratio));

        // cache the ratio from the older blocks
        initialRatio = WSTETH.stEthPerToken();
        initialTimestamp = block.timestamp;

        // forward the fork to the latest block so that ratio of wstETH vault increases
        vm.createSelectFork(rpcUrl, 23476180);
        currentRatio = WSTETH.stEthPerToken();
    }

    function testReadLatestRatioWithinLimits() public view {
        // growth rate of wsteth is less than 4%
        uint256 maxYearlyGrowthRatioWad = 0.04 ether; // 4%
        uint256 latestRatioReturned = moduleERC4626Ratio.readLatestRatio(
            currentRatio, ERC4626RatioNode(initialRatio, initialTimestamp, maxYearlyGrowthRatioWad)
        );
        assertEq(latestRatioReturned, currentRatio, "Latest ratio returned should be equal to current ratio");
    }

    function testReadLatestRatioAboveLimits() public view {
        // growth rate of wsteth is greater than 1%
        uint256 maxYearlyGrowthRatioWad = 0.01 ether; // 1%
        uint256 latestRatioReturned = moduleERC4626Ratio.readLatestRatio(
            currentRatio, ERC4626RatioNode(initialRatio, initialTimestamp, maxYearlyGrowthRatioWad)
        );
        assertNotEq(latestRatioReturned, currentRatio, "Latest ratio returned should not be equal to current ratio");

        uint256 expectedRatio = initialRatio
            + (
                initialRatio * maxYearlyGrowthRatioWad * (block.timestamp - initialTimestamp) / MATH_PRECISION
                    / moduleERC4626Ratio.SECONDS_PER_YEAR()
            );
        assertEq(latestRatioReturned, expectedRatio, "Latest ratio returned should be equal to expected ratio");
    }
}
