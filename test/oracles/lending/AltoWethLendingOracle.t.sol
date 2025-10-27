// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {AltoWethLendingOracle} from "@alto/oracles/lending/AltoWethLendingOracle.sol";
import {ChainlinkNode} from "@alto/oracles/interfaces/IModuleNode.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {console2} from "forge-std/console2.sol";
import {ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {
    IAltoWethLendingOracleEvents,
    IAltoWethLendingOracleErrors
} from "@alto/oracles/interfaces/IAltoWethLendingOracle.sol";

contract AltoWethLendingOracleTest is Test {
    AltoWethLendingOracle public altoWethLendingOracle;
    address OWNER = makeAddr("Alto-multisig");
    address constant CHAINLINK_ETH_USD_PRICE_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    ChainlinkNode public chainlinkNode;

    function setUp() public {
        string memory rpcUrl = vm.rpcUrl("ethereum");
        vm.createSelectFork(rpcUrl, 23474424);
        chainlinkNode = ChainlinkNode(AggregatorV3Interface(CHAINLINK_ETH_USD_PRICE_FEED), 1, 2 hours, 8, 8);
        altoWethLendingOracle = new AltoWethLendingOracle(OWNER, chainlinkNode);
    }

    function testGetPrice() public view {
        uint256 price = altoWethLendingOracle.getPrice();
        console2.log("price from AltoWethLendingOracle", price);

        assertApproxEqRel(price, 4185 * ORACLE_PRICE_PRECISION, 1e15, "Invalid price from AltoWethLendingOracle");

        (, int256 chainlinkAnswer,,,) = AggregatorV3Interface(CHAINLINK_ETH_USD_PRICE_FEED).latestRoundData();
        uint256 chainlinkPrice = uint256(chainlinkAnswer);
        console2.log("chainlinkPrice", chainlinkPrice);

        // output precision should be in 36
        // chainlinkPrice is in 8 decimals
        uint256 expectedAnswer = (chainlinkPrice * 1e36) / 1e8;

        assertEq(expectedAnswer, price, "Invalid price from expected and actual price from AltoWethLendingOracle");
    }

    function testOnlyOwnerCanUpdateChainlinkNode() public {
        address nonOwner = makeAddr("NonOwner");
        vm.startPrank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        altoWethLendingOracle.updateChainlinkNode(chainlinkNode);
        vm.stopPrank();

        vm.startPrank(OWNER);
        ChainlinkNode memory newChainlinkNode =
            ChainlinkNode(AggregatorV3Interface(CHAINLINK_ETH_USD_PRICE_FEED), 1, 2 hours, 18, 18);
        vm.expectEmit(true, true, true, true);
        emit IAltoWethLendingOracleEvents.SetChainlinkNode(chainlinkNode, newChainlinkNode);
        altoWethLendingOracle.updateChainlinkNode(newChainlinkNode);
        vm.stopPrank();
    }
}
