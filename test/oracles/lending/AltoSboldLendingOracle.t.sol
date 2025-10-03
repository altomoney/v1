// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {AltoSboldLendingOracle} from "@alto/oracles/lending/AltoSboldLendingOracle.sol";
import {
    ERC4626RatioNode,
    CurveNode,
    ChainlinkNode,
    RedstoneNode,
    ChainlinkRedstoneNode
} from "@alto/oracles/interfaces/IModuleNode.sol";
import {ICurvePool} from "@alto/oracles/interfaces/ICurvePool.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {console2} from "forge-std/console2.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAltoSboldLendingOracleEvents} from "@alto/oracles/interfaces/IAltoSboldLendingOracle.sol";

contract AltoSboldLendingOracleTest is Test {
    AltoSboldLendingOracle public altoSboldLendingOracle;
    address OWNER = makeAddr("Alto-multisig");
    address constant SBOLD = 0x50Bd66D59911F5e086Ec87aE43C811e0D059DD11;
    address constant CHAINLINK_USDC_USD_PRICE_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address constant REDSTONE_USDC_USD_PRICE_FEED = 0xeeF31c7d9F2E82e8A497b140cc60cc082Be4b94e;
    address constant BOLD_USDC_CURVE_POOL = 0xEFc6516323FbD28e80B85A497B65A86243a54B3E;
    ERC4626RatioNode erc4626RatioNode;
    CurveNode curveNode;
    uint256[] minAllowedLiquidityPool;
    ChainlinkNode chainlinkNode;
    RedstoneNode redstoneNode;
    ChainlinkRedstoneNode chainlinkRedstoneNode;
    uint256 constant CHAINLINK_WEIGHT = 0.9e18; // 90%
    uint256 constant REDSTONE_WEIGHT = 0.1e18; // 10%
    uint256 maxAllowedDeviation = 1e15; // 0.1%

    function setUp() public {
        string memory rpcUrl = vm.rpcUrl("ethereum");
        vm.createSelectFork(rpcUrl, 23496185);

        // assuming 6% yearly growth based on deployment timestamp of sBOLD contract
        erc4626RatioNode = ERC4626RatioNode(1 ether, 1749092411, 0.06 ether);
        curveNode = CurveNode(ICurvePool(BOLD_USDC_CURVE_POOL), 0, 0, 18, 18, 10 minutes, 1 days);
        chainlinkNode = ChainlinkNode(AggregatorV3Interface(CHAINLINK_USDC_USD_PRICE_FEED), 1, 26 hours, 6, 8);
        redstoneNode = RedstoneNode(AggregatorV3Interface(REDSTONE_USDC_USD_PRICE_FEED), 1, 26 hours, 6, 8);
        chainlinkRedstoneNode =
            ChainlinkRedstoneNode(chainlinkNode, redstoneNode, maxAllowedDeviation, CHAINLINK_WEIGHT, REDSTONE_WEIGHT);
        // minimum liquidity for BOLD(18 decimals) and USDC(6 decimals)
        minAllowedLiquidityPool = [1_000_000 * 10 ** 18, 1_000_000 * 10 ** 6];
        altoSboldLendingOracle = new AltoSboldLendingOracle(
            OWNER, SBOLD, erc4626RatioNode, curveNode, minAllowedLiquidityPool, chainlinkRedstoneNode
        );
    }

    function testGetPrice() public view {
        uint256 price = altoSboldLendingOracle.getPrice();
        console2.log("price from AltoSboldLendingOracle", price);

        uint256 sBoldToBoldRatio = IERC4626(SBOLD).convertToAssets(10 ** IERC20Metadata(SBOLD).decimals());
        // convert to 36 decimals
        sBoldToBoldRatio = sBoldToBoldRatio * 1e18;
        console2.log("sBoldToBoldRatio", sBoldToBoldRatio);

        assertApproxEqRel(sBoldToBoldRatio, price, 5e15, "Higher deviation between sBoldToBoldRatio and price");
    }

    function testOnlyOwnerCanUpdateERC4626RatioNode() public {
        address nonOwner = makeAddr("NonOwner");
        vm.startPrank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        altoSboldLendingOracle.updateERC4626RatioNode(erc4626RatioNode);
        vm.stopPrank();

        vm.startPrank(OWNER);
        ERC4626RatioNode memory newERC4626RatioNode = ERC4626RatioNode(1 ether, 1749092411, 0.08 ether);
        vm.expectEmit(true, true, true, true);
        emit IAltoSboldLendingOracleEvents.SetERC4626RatioNode(erc4626RatioNode, newERC4626RatioNode);
        altoSboldLendingOracle.updateERC4626RatioNode(newERC4626RatioNode);
        vm.stopPrank();
    }

    function testOnlyOwnerCanUpdateCurveNode() public {
        address nonOwner = makeAddr("NonOwner");
        vm.startPrank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        altoSboldLendingOracle.updateCurveNode(curveNode);
        vm.stopPrank();

        vm.startPrank(OWNER);
        CurveNode memory newCurveNode = CurveNode(ICurvePool(BOLD_USDC_CURVE_POOL), 0, 0, 18, 18, 10 minutes, 2 days);
        vm.expectEmit(true, true, true, true);
        emit IAltoSboldLendingOracleEvents.SetCurveNode(curveNode, newCurveNode);
        altoSboldLendingOracle.updateCurveNode(newCurveNode);
        vm.stopPrank();
    }

    function testOnlyOwnerCanUpdateChainlinkNode() public {
        address nonOwner = makeAddr("NonOwner");
        vm.startPrank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        altoSboldLendingOracle.updateChainlinkRedstoneNode(chainlinkRedstoneNode);
        vm.stopPrank();

        vm.startPrank(OWNER);
        ChainlinkRedstoneNode memory newChainlinkRedstoneNode = ChainlinkRedstoneNode(
            chainlinkNode, redstoneNode, maxAllowedDeviation, CHAINLINK_WEIGHT - 1, REDSTONE_WEIGHT + 1
        );
        vm.expectEmit(true, true, true, true);
        emit IAltoSboldLendingOracleEvents.SetChainlinkRedstoneNode(chainlinkRedstoneNode, newChainlinkRedstoneNode);
        altoSboldLendingOracle.updateChainlinkRedstoneNode(newChainlinkRedstoneNode);
        vm.stopPrank();
    }
}
