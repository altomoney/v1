// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {AltoWBtcLendingOracle} from "@alto/oracles/lending/AltoWBtcLendingOracle.sol";
import {ChainlinkNode} from "@alto/oracles/interfaces/IModuleNode.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {console2} from "forge-std/console2.sol";
import {ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {
    IAltoWbtcLendingOracleEvents,
    IAltoWbtcLendingOracleErrors
} from "@alto/oracles/interfaces/IAltoWbtcLendingOracle.sol";

contract AltoWBtcLendingOracleTest is Test {
    AltoWBtcLendingOracle public altoWBtcLendingOracle;
    address OWNER = makeAddr("Alto-multisig");
    address constant CHAINLINK_WBTC_BTC_RATIO_FEED = 0xfdFD9C85aD200c506Cf9e21F1FD8dd01932FBB23;
    address constant CHAINLINK_BTC_USD_PRICE_FEED = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;
    ChainlinkNode public chainlinkNode1;
    ChainlinkNode public chainlinkNode2;

    function setUp() public {
        string memory rpcUrl = vm.rpcUrl("ethereum");
        vm.createSelectFork(rpcUrl, 23689416);
        chainlinkNode1 = ChainlinkNode(AggregatorV3Interface(CHAINLINK_WBTC_BTC_RATIO_FEED), 1, 26 hours, 8, 8);
        chainlinkNode2 = ChainlinkNode(AggregatorV3Interface(CHAINLINK_BTC_USD_PRICE_FEED), 1, 2 hours, 8, 8);
        altoWBtcLendingOracle = new AltoWBtcLendingOracle(OWNER, chainlinkNode1, chainlinkNode2);
    }

    function testGetPrice() public view {
        uint256 price = altoWBtcLendingOracle.getPrice();
        console2.log("price from AltoWBtcLendingOracle", price);

        assertApproxEqRel(
            price, 110417 * ORACLE_PRICE_PRECISION * 1e10, 1e15, "Invalid price from AltoWBtcLendingOracle"
        );

        (, int256 chainlinkAnswer1,,,) = AggregatorV3Interface(CHAINLINK_WBTC_BTC_RATIO_FEED).latestRoundData();
        (, int256 chainlinkAnswer2,,,) = AggregatorV3Interface(CHAINLINK_BTC_USD_PRICE_FEED).latestRoundData();
        uint256 chainlinkPrice1 = uint256(chainlinkAnswer1);
        uint256 chainlinkPrice2 = uint256(chainlinkAnswer2);
        console2.log("chainlinkPrice WBTC/BTC", chainlinkPrice1);
        console2.log("chainlinkPrice BTC/USD", chainlinkPrice2);

        // chainlinkPrice1 is in 8 decimals and chainlinkPrice2 is in 8 decimals
        // we need to convert it to 36 decimals
        uint256 expectedAnswer = (chainlinkPrice1 * chainlinkPrice2 * 1e36 * 1e10) / (10 ** 8 * 10 ** 8);

        assertEq(expectedAnswer, price, "Invalid price from expected and actual price from AltoWBtcLendingOracle");
    }

    function testOnlyOwnerCanUpdateChainlinkNode() public {
        address nonOwner = makeAddr("NonOwner");
        vm.startPrank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        altoWBtcLendingOracle.updateChainlinkNode(1, chainlinkNode1);
        vm.stopPrank();

        vm.startPrank(OWNER);
        ChainlinkNode memory newChainlinkNode1 =
            ChainlinkNode(AggregatorV3Interface(CHAINLINK_WBTC_BTC_RATIO_FEED), 1, 26 hours, 8, 8);
        ChainlinkNode memory newChainlinkNode2 =
            ChainlinkNode(AggregatorV3Interface(CHAINLINK_BTC_USD_PRICE_FEED), 1, 2 hours, 8, 8);
        vm.expectEmit(true, true, true, true);
        emit IAltoWbtcLendingOracleEvents.SetChainlinkNode1(chainlinkNode1, newChainlinkNode1);
        emit IAltoWbtcLendingOracleEvents.SetChainlinkNode2(chainlinkNode2, newChainlinkNode2);
        altoWBtcLendingOracle.updateChainlinkNode(1, newChainlinkNode1);
        altoWBtcLendingOracle.updateChainlinkNode(2, newChainlinkNode2);
        vm.stopPrank();
    }

    function testRevertsWhenInvalidIndexIsProvided() public {
        vm.startPrank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(IAltoWbtcLendingOracleErrors.AltoWbtcLendingOracleInvalidInput.selector));
        altoWBtcLendingOracle.updateChainlinkNode(3, chainlinkNode1);
        vm.stopPrank();
    }
}
