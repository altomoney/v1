// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {AltoRethLendingOracle} from "@alto/oracles/lending/AltoRethLendingOracle.sol";
import {ChainlinkNode, ERC4626RatioNode} from "@alto/oracles/interfaces/IModuleNode.sol";
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
    ERC4626RatioNode erc4626RatioNode;
    ChainlinkNode chainlinkNode;

    function setUp() public {
        string memory rpcUrl = vm.rpcUrl("ethereum");
        vm.createSelectFork(rpcUrl, 23532976);
        // taken from AAVE's contract https://etherscan.io/address/0x6929706c42d637df5ebf7f0bcff2af47f84ea69d
        erc4626RatioNode = ERC4626RatioNode(1098284517740008249, 1708004591, 0.093 ether);
        chainlinkNode = ChainlinkNode(AggregatorV3Interface(CHAINLINK_ETH_USD_PRICE_FEED), 1, 2 hours, 18, 36);
        altoRethLendingOracle = new AltoRethLendingOracle(OWNER, erc4626RatioNode, chainlinkNode, RETH);
    }

    function testGetPrice() public view {
        uint256 price = altoRethLendingOracle.getPrice();
        console2.log("price from AltoRethLendingOracle", price);

        assertApproxEqRel(price, 5148 * 1e36, 1e15, "Incorrect price returned by AltoRethLendingOracle");

        uint256 rETHToETHRatio = IReth(RETH).getExchangeRate();
        (, int256 chainlinkAnswer,,,) = AggregatorV3Interface(CHAINLINK_ETH_USD_PRICE_FEED).latestRoundData();
        console2.log("chainlinkAnswer", chainlinkAnswer);

        // chainlinkAnswer is in 8 decimals
        // we need to convert it to 18 decimals
        uint256 chainlinkPrice = uint256(chainlinkAnswer) * 1e18 / 1e8;

        uint256 expectedRethUsdPrice = rETHToETHRatio * chainlinkPrice;
        console2.log("expectedRethUsdPrice", expectedRethUsdPrice);

        assertEq(expectedRethUsdPrice, price, "Invalid price from expected and actual price from AltoRethLendingOracle");
    }

    function testOnlyOwnerCanUpdateChainlinkNode() public {
        address nonOwner = makeAddr("NonOwner");
        vm.startPrank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        altoRethLendingOracle.updateChainlinkNode(chainlinkNode);
        vm.stopPrank();

        ChainlinkNode memory newChainlinkNode =
            ChainlinkNode(AggregatorV3Interface(CHAINLINK_ETH_USD_PRICE_FEED), 1, 2 hours, 18, 18);

        vm.startPrank(OWNER);
        vm.expectEmit(true, true, true, true);
        emit IAltoRethLendingOracleEvents.SetChainlinkNode(chainlinkNode, newChainlinkNode);
        altoRethLendingOracle.updateChainlinkNode(newChainlinkNode);
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
