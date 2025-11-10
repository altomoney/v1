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
    IAltoWbtcLendingOracleErrors,
    IAltoWbtcLendingOracle
} from "@alto/oracles/interfaces/IAltoWbtcLendingOracle.sol";

contract AltoWBtcLendingOracleTest is Test {
    address constant CHAINLINK_WBTC_BTC_RATIO_FEED = 0xfdFD9C85aD200c506Cf9e21F1FD8dd01932FBB23;
    address constant CHAINLINK_BTC_USD_PRICE_FEED = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;

    IAltoWbtcLendingOracle internal altoWBtcLendingOracle;
    ChainlinkNode internal chainlinkNode1;
    ChainlinkNode internal chainlinkNode2;

    address OWNER = makeAddr("Alto-multisig");
    uint256 chainlinkPrice;

    function setUp() public {
        altoWBtcLendingOracle = IAltoWbtcLendingOracle(
            address(
                new AltoWBtcLendingOracle(
                    OWNER,
                    ChainlinkNode(AggregatorV3Interface(CHAINLINK_WBTC_BTC_RATIO_FEED), 1, 26 hours, 8, 8),
                    ChainlinkNode(AggregatorV3Interface(CHAINLINK_BTC_USD_PRICE_FEED), 1, 2 hours, 8, 36)
                )
            )
        );

        chainlinkNode1 = altoWBtcLendingOracle.chainlinkNode1();
        chainlinkNode2 = altoWBtcLendingOracle.chainlinkNode2();

        string memory rpcUrl = vm.rpcUrl("ethereum");
        vm.createSelectFork(rpcUrl, 23689416);
        (, int256 chainlinkAnswer,,,) = AggregatorV3Interface(CHAINLINK_BTC_USD_PRICE_FEED).latestRoundData();
        chainlinkPrice = uint256(chainlinkAnswer);
    }

    function testGetPrice() public view {
        uint256 price = altoWBtcLendingOracle.getPrice();

        // Make sure price is approximately within btc/usd price
        assertApproxEqRel(
            price,
            chainlinkPrice * (10 ** (chainlinkNode2.outDecimals - chainlinkNode2.inDecimals)),
            1e15,
            "Invalid price from AltoWBtcLendingOracle"
        );
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
