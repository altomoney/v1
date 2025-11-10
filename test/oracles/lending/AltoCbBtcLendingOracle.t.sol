// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {AltoCbBtcLendingOracle} from "@alto/oracles/lending/AltoCbBtcLendingOracle.sol";
import {ChainlinkNode, ConversionDirection} from "@alto/oracles/interfaces/IModuleNode.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IAltoCbBtcLendingOracleEvents} from "@alto/oracles/interfaces/IAltoCbBtcLendingOracle.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAltoCbBtcLendingOracle} from "@alto/oracles/interfaces/IAltoCbBtcLendingOracle.sol";

contract AltoCbBtcLendingOracleTest is Test {
    address constant CHAINLINK_BTC_USD_PRICE_FEED = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;
    IAltoCbBtcLendingOracle internal altoCbBtcLendingOracle;
    ChainlinkNode internal chainlinkNode;

    address OWNER = makeAddr("Alto-multisig");
    uint256 chainlinkPrice;
    uint256 chainlinkDecimals;

    function setUp() public {
        altoCbBtcLendingOracle = IAltoCbBtcLendingOracle(
            address(
                new AltoCbBtcLendingOracle(
                    OWNER,
                    ChainlinkNode(
                        AggregatorV3Interface(CHAINLINK_BTC_USD_PRICE_FEED),
                        ConversionDirection.IN_TO_OUT,
                        2 hours,
                        8,
                        36
                    )
                )
            )
        );
        chainlinkNode = altoCbBtcLendingOracle.chainlinkNode();

        // Fetch chainlink price at forked block
        string memory rpcUrl = vm.rpcUrl("ethereum");
        vm.createSelectFork(rpcUrl, 23689559);
        (, int256 chainlinkAnswer,,,) = AggregatorV3Interface(CHAINLINK_BTC_USD_PRICE_FEED).latestRoundData();
        chainlinkPrice = uint256(chainlinkAnswer);
        chainlinkDecimals = AggregatorV3Interface(CHAINLINK_BTC_USD_PRICE_FEED).decimals();
    }

    function testGetPrice() public view {
        uint256 price = altoCbBtcLendingOracle.getPrice();

        assertEq(
            price,
            chainlinkPrice * (10 ** (chainlinkNode.outDecimals - chainlinkDecimals)),
            "Incorrect price returned by AltoCbBtcLendingOracle"
        );
    }

    function testOnlyOwnerCanUpdateChainlinkNode() public {
        address nonOwner = makeAddr("NonOwner");
        vm.startPrank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        altoCbBtcLendingOracle.updateChainlinkNode(chainlinkNode);
        vm.stopPrank();

        vm.startPrank(OWNER);
        ChainlinkNode memory newChainlinkNode = ChainlinkNode(
            AggregatorV3Interface(CHAINLINK_BTC_USD_PRICE_FEED), ConversionDirection.IN_TO_OUT, 2 hours, 8, 8
        );
        vm.expectEmit(true, true, true, true);
        emit IAltoCbBtcLendingOracleEvents.SetChainlinkNode(chainlinkNode, newChainlinkNode);
        altoCbBtcLendingOracle.updateChainlinkNode(newChainlinkNode);
        vm.stopPrank();
    }
}
