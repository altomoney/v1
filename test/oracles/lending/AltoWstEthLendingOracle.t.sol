// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {AltoWstEthLendingOracle} from "@alto/oracles/lending/AltoWstEthLendingOracle.sol";
import {
    ChainlinkNode,
    RedstoneNode,
    ERC4626RatioNode,
    ChainlinkRedstoneNode
} from "@alto/oracles/interfaces/IModuleNode.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {console2} from "forge-std/console2.sol";
import {IWstEth} from "@alto/oracles/interfaces/IWstEth.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAltoWstEthLendingOracleEvents} from "@alto/oracles/interfaces/IAltoWstEthLendingOracle.sol";

contract AltoWstEthLendingOracleTest is Test {
    AltoWstEthLendingOracle public altoWstEthLendingOracle;
    address OWNER = makeAddr("Alto-multisig");
    address constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    uint256 constant MAX_ALLOWED_DEVIATION = 1e16; // 1%
    address constant CHAINLINK_ETH_USD_PRICE_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address constant REDSTONE_ETH_USD_PRICE_FEED = 0x67F6838e58859d612E4ddF04dA396d6DABB66Dc4;
    address constant REDSTONE_WSTETH_USD_PRICE_FEED = 0xe4aE88743c3834d0c492eAbC47384c84BcADC6a6;
    uint256 constant CHAINLINK_WEIGHT = 0.9e18;
    uint256 constant REDSTONE_WEIGHT = 0.1e18;
    ERC4626RatioNode erc4626RatioNode;
    ChainlinkRedstoneNode chainlinkRedstoneNode;
    RedstoneNode redstoneNode;

    function setUp() public {
        string memory rpcUrl = vm.rpcUrl("ethereum");
        vm.createSelectFork(rpcUrl, 23483134);
        erc4626RatioNode = ERC4626RatioNode(1157209899495068171, 1708004591, 0.06 ether);
        chainlinkRedstoneNode = ChainlinkRedstoneNode(
            ChainlinkNode(AggregatorV3Interface(CHAINLINK_ETH_USD_PRICE_FEED), 1, 2 hours, 8, 8),
            RedstoneNode(AggregatorV3Interface(REDSTONE_ETH_USD_PRICE_FEED), 1, 26 hours, 18, 8),
            MAX_ALLOWED_DEVIATION,
            CHAINLINK_WEIGHT,
            REDSTONE_WEIGHT
        );
        redstoneNode = RedstoneNode(AggregatorV3Interface(REDSTONE_WSTETH_USD_PRICE_FEED), 1, 8 hours, 18, 18);
        altoWstEthLendingOracle = new AltoWstEthLendingOracle(
            OWNER, WSTETH, MAX_ALLOWED_DEVIATION, erc4626RatioNode, chainlinkRedstoneNode, redstoneNode
        );
    }

    function testGetPrice() public view {
        uint256 priceOfWstEth = altoWstEthLendingOracle.getPrice();
        console2.log("price from AltoWstEthLendingOracle", priceOfWstEth);

        assertApproxEqRel(priceOfWstEth, 5225.6 * 1e36, 1e15, "Invalid price from AltoWstEthLendingOracle");

        (, int256 redstoneAnswer,,,) = AggregatorV3Interface(REDSTONE_WSTETH_USD_PRICE_FEED).latestRoundData();
        uint256 redstoneWstEthUsdPrice = uint256(redstoneAnswer);
        console2.log("redstonePrice", redstoneWstEthUsdPrice);

        // redstoneWstEthUsdPrice is in 8 decimals
        // we need to convert it to 36 decimals
        redstoneWstEthUsdPrice = redstoneWstEthUsdPrice * 1e28;

        assertApproxEqRel(
            redstoneWstEthUsdPrice,
            priceOfWstEth,
            MAX_ALLOWED_DEVIATION,
            "Price from AltoWstEthLendingOracle and redstoneWstEthUsdPrice is not within the allowed deviation"
        );
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

    function testOnlyOwnerCanUpdateChainlinkRedstoneNode() public {
        address nonOwner = makeAddr("NonOwner");
        vm.startPrank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        altoWstEthLendingOracle.updateChainlinkRedstoneNode(chainlinkRedstoneNode);
        vm.stopPrank();

        vm.startPrank(OWNER);
        ChainlinkRedstoneNode memory newChainlinkRedstoneNode = ChainlinkRedstoneNode(
            ChainlinkNode(AggregatorV3Interface(CHAINLINK_ETH_USD_PRICE_FEED), 1, 2 hours, 8, 18),
            RedstoneNode(AggregatorV3Interface(REDSTONE_ETH_USD_PRICE_FEED), 1, 26 hours, 18, 18),
            MAX_ALLOWED_DEVIATION,
            CHAINLINK_WEIGHT + 1e16,
            REDSTONE_WEIGHT - 1e16
        );
        vm.expectEmit(true, true, true, true);
        emit IAltoWstEthLendingOracleEvents.SetChainlinkRedstoneNode(chainlinkRedstoneNode, newChainlinkRedstoneNode);
        altoWstEthLendingOracle.updateChainlinkRedstoneNode(newChainlinkRedstoneNode);
        vm.stopPrank();
    }

    function testOnlyOwnerCanUpdateRedstoneNode() public {
        address nonOwner = makeAddr("NonOwner");
        vm.startPrank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        altoWstEthLendingOracle.updateRedstoneNode(redstoneNode);
        vm.stopPrank();

        vm.startPrank(OWNER);
        RedstoneNode memory newRedstoneNode =
            RedstoneNode(AggregatorV3Interface(REDSTONE_WSTETH_USD_PRICE_FEED), 1, 26 hours, 18, 12);
        vm.expectEmit(true, true, true, true);
        emit IAltoWstEthLendingOracleEvents.SetRedstoneNode(redstoneNode, newRedstoneNode);
        altoWstEthLendingOracle.updateRedstoneNode(newRedstoneNode);
        vm.stopPrank();
    }

    function testOnlyOwnerCanUpdateMaxAllowedDeviation() public {
        address nonOwner = makeAddr("NonOwner");
        vm.startPrank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        altoWstEthLendingOracle.updateMaxAllowedDeviation(MAX_ALLOWED_DEVIATION);
        vm.stopPrank();

        vm.startPrank(OWNER);
        vm.expectEmit(true, true, true, true);
        emit IAltoWstEthLendingOracleEvents.SetMaxAllowedDeviation(MAX_ALLOWED_DEVIATION, MAX_ALLOWED_DEVIATION);
        altoWstEthLendingOracle.updateMaxAllowedDeviation(MAX_ALLOWED_DEVIATION);
        vm.stopPrank();
    }
}
