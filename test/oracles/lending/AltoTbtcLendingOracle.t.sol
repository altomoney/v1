// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {AltoTbtcLendingOracle} from "@alto/oracles/lending/AltoTbtcLendingOracle.sol";
import {ChainlinkNode, RedstoneNode, ChainlinkRedstoneNode} from "@alto/oracles/interfaces/IModuleNode.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {console2} from "forge-std/console2.sol";
import {IAltoTbtcLendingOracleEvents} from "@alto/oracles/interfaces/IAltoTbtcLendingOracle.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract AltoTbtcLendingOracleTest is Test {
    AltoTbtcLendingOracle public altoTbtcLendingOracle;
    address OWNER = makeAddr("Alto-multisig");
    address constant CHAINLINK_BTC_USD_PRICE_FEED = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;
    address constant REDSTONE_BTC_USD_PRICE_FEED = 0xAB7f623fb2F6fea6601D4350FA0E2290663C28Fc;
    uint256 constant CHAINLINK_WEIGHT = 0.9e18; // 90%
    uint256 constant REDSTONE_WEIGHT = 0.1e18; // 10%
    uint256 constant MAX_ALLOWED_DEVIATION = 1e16; // 1%
    ChainlinkNode chainlinkNode;
    RedstoneNode redstoneNode;
    ChainlinkRedstoneNode chainlinkRedstoneNode;

    function setUp() public {
        string memory rpcUrl = vm.rpcUrl("ethereum");
        vm.createSelectFork(rpcUrl, 23489205);
        chainlinkNode = ChainlinkNode(AggregatorV3Interface(CHAINLINK_BTC_USD_PRICE_FEED), 1, 2 hours, 18, 18);
        redstoneNode = RedstoneNode(AggregatorV3Interface(REDSTONE_BTC_USD_PRICE_FEED), 1, 26 hours, 8, 18);
        chainlinkRedstoneNode =
            ChainlinkRedstoneNode(chainlinkNode, redstoneNode, MAX_ALLOWED_DEVIATION, CHAINLINK_WEIGHT, REDSTONE_WEIGHT);

        altoTbtcLendingOracle = new AltoTbtcLendingOracle(OWNER, chainlinkRedstoneNode);
    }

    function testGetPrice() public view {
        uint256 price = altoTbtcLendingOracle.getPrice();
        console2.log("price from AltoTbtcLendingOracle", price);

        assertApproxEqRel(price, 118700 * 1e36, 5e15, "Incorrect price returned by AltoTbtcLendingOracle");

        (, int256 chainlinkAnswer,,,) = AggregatorV3Interface(CHAINLINK_BTC_USD_PRICE_FEED).latestRoundData();
        uint256 chainlinkPrice = uint256(chainlinkAnswer);
        console2.log("chainlinkPrice", chainlinkPrice);

        (, int256 redstoneAnswer,,,) = AggregatorV3Interface(REDSTONE_BTC_USD_PRICE_FEED).latestRoundData();
        uint256 redstonePrice = uint256(redstoneAnswer);
        console2.log("redstonePrice", redstonePrice);

        // chainlink price and redstone price are in 8 decimals
        // chainlinkWeight and redstoneWeight are in 18 decimals
        // expected answer is in 36 decimals
        uint256 expectedAnswer = (chainlinkPrice * CHAINLINK_WEIGHT + redstonePrice * REDSTONE_WEIGHT) * 1e18 / 1e8;

        assertApproxEqRel(
            expectedAnswer, price, 1e14, "Invalid price from expected and actual price from AltoTbtcLendingOracle"
        );
    }

    function testOnlyOwnerCanUpdateChainlinkRedstoneNode() public {
        address nonOwner = makeAddr("NonOwner");
        vm.startPrank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        altoTbtcLendingOracle.updateChainlinkRedstoneNode(chainlinkRedstoneNode);
        vm.stopPrank();

        vm.startPrank(OWNER);
        ChainlinkRedstoneNode memory newChainlinkRedstoneNode = ChainlinkRedstoneNode(
            ChainlinkNode(AggregatorV3Interface(CHAINLINK_BTC_USD_PRICE_FEED), 1, 2 hours, 18, 18),
            RedstoneNode(AggregatorV3Interface(REDSTONE_BTC_USD_PRICE_FEED), 1, 26 hours, 18, 18),
            MAX_ALLOWED_DEVIATION,
            CHAINLINK_WEIGHT + 1e16,
            REDSTONE_WEIGHT - 1e16
        );
        vm.expectEmit(true, true, true, true);
        emit IAltoTbtcLendingOracleEvents.SetChainlinkRedstoneNode(chainlinkRedstoneNode, newChainlinkRedstoneNode);
        altoTbtcLendingOracle.updateChainlinkRedstoneNode(newChainlinkRedstoneNode);
        vm.stopPrank();
    }
}
