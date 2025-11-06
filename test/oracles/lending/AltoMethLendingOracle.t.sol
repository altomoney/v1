// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {AltoMethLendingOracle} from "@alto/oracles/lending/AltoMethLendingOracle.sol";
import {ChainlinkNode, ERC4626RatioNode, ConversionDirection} from "@alto/oracles/interfaces/IModuleNode.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {console2} from "forge-std/console2.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAltoMethLendingOracleEvents} from "@alto/oracles/interfaces/IAltoMethLendingOracle.sol";
import {IMethStaking} from "@alto/oracles/interfaces/IMethStaking.sol";

contract AltoMethLendingOracleTest is Test {
    AltoMethLendingOracle public altoMethLendingOracle;
    address OWNER = makeAddr("Alto-multisig");
    address constant METH_STAKING = 0xe3cBd06D7dadB3F4e6557bAb7EdD924CD1489E8f;
    address constant CHAINLINK_ETH_USD_PRICE_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    ERC4626RatioNode erc4626RatioNode;
    ChainlinkNode chainlinkNode;

    function setUp() public {
        string memory rpcUrl = vm.rpcUrl("ethereum");
        vm.createSelectFork(rpcUrl, 23690069);
        erc4626RatioNode = ERC4626RatioNode(1 ether, 1696594100, 0.08 ether);
        chainlinkNode = ChainlinkNode(
            AggregatorV3Interface(CHAINLINK_ETH_USD_PRICE_FEED), ConversionDirection.IN_TO_OUT, 2 hours, 18, 36
        );
        altoMethLendingOracle = new AltoMethLendingOracle(OWNER, METH_STAKING, erc4626RatioNode, chainlinkNode);
    }

    function testGetPrice() public view {
        uint256 priceOfMeth = altoMethLendingOracle.getPrice();
        console2.log("price from AltoMethLendingOracle", priceOfMeth);

        assertApproxEqRel(priceOfMeth, 4187 * 1e36, 1e15, "Invalid price from AltoMethLendingOracle");

        uint256 mETHToETHRatio = IMethStaking(METH_STAKING).mETHToETH(1 ether);
        console2.log("mETHToETHRatio", mETHToETHRatio);

        (, int256 ethUsdChainlinkPrice,,,) = AggregatorV3Interface(CHAINLINK_ETH_USD_PRICE_FEED).latestRoundData();
        // chainlink price is in 8 decimals
        // we need to convert it to 18 decimals
        uint256 ethUsdPrice = uint256(ethUsdChainlinkPrice) * 1e18 / 1e8;
        console2.log("ethUsdPrice", ethUsdPrice);

        uint256 mETHUsdPrice = mETHToETHRatio * ethUsdPrice;
        console2.log("mETHUsdPrice", mETHUsdPrice);

        assertEq(mETHUsdPrice, priceOfMeth, "Invalid price from AltoMethLendingOracle");
    }

    function testOnlyOwnerCanUpdateERC4626RatioNode() public {
        address nonOwner = makeAddr("NonOwner");
        vm.startPrank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        altoMethLendingOracle.updateERC4626RatioNode(erc4626RatioNode);
        vm.stopPrank();

        vm.startPrank(OWNER);
        ERC4626RatioNode memory newERC4626RatioNode = ERC4626RatioNode(1157209899495068171, 1708004591, 0.08 ether);
        vm.expectEmit(true, true, true, true);
        emit IAltoMethLendingOracleEvents.SetERC4626RatioNode(erc4626RatioNode, newERC4626RatioNode);
        altoMethLendingOracle.updateERC4626RatioNode(newERC4626RatioNode);
        vm.stopPrank();
    }

    function testOnlyOwnerCanUpdateChainlinkNode() public {
        address nonOwner = makeAddr("NonOwner");
        vm.startPrank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        altoMethLendingOracle.updateChainlinkNode(chainlinkNode);
        vm.stopPrank();

        vm.startPrank(OWNER);
        ChainlinkNode memory newChainlinkNode = ChainlinkNode(
            AggregatorV3Interface(CHAINLINK_ETH_USD_PRICE_FEED), ConversionDirection.IN_TO_OUT, 2 hours, 18, 18
        );
        vm.expectEmit(true, true, true, true);
        emit IAltoMethLendingOracleEvents.SetChainlinkNode(chainlinkNode, newChainlinkNode);
        altoMethLendingOracle.updateChainlinkNode(newChainlinkNode);
        vm.stopPrank();
    }
}
