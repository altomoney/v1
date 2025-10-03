// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {AltoSusdeLendingOracle} from "@alto/oracles/lending/AltoSusdeLendingOracle.sol";
import {
    ERC4626RatioNode,
    ChainlinkNode,
    RedstoneNode,
    ChainlinkRedstoneNode
} from "@alto/oracles/interfaces/IModuleNode.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {console2} from "forge-std/console2.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAltoSusdeLendingOracleEvents} from "@alto/oracles/interfaces/IAltoSusdeLendingOracle.sol";

contract AltoSusdeLendingOracleTest is Test {
    AltoSusdeLendingOracle public altoSusdeLendingOracle;
    address OWNER = makeAddr("Alto-multisig");
    address constant SUSDE = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
    address constant CHAINLINK_USDE_USD_PRICE_FEED = 0xa569d910839Ae8865Da8F8e70FfFb0cBA869F961;
    address constant REDSTONE_USDE_USD_PRICE_FEED = 0xbC5FBcf58CeAEa19D523aBc76515b9AEFb5cfd58;
    uint256 constant CHAINLINK_WEIGHT = 0.9e18;
    uint256 constant REDSTONE_WEIGHT = 0.1e18;
    uint256 constant MAX_ALLOWED_DEVIATION = 1e16;
    ERC4626RatioNode erc4626RatioNode;
    ChainlinkNode chainlinkNode;
    RedstoneNode redstoneNode;
    ChainlinkRedstoneNode chainlinkRedstoneNode;

    function setUp() public {
        string memory rpcUrl = vm.rpcUrl("ethereum");
        vm.createSelectFork(rpcUrl, 23490557);
        erc4626RatioNode = ERC4626RatioNode(1157209899495068171, 1708004591, 0.06 ether);
        chainlinkNode = ChainlinkNode(AggregatorV3Interface(CHAINLINK_USDE_USD_PRICE_FEED), 1, 26 hours, 8, 18);
        redstoneNode = RedstoneNode(AggregatorV3Interface(REDSTONE_USDE_USD_PRICE_FEED), 1, 26 hours, 8, 18);
        chainlinkRedstoneNode =
            ChainlinkRedstoneNode(chainlinkNode, redstoneNode, MAX_ALLOWED_DEVIATION, CHAINLINK_WEIGHT, REDSTONE_WEIGHT);
        altoSusdeLendingOracle = new AltoSusdeLendingOracle(OWNER, erc4626RatioNode, chainlinkRedstoneNode, SUSDE);
    }

    function testGetPrice() public view {
        uint256 price = altoSusdeLendingOracle.getPrice();
        console2.log("price from AltoSusdeLendingOracle", price);

        assertApproxEqRel(price, 1.2015 * 1e36, 1e15, "Incorrect price returned by AltoSusdeLendingOracle");

        uint256 susdeUsdeRatio = IERC4626(SUSDE).convertToAssets(10 ** IERC20Metadata(SUSDE).decimals());
        susdeUsdeRatio = susdeUsdeRatio * 1e18;

        assertApproxEqRel(susdeUsdeRatio, price, 1e15, "Higher deviation between susdeUsdeRatio and price");
    }

    function testOnlyOwnerCanUpdateChainlinkRedstoneNode() public {
        address nonOwner = makeAddr("NonOwner");
        vm.startPrank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        altoSusdeLendingOracle.updateChainlinkRedstoneNode(chainlinkRedstoneNode);
        vm.stopPrank();

        ChainlinkRedstoneNode memory newChainlinkRedstoneNode = ChainlinkRedstoneNode(
            ChainlinkNode(AggregatorV3Interface(CHAINLINK_USDE_USD_PRICE_FEED), 1, 2 hours, 8, 18),
            RedstoneNode(AggregatorV3Interface(REDSTONE_USDE_USD_PRICE_FEED), 1, 2 hours, 8, 18),
            MAX_ALLOWED_DEVIATION,
            CHAINLINK_WEIGHT,
            REDSTONE_WEIGHT
        );

        vm.startPrank(OWNER);
        vm.expectEmit(true, true, true, true);
        emit IAltoSusdeLendingOracleEvents.SetChainlinkRedstoneNode(chainlinkRedstoneNode, newChainlinkRedstoneNode);
        altoSusdeLendingOracle.updateChainlinkRedstoneNode(newChainlinkRedstoneNode);
        vm.stopPrank();
    }

    function testOnlyOwnerCanUpdateERC4626RatioNode() public {
        address nonOwner = makeAddr("NonOwner");
        vm.startPrank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        altoSusdeLendingOracle.updateERC4626RatioNode(erc4626RatioNode);
        vm.stopPrank();

        vm.startPrank(OWNER);
        ERC4626RatioNode memory newERC4626RatioNode = ERC4626RatioNode(1157209899495068171, 1708004591, 0.08 ether);
        vm.expectEmit(true, true, true, true);
        emit IAltoSusdeLendingOracleEvents.SetERC4626RatioNode(erc4626RatioNode, newERC4626RatioNode);
        altoSusdeLendingOracle.updateERC4626RatioNode(newERC4626RatioNode);
        vm.stopPrank();
    }
}
