// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {AltoCbBtcLendingOracle} from "@alto/oracles/lending/AltoCbBtcLendingOracle.sol";
import {ChainlinkNode} from "@alto/oracles/interfaces/IModuleNode.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {console2} from "forge-std/console2.sol";
import {IAltoCbBtcLendingOracleEvents} from "@alto/oracles/interfaces/IAltoCbBtcLendingOracle.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract AltoCbBtcLendingOracleTest is Test {
    AltoCbBtcLendingOracle public altoCbBtcLendingOracle;
    address OWNER = makeAddr("Alto-multisig");
    address constant CHAINLINK_BTC_USD_PRICE_FEED = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;
    ChainlinkNode chainlinkNode;

    function setUp() public {
        string memory rpcUrl = vm.rpcUrl("ethereum");
        vm.createSelectFork(rpcUrl, 23689559);
        chainlinkNode = ChainlinkNode(AggregatorV3Interface(CHAINLINK_BTC_USD_PRICE_FEED), 1, 2 hours, 18, 18);

        altoCbBtcLendingOracle = new AltoCbBtcLendingOracle(OWNER, chainlinkNode);
    }

    function testGetPrice() public view {
        uint256 price = altoCbBtcLendingOracle.getPrice();
        console2.log("price from AltoCbBtcLendingOracle", price);

        assertApproxEqRel(price, 110000 * 1e36 * 1e10, 5e15, "Incorrect price returned by AltoCbBtcLendingOracle");

        (, int256 chainlinkAnswer,,,) = AggregatorV3Interface(CHAINLINK_BTC_USD_PRICE_FEED).latestRoundData();
        uint256 chainlinkPrice = uint256(chainlinkAnswer);
        console2.log("chainlinkPrice", chainlinkPrice);

        // chainlink price is in 8 decimals
        // we need to convert it to 36 decimals
        chainlinkPrice = chainlinkPrice * 1e36 * 1e10 / 1e8;

        assertEq(chainlinkPrice, price, "Invalid price from expected and actual price from AltoCbBtcLendingOracle");
    }

    function testOnlyOwnerCanUpdateChainlinkNode() public {
        address nonOwner = makeAddr("NonOwner");
        vm.startPrank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        altoCbBtcLendingOracle.updateChainlinkNode(chainlinkNode);
        vm.stopPrank();

        vm.startPrank(OWNER);
        ChainlinkNode memory newChainlinkNode =
            ChainlinkNode(AggregatorV3Interface(CHAINLINK_BTC_USD_PRICE_FEED), 1, 2 hours, 8, 8);
        vm.expectEmit(true, true, true, true);
        emit IAltoCbBtcLendingOracleEvents.SetChainlinkNode(chainlinkNode, newChainlinkNode);
        altoCbBtcLendingOracle.updateChainlinkNode(newChainlinkNode);
        vm.stopPrank();
    }
}
