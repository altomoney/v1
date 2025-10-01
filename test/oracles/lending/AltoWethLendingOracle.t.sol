// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {AltoWethLendingOracle} from "@alto/oracles/lending/AltoWethLendingOracle.sol";
import {ChainlinkNode, RedstoneNode, ChainlinkRedstoneNode} from "@alto/oracles/interfaces/IModuleNode.sol";
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
    address constant REDSTONE_ETH_USD_PRICE_FEED = 0x67F6838e58859d612E4ddF04dA396d6DABB66Dc4;
    uint256 constant CHAINLINK_WEIGHT = 0.9e18;
    uint256 constant REDSTONE_WEIGHT = 0.1e18;
    uint256 constant MAX_ALLOWED_DEVIATION = 1e16;
    ChainlinkRedstoneNode chainlinkRedstoneNode;
    ChainlinkNode chainlinkNode;
    RedstoneNode redstoneNode;

    function setUp() public {
        string memory rpcUrl = vm.rpcUrl("ethereum");
        vm.createSelectFork(rpcUrl, 23474424);
        chainlinkNode = ChainlinkNode(AggregatorV3Interface(CHAINLINK_ETH_USD_PRICE_FEED), 1, 2 hours, 8, 8);
        redstoneNode = RedstoneNode(AggregatorV3Interface(REDSTONE_ETH_USD_PRICE_FEED), 1, 26 hours, 18, 8);
        chainlinkRedstoneNode =
            ChainlinkRedstoneNode(chainlinkNode, redstoneNode, MAX_ALLOWED_DEVIATION, CHAINLINK_WEIGHT, REDSTONE_WEIGHT);

        altoWethLendingOracle = new AltoWethLendingOracle(OWNER, chainlinkRedstoneNode);
    }

    function testGetPrice() public view {
        uint256 price = altoWethLendingOracle.getPrice();
        console2.log("price from AltoWethLendingOracle", price);

        assertApproxEqRel(price, 4185 * ORACLE_PRICE_PRECISION, 1e15, "Invalid price from AltoWethLendingOracle");

        (, int256 chainlinkAnswer,,,) = AggregatorV3Interface(CHAINLINK_ETH_USD_PRICE_FEED).latestRoundData();
        uint256 chainlinkPrice = uint256(chainlinkAnswer);
        console2.log("chainlinkPrice", chainlinkPrice);

        (, int256 redstoneAnswer,,,) = AggregatorV3Interface(REDSTONE_ETH_USD_PRICE_FEED).latestRoundData();
        uint256 redstonePrice = uint256(redstoneAnswer);
        console2.log("redstonePrice", redstonePrice);

        // output precision should be in 36
        // chainlinkPrice and redstonePrice are in 8 decimals
        // chainlinkWeight and redstoneWeight are in 18 decimals
        uint256 expectedAnswer = (chainlinkPrice * CHAINLINK_WEIGHT + redstonePrice * REDSTONE_WEIGHT) * 1e18 / 1e8;

        assertApproxEqRel(
            expectedAnswer, price, 1e14, "Invalid price from expected and actual price from AltoWethLendingOracle"
        );
    }

    function testOnlyOwnerCanUpdateChainlinkRedstoneNode() public {
        address nonOwner = makeAddr("NonOwner");
        vm.startPrank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        altoWethLendingOracle.updateChainlinkRedstoneNode(chainlinkRedstoneNode);
        vm.stopPrank();

        vm.startPrank(OWNER);
        ChainlinkRedstoneNode memory newChainlinkRedstoneNode = ChainlinkRedstoneNode(
            chainlinkNode, redstoneNode, MAX_ALLOWED_DEVIATION, CHAINLINK_WEIGHT + 1e16, REDSTONE_WEIGHT - 1e16
        );
        vm.expectEmit(true, true, true, true);
        emit IAltoWethLendingOracleEvents.SetChainlinkRedstoneNode(chainlinkRedstoneNode, newChainlinkRedstoneNode);
        altoWethLendingOracle.updateChainlinkRedstoneNode(newChainlinkRedstoneNode);
        vm.stopPrank();
    }
}
