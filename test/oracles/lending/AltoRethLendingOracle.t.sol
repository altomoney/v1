// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {AltoRethLendingOracle} from "@alto/oracles/lending/AltoRethLendingOracle.sol";
import {
    ChainlinkNode,
    RedstoneNode,
    ChainlinkRedstoneNode,
    ERC4626RatioNode
} from "@alto/oracles/interfaces/IModuleNode.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {
    IAltoRethLendingOracleEvents,
    IAltoRethLendingOracleErrors
} from "@alto/oracles/interfaces/IAltoRethLendingOracle.sol";
import {IReth} from "@alto/oracles/interfaces/IReth.sol";
import {console2} from "forge-std/console2.sol";

contract AltoRethLendingOracleTest is Test {
    AltoRethLendingOracle public altoRethLendingOracle;
    address OWNER = makeAddr("Alto-multisig");
    address constant RETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;
    address constant CHAINLINK_ETH_USD_PRICE_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address constant REDSTONE_ETH_USD_PRICE_FEED = 0x67F6838e58859d612E4ddF04dA396d6DABB66Dc4;
    uint256 constant CHAINLINK_WEIGHT = 0.9e18;
    uint256 constant REDSTONE_WEIGHT = 0.1e18;
    uint256 constant MAX_ALLOWED_DEVIATION = 1e16;
    ERC4626RatioNode erc4626RatioNode;
    ChainlinkRedstoneNode chainlinkRedstoneNode;
    ChainlinkNode chainlinkNode;
    RedstoneNode redstoneNode;

    function setUp() public {
        string memory rpcUrl = vm.rpcUrl("ethereum");
        vm.createSelectFork(rpcUrl, 23532976);
        // taken from AAVE's contract https://etherscan.io/address/0x6929706c42d637df5ebf7f0bcff2af47f84ea69d
        erc4626RatioNode = ERC4626RatioNode(1098284517740008249, 1708004591, 0.093 ether);
        chainlinkNode = ChainlinkNode(AggregatorV3Interface(CHAINLINK_ETH_USD_PRICE_FEED), 1, 2 hours, 8, 18);
        redstoneNode = RedstoneNode(AggregatorV3Interface(REDSTONE_ETH_USD_PRICE_FEED), 1, 26 hours, 8, 18);
        chainlinkRedstoneNode =
            ChainlinkRedstoneNode(chainlinkNode, redstoneNode, MAX_ALLOWED_DEVIATION, CHAINLINK_WEIGHT, REDSTONE_WEIGHT);
        altoRethLendingOracle = new AltoRethLendingOracle(OWNER, erc4626RatioNode, chainlinkRedstoneNode, RETH);
    }

    function testGetPrice() public view {
        uint256 price = altoRethLendingOracle.getPrice();
        console2.log("price from AltoRethLendingOracle", price);

        assertApproxEqRel(price, 5148 * 1e36, 1e15, "Incorrect price returned by AltoRethLendingOracle");

        uint256 rETHToETHRatio = IReth(RETH).getExchangeRate();
        (, int256 chainlinkAnswer,,,) = AggregatorV3Interface(CHAINLINK_ETH_USD_PRICE_FEED).latestRoundData();
        uint256 chainlinkPrice = uint256(chainlinkAnswer);
        console2.log("chainlinkPrice", chainlinkPrice);

        (, int256 redstoneAnswer,,,) = AggregatorV3Interface(REDSTONE_ETH_USD_PRICE_FEED).latestRoundData();
        uint256 redstonePrice = uint256(redstoneAnswer);
        console2.log("redstonePrice", redstonePrice);

        // ETH/USD price in 18 decimals based on weighted average
        uint256 expectedAnswer = (chainlinkPrice * CHAINLINK_WEIGHT + redstonePrice * REDSTONE_WEIGHT) / 1e8;

        uint256 expectedRethUsdPrice = rETHToETHRatio * expectedAnswer;
        console2.log("expectedRethUsdPrice", expectedRethUsdPrice);

        assertEq(expectedRethUsdPrice, price, "Invalid price from expected and actual price from AltoRethLendingOracle");
    }

    function testOnlyOwnerCanUpdateChainlinkRedstoneNode() public {
        address nonOwner = makeAddr("NonOwner");
        vm.startPrank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        altoRethLendingOracle.updateChainlinkRedstoneNode(chainlinkRedstoneNode);
        vm.stopPrank();

        ChainlinkRedstoneNode memory newChainlinkRedstoneNode = ChainlinkRedstoneNode(
            ChainlinkNode(AggregatorV3Interface(CHAINLINK_ETH_USD_PRICE_FEED), 1, 2 hours, 8, 18),
            RedstoneNode(AggregatorV3Interface(REDSTONE_ETH_USD_PRICE_FEED), 1, 2 hours, 8, 18),
            MAX_ALLOWED_DEVIATION,
            CHAINLINK_WEIGHT,
            REDSTONE_WEIGHT
        );

        vm.startPrank(OWNER);
        vm.expectEmit(true, true, true, true);
        emit IAltoRethLendingOracleEvents.SetChainlinkRedstoneNode(chainlinkRedstoneNode, newChainlinkRedstoneNode);
        altoRethLendingOracle.updateChainlinkRedstoneNode(newChainlinkRedstoneNode);
        vm.stopPrank();
    }

    function testOnlyOwnerCanUpdateERC4626RatioNode() public {
        address nonOwner = makeAddr("NonOwner");
        vm.startPrank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        altoRethLendingOracle.updateERC4626RatioNode(erc4626RatioNode);
        vm.stopPrank();

        vm.startPrank(OWNER);
        ERC4626RatioNode memory newERC4626RatioNode = ERC4626RatioNode(1098284517740008249, 1708004591, 0.096 ether);
        vm.expectEmit(true, true, true, true);
        emit IAltoRethLendingOracleEvents.SetERC4626RatioNode(erc4626RatioNode, newERC4626RatioNode);
        altoRethLendingOracle.updateERC4626RatioNode(newERC4626RatioNode);
        vm.stopPrank();
    }
}
