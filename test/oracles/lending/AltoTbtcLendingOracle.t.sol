// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {AltoTbtcLendingOracle} from "@alto/oracles/lending/AltoTbtcLendingOracle.sol";
import {ChainlinkNode} from "@alto/oracles/interfaces/IModuleNode.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {console2} from "forge-std/console2.sol";
import {IAltoTbtcLendingOracleEvents} from "@alto/oracles/interfaces/IAltoTbtcLendingOracle.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract AltoTbtcLendingOracleTest is Test {
    AltoTbtcLendingOracle public altoTbtcLendingOracle;
    address OWNER = makeAddr("Alto-multisig");
    address constant CHAINLINK_BTC_USD_PRICE_FEED = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;
    ChainlinkNode chainlinkNode;

    function setUp() public {
        string memory rpcUrl = vm.rpcUrl("ethereum");
        vm.createSelectFork(rpcUrl, 23489205);
        chainlinkNode = ChainlinkNode(AggregatorV3Interface(CHAINLINK_BTC_USD_PRICE_FEED), 1, 2 hours, 18, 18);

        altoTbtcLendingOracle = new AltoTbtcLendingOracle(OWNER, chainlinkNode);
    }

    function testGetPrice() public view {
        uint256 price = altoTbtcLendingOracle.getPrice();
        console2.log("price from AltoTbtcLendingOracle", price);

        assertApproxEqRel(price, 118700 * 1e36, 5e15, "Incorrect price returned by AltoTbtcLendingOracle");

        (, int256 chainlinkAnswer,,,) = AggregatorV3Interface(CHAINLINK_BTC_USD_PRICE_FEED).latestRoundData();
        uint256 chainlinkPrice = uint256(chainlinkAnswer);
        console2.log("chainlinkPrice", chainlinkPrice);

        // chainlink price is in 8 decimals
        // we need to convert it to 36 decimals
        chainlinkPrice = chainlinkPrice * 1e36 / 1e8;

        assertEq(chainlinkPrice, price, "Invalid price from expected and actual price from AltoTbtcLendingOracle");
    }

    function testOnlyOwnerCanUpdateChainlinkNode() public {
        address nonOwner = makeAddr("NonOwner");
        vm.startPrank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        altoTbtcLendingOracle.updateChainlinkNode(chainlinkNode);
        vm.stopPrank();

        vm.startPrank(OWNER);
        ChainlinkNode memory newChainlinkNode =
            ChainlinkNode(AggregatorV3Interface(CHAINLINK_BTC_USD_PRICE_FEED), 1, 2 hours, 8, 8);
        vm.expectEmit(true, true, true, true);
        emit IAltoTbtcLendingOracleEvents.SetChainlinkNode(chainlinkNode, newChainlinkNode);
        altoTbtcLendingOracle.updateChainlinkNode(newChainlinkNode);
        vm.stopPrank();
    }
}
