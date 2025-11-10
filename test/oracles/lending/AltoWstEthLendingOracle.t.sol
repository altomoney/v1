// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {AltoWstEthLendingOracle} from "@alto/oracles/lending/AltoWstEthLendingOracle.sol";
import {ChainlinkNode, ERC4626RatioNode} from "@alto/oracles/interfaces/IModuleNode.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {console2} from "forge-std/console2.sol";
import {IWstEth} from "@alto/oracles/interfaces/IWstEth.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAltoWstEthLendingOracleEvents} from "@alto/oracles/interfaces/IAltoWstEthLendingOracle.sol";

contract AltoWstEthLendingOracleTest is Test {
    AltoWstEthLendingOracle public altoWstEthLendingOracle;
    address OWNER = makeAddr("Alto-multisig");
    address constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address constant CHAINLINK_ETH_USD_PRICE_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    ERC4626RatioNode erc4626RatioNode;
    ChainlinkNode chainlinkNode;

    function setUp() public {
        string memory rpcUrl = vm.rpcUrl("ethereum");
        vm.createSelectFork(rpcUrl, 23483134);
        erc4626RatioNode = ERC4626RatioNode(1157209899495068171, 1708004591, 0.06 ether);
        chainlinkNode = ChainlinkNode(AggregatorV3Interface(CHAINLINK_ETH_USD_PRICE_FEED), 1, 2 hours, 18, 36);
        altoWstEthLendingOracle = new AltoWstEthLendingOracle(OWNER, WSTETH, erc4626RatioNode, chainlinkNode);
    }

    function testGetPrice() public view {
        uint256 priceOfWstEth = altoWstEthLendingOracle.getPrice();
        console2.log("price from AltoWstEthLendingOracle", priceOfWstEth);

        assertApproxEqRel(priceOfWstEth, 5225.6 * 1e36, 1e15, "Invalid price from AltoWstEthLendingOracle");

        uint256 wstETHstEthRatio = IWstEth(WSTETH).stEthPerToken();
        console2.log("wstETHstEthRatio", wstETHstEthRatio);

        (, int256 ethUsdChainlinkPrice,,,) = AggregatorV3Interface(CHAINLINK_ETH_USD_PRICE_FEED).latestRoundData();
        // chainlink price is in 8 decimals
        // we need to convert it to 18 decimals
        uint256 ethUsdPrice = uint256(ethUsdChainlinkPrice) * 1e18 / 1e8;
        console2.log("ethUsdPrice", ethUsdPrice);

        uint256 wstEthUsdPrice = wstETHstEthRatio * ethUsdPrice;
        console2.log("wstEthUsdPrice", wstEthUsdPrice);

        assertEq(wstEthUsdPrice, priceOfWstEth, "Invalid price from AltoWstEthLendingOracle");
    }

    function testOnlyOwnerCanUpdateERC4626RatioNode() public {
        address nonOwner = makeAddr("NonOwner");
        vm.startPrank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        altoWstEthLendingOracle.updateERC4626RatioNode(erc4626RatioNode);
        vm.stopPrank();

        vm.startPrank(OWNER);
        ERC4626RatioNode memory newERC4626RatioNode = ERC4626RatioNode(1157209899495068171, 1708004591, 0.08 ether);
        vm.expectEmit(true, true, true, true);
        emit IAltoWstEthLendingOracleEvents.SetERC4626RatioNode(erc4626RatioNode, newERC4626RatioNode);
        altoWstEthLendingOracle.updateERC4626RatioNode(newERC4626RatioNode);
        vm.stopPrank();
    }

    function testOnlyOwnerCanUpdateChainlinkNode() public {
        address nonOwner = makeAddr("NonOwner");
        vm.startPrank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        altoWstEthLendingOracle.updateChainlinkNode(chainlinkNode);
        vm.stopPrank();

        vm.startPrank(OWNER);
        ChainlinkNode memory newChainlinkNode =
            ChainlinkNode(AggregatorV3Interface(CHAINLINK_ETH_USD_PRICE_FEED), 1, 2 hours, 18, 18);
        vm.expectEmit(true, true, true, true);
        emit IAltoWstEthLendingOracleEvents.SetChainlinkNode(chainlinkNode, newChainlinkNode);
        altoWstEthLendingOracle.updateChainlinkNode(newChainlinkNode);
        vm.stopPrank();
    }
}
