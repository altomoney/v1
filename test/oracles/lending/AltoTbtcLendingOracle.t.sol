// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {AltoTbtcLendingOracle} from "@alto/oracles/lending/AltoTbtcLendingOracle.sol";
import {ChainlinkNode} from "@alto/oracles/interfaces/IModuleNode.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {console2} from "forge-std/console2.sol";
import {IAltoTbtcLendingOracleEvents} from "@alto/oracles/interfaces/IAltoTbtcLendingOracle.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAltoTbtcLendingOracle} from "@alto/oracles/interfaces/IAltoTbtcLendingOracle.sol";

contract AltoTbtcLendingOracleTest is Test {
    address constant CHAINLINK_BTC_USD_PRICE_FEED = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;
    IAltoTbtcLendingOracle internal altoTbtcLendingOracle;
    ChainlinkNode internal chainlinkNode;

    address OWNER = makeAddr("Alto-multisig");
    uint256 chainlinkPrice;
    uint256 chainlinkDecimals;

    function setUp() public {
        altoTbtcLendingOracle = IAltoTbtcLendingOracle(
            address(
                new AltoTbtcLendingOracle(
                    OWNER, ChainlinkNode(AggregatorV3Interface(CHAINLINK_BTC_USD_PRICE_FEED), 1, 2 hours, 18, 36)
                )
            )
        );
        chainlinkNode = altoTbtcLendingOracle.chainlinkNode();

        // Fetch chainlink price at forked block
        string memory rpcUrl = vm.rpcUrl("ethereum");
        vm.createSelectFork(rpcUrl, 23489205);
        (, int256 chainlinkAnswer,,,) = AggregatorV3Interface(CHAINLINK_BTC_USD_PRICE_FEED).latestRoundData();
        chainlinkPrice = uint256(chainlinkAnswer);
        chainlinkDecimals = AggregatorV3Interface(CHAINLINK_BTC_USD_PRICE_FEED).decimals();
    }

    function testGetPrice() public view {
        uint256 price = altoTbtcLendingOracle.getPrice();

        assertEq(
            price,
            chainlinkPrice * (10 ** (chainlinkNode.outDecimals - chainlinkDecimals)),
            "Incorrect price returned by AltoTbtcLendingOracle"
        );
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
