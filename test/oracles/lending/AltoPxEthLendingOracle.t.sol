// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {AltoPxEthLendingOracle} from "@alto/oracles/lending/AltoPxEthLendingOracle.sol";
import {CurveNode, ChainlinkNode, RedstoneNode, ChainlinkRedstoneNode} from "@alto/oracles/interfaces/IModuleNode.sol";
import {ICurvePool} from "@alto/oracles/interfaces/ICurvePool.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {console2} from "forge-std/console2.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAltoPxEthLendingOracleEvents} from "@alto/oracles/interfaces/IAltoPxEthLendingOracle.sol";

contract AltoPxEthLendingOracleTest is Test {
    address constant CHAINLINK_ETH_USD_PRICE_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address constant REDSTONE_ETH_USD_PRICE_FEED = 0x67F6838e58859d612E4ddF04dA396d6DABB66Dc4;
    uint256 constant CHAINLINK_WEIGHT = 0.9e18;
    uint256 constant REDSTONE_WEIGHT = 0.1e18;
    ChainlinkRedstoneNode chainlinkRedstoneNode;
    ChainlinkNode chainlinkNode;
    RedstoneNode redstoneNode;
    address constant PXETH_WETH_CURVE_POOL = 0xC8Eb2Cf2f792F77AF0Cd9e203305a585E588179D; // curve pool for pxETH/WETH
    address constant PXETH_STETH_CURVE_POOL = 0x6951bDC4734b9f7F3E1B74afeBC670c736A0EDB6; // curve pool for pxETH/STETH
    uint256 constant MAX_ALLOWED_DEVIATION = 2e16; // 2%
    uint256[] public minAllowedLiquidityPool1 = [100 ether, 100 ether];
    uint256[] public minAllowedLiquidityPool2 = [100 ether, 100 ether];
    AltoPxEthLendingOracle public altoPxEthLendingOracle;
    address OWNER = makeAddr("Alto-multisig");
    CurveNode curveNode1;
    CurveNode curveNode2;

    function setUp() public {
        string memory rpcUrl = vm.rpcUrl("ethereum");
        vm.createSelectFork(rpcUrl, 23484104);
        curveNode1 = CurveNode(ICurvePool(PXETH_WETH_CURVE_POOL), 0, 0, 8, 8, 10 minutes, 1 days);
        curveNode2 = CurveNode(ICurvePool(PXETH_STETH_CURVE_POOL), 0, 0, 8, 8, 10 minutes, 1 days);
        chainlinkNode = ChainlinkNode(AggregatorV3Interface(CHAINLINK_ETH_USD_PRICE_FEED), 1, 2 hours, 18, 18);
        redstoneNode = RedstoneNode(AggregatorV3Interface(REDSTONE_ETH_USD_PRICE_FEED), 1, 26 hours, 8, 18);
        chainlinkRedstoneNode =
            ChainlinkRedstoneNode(chainlinkNode, redstoneNode, MAX_ALLOWED_DEVIATION, CHAINLINK_WEIGHT, REDSTONE_WEIGHT);
        altoPxEthLendingOracle = new AltoPxEthLendingOracle(
            OWNER,
            curveNode1,
            minAllowedLiquidityPool1,
            curveNode2,
            minAllowedLiquidityPool2,
            MAX_ALLOWED_DEVIATION,
            chainlinkRedstoneNode
        );
    }

    function testGetPrice() public view {
        uint256 price = altoPxEthLendingOracle.getPrice();
        console2.log("price from AltoPxEthLendingOracle", price);

        assertApproxEqRel(price, 4330 * 1e36, 5e15, "Incorrect price returned by AltoPxEthLendingOracle");

        (, int256 ethUsdPrice,,,) = AggregatorV3Interface(CHAINLINK_ETH_USD_PRICE_FEED).latestRoundData();
        console2.log("ethUsdPrice from Chainlink", ethUsdPrice);
        assertApproxEqRel(
            price, uint256(ethUsdPrice) * 1e28, 5e15, "Price of pxETH deviating too much from Chainlink ETH/USD price"
        );
    }

    function testOnlyOwnerCanUpdateCurveNode() public {
        address nonOwner = makeAddr("NonOwner");
        vm.startPrank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        altoPxEthLendingOracle.updateCurveNode(true, curveNode1, false, curveNode2);
        vm.stopPrank();

        vm.startPrank(OWNER);
        CurveNode memory newCurveNode1 = CurveNode(ICurvePool(PXETH_WETH_CURVE_POOL), 0, 0, 8, 8, 10 minutes, 15 days);
        vm.expectEmit(true, true, true, true);
        emit IAltoPxEthLendingOracleEvents.SetCurveNode1(curveNode1, newCurveNode1);
        altoPxEthLendingOracle.updateCurveNode(true, newCurveNode1, false, curveNode2);

        CurveNode memory newCurveNode2 = CurveNode(ICurvePool(PXETH_STETH_CURVE_POOL), 0, 0, 8, 8, 10 minutes, 15 days);
        vm.expectEmit(true, true, true, true);
        emit IAltoPxEthLendingOracleEvents.SetCurveNode2(curveNode2, newCurveNode2);
        altoPxEthLendingOracle.updateCurveNode(false, curveNode1, true, newCurveNode2);
        vm.stopPrank();
    }

    function testOnlyOwnerCanUpdateChainlinkRedstoneNode() public {
        address nonOwner = makeAddr("NonOwner");
        vm.startPrank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        altoPxEthLendingOracle.updateChainlinkRedstoneNode(chainlinkRedstoneNode);
        vm.stopPrank();

        vm.startPrank(OWNER);
        ChainlinkRedstoneNode memory newChainlinkRedstoneNode = ChainlinkRedstoneNode(
            ChainlinkNode(AggregatorV3Interface(CHAINLINK_ETH_USD_PRICE_FEED), 1, 5 hours, 8, 18),
            RedstoneNode(AggregatorV3Interface(REDSTONE_ETH_USD_PRICE_FEED), 1, 27 hours, 8, 18),
            MAX_ALLOWED_DEVIATION,
            CHAINLINK_WEIGHT + 1e16,
            REDSTONE_WEIGHT - 1e16
        );
        vm.expectEmit(true, true, true, true);
        emit IAltoPxEthLendingOracleEvents.SetChainlinkRedstoneNode(chainlinkRedstoneNode, newChainlinkRedstoneNode);
        altoPxEthLendingOracle.updateChainlinkRedstoneNode(newChainlinkRedstoneNode);
        vm.stopPrank();
    }

    function testOnlyOwnerCanUpdateMaxAllowedDeviation() public {
        address nonOwner = makeAddr("NonOwner");
        vm.startPrank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        altoPxEthLendingOracle.updateMaxAllowedDeviation(MAX_ALLOWED_DEVIATION);
        vm.stopPrank();

        vm.startPrank(OWNER);
        uint256 newMaxAllowedDeviation = MAX_ALLOWED_DEVIATION + 1;
        vm.expectEmit(true, true, true, true);
        emit IAltoPxEthLendingOracleEvents.SetMaxAllowedDeviation(MAX_ALLOWED_DEVIATION, newMaxAllowedDeviation);
        altoPxEthLendingOracle.updateMaxAllowedDeviation(newMaxAllowedDeviation);
        vm.stopPrank();
    }

    function testOnlyOwnerCanUpdateMinAllowedLiquidityPool() public {
        address nonOwner = makeAddr("NonOwner");
        vm.startPrank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        altoPxEthLendingOracle.updateMinAllowedLiquidityPoo1(true, minAllowedLiquidityPool1);
        vm.stopPrank();

        vm.startPrank(OWNER);
        uint256[] memory newMinAllowedLiquidityPool1 = new uint256[](2);
        newMinAllowedLiquidityPool1[0] = 1000 ether;
        newMinAllowedLiquidityPool1[1] = 1000 ether;
        vm.expectEmit(true, true, true, true);
        emit IAltoPxEthLendingOracleEvents.SetMinAllowedLiquidityPool1(
            minAllowedLiquidityPool1, newMinAllowedLiquidityPool1
        );
        altoPxEthLendingOracle.updateMinAllowedLiquidityPoo1(true, newMinAllowedLiquidityPool1);
        vm.stopPrank();

        vm.startPrank(OWNER);
        uint256[] memory newMinAllowedLiquidityPool2 = new uint256[](2);
        newMinAllowedLiquidityPool2[0] = 1000 ether;
        newMinAllowedLiquidityPool2[1] = 1000 ether;
        vm.expectEmit(true, true, true, true);
        emit IAltoPxEthLendingOracleEvents.SetMinAllowedLiquidityPool2(
            minAllowedLiquidityPool2, newMinAllowedLiquidityPool2
        );
        altoPxEthLendingOracle.updateMinAllowedLiquidityPoo1(false, newMinAllowedLiquidityPool2);
        vm.stopPrank();
    }
}
