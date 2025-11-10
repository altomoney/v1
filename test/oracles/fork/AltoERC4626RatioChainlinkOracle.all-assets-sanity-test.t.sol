// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ChainlinkNode, ERC4626RatioNode, ConversionDirection} from "@alto/oracles/interfaces/IModuleNode.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {
    ERC4626RatioChainlinkOracleMETH,
    IMethStaking
} from "@alto/oracles/AltoERC4626RatioChainlinkOracle/implementations/ERC4626RatioChainlinkOracleMETH.sol";
import {
    ERC4626RatioChainlinkOracleRETH,
    IReth
} from "@alto/oracles/AltoERC4626RatioChainlinkOracle/implementations/ERC4626RatioChainlinkOracleRETH.sol";
import {
    ERC4626RatioChainlinkOracleSUSDE
} from "@alto/oracles/AltoERC4626RatioChainlinkOracle/implementations/ERC4626RatioChainlinkOracleSUSDE.sol";
import {
    ERC4626RatioChainlinkOracleWSTETH,
    IWstEth
} from "@alto/oracles/AltoERC4626RatioChainlinkOracle/implementations/ERC4626RatioChainlinkOracleWSTETH.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract AltoERC4626RatioChainlinkOracleGetPriceForkTest is Test {
    address internal OWNER = makeAddr("Alto-multisig");

    function test_GetPrice_Meth() public {
        // Fork and setup
        string memory rpcUrl = vm.rpcUrl("ethereum");
        vm.createSelectFork(rpcUrl, 23690069);

        address METH_STAKING = 0xe3cBd06D7dadB3F4e6557bAb7EdD924CD1489E8f;
        address CHAINLINK_ETH_USD_PRICE_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

        ERC4626RatioNode memory erc4626RatioNode = ERC4626RatioNode(1 ether, 1696594100, 0.08 ether);
        ChainlinkNode memory chainlinkNode = ChainlinkNode(
            AggregatorV3Interface(CHAINLINK_ETH_USD_PRICE_FEED), ConversionDirection.IN_TO_OUT, 2 hours, 18, 36
        );
        ERC4626RatioChainlinkOracleMETH oracle =
            new ERC4626RatioChainlinkOracleMETH(OWNER, METH_STAKING, erc4626RatioNode, chainlinkNode);

        uint256 price = oracle.getPrice();
        console2.log("price from AltoMethLendingOracle", price);
        assertApproxEqRel(price, 4187 * 1e36, 1e15, "Invalid price from AltoMethLendingOracle");

        uint256 mETHToETHRatio = IMethStaking(METH_STAKING).mETHToETH(1 ether);
        (, int256 ethUsdChainlinkPrice,,,) = AggregatorV3Interface(CHAINLINK_ETH_USD_PRICE_FEED).latestRoundData();
        uint256 ethUsdPrice = uint256(ethUsdChainlinkPrice) * 1e18 / 1e8;
        uint256 expected = mETHToETHRatio * ethUsdPrice;
        assertEq(expected, price, "Invalid price from AltoMethLendingOracle");
    }

    function test_GetPrice_Reth() public {
        // Fork and setup
        string memory rpcUrl = vm.rpcUrl("ethereum");
        vm.createSelectFork(rpcUrl, 23532976);

        address RETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;
        address CHAINLINK_ETH_USD_PRICE_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

        // taken from AAVE's contract https://etherscan.io/address/0x6929706c42d637df5ebf7f0bcff2af47f84ea69d
        ERC4626RatioNode memory erc4626RatioNode = ERC4626RatioNode(1098284517740008249, 1708004591, 0.093 ether);
        ChainlinkNode memory chainlinkNode = ChainlinkNode(
            AggregatorV3Interface(CHAINLINK_ETH_USD_PRICE_FEED), ConversionDirection.IN_TO_OUT, 2 hours, 18, 36
        );
        ERC4626RatioChainlinkOracleRETH oracle =
            new ERC4626RatioChainlinkOracleRETH(OWNER, RETH, erc4626RatioNode, chainlinkNode);

        uint256 price = oracle.getPrice();
        console2.log("price from AltoRethLendingOracle", price);
        assertApproxEqRel(price, 5148 * 1e36, 1e15, "Incorrect price returned by AltoRethLendingOracle");

        uint256 rETHToETHRatio = IReth(RETH).getExchangeRate();
        (, int256 chainlinkAnswer,,,) = AggregatorV3Interface(CHAINLINK_ETH_USD_PRICE_FEED).latestRoundData();
        uint256 chainlinkPrice = uint256(chainlinkAnswer) * 1e18 / 1e8;
        uint256 expected = rETHToETHRatio * chainlinkPrice;
        assertEq(expected, price, "Invalid price from AltoRethLendingOracle");
    }

    function test_GetPrice_Susde() public {
        // Fork and setup
        string memory rpcUrl = vm.rpcUrl("ethereum");
        vm.createSelectFork(rpcUrl, 23490557);

        address SUSDE = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
        address CHAINLINK_USDE_USD_PRICE_FEED = 0xa569d910839Ae8865Da8F8e70FfFb0cBA869F961;

        ERC4626RatioNode memory erc4626RatioNode = ERC4626RatioNode(1157209899495068171, 1708004591, 0.06 ether);
        ChainlinkNode memory chainlinkNode = ChainlinkNode(
            AggregatorV3Interface(CHAINLINK_USDE_USD_PRICE_FEED), ConversionDirection.IN_TO_OUT, 26 hours, 18, 36
        );
        ERC4626RatioChainlinkOracleSUSDE oracle =
            new ERC4626RatioChainlinkOracleSUSDE(OWNER, SUSDE, erc4626RatioNode, chainlinkNode);

        uint256 price = oracle.getPrice();
        console2.log("price from AltoSusdeLendingOracle", price);
        assertApproxEqRel(price, 1.2015 * 1e36, 1e15, "Incorrect price returned by AltoSusdeLendingOracle");

        uint256 susdeUsdeRatio = IERC4626(SUSDE).convertToAssets(10 ** IERC20Metadata(SUSDE).decimals());
        susdeUsdeRatio = susdeUsdeRatio * 1e18;
        assertApproxEqRel(susdeUsdeRatio, price, 1e15, "Higher deviation between susdeUsdeRatio and price");
    }

    function test_GetPrice_WstEth() public {
        // Fork and setup
        string memory rpcUrl = vm.rpcUrl("ethereum");
        vm.createSelectFork(rpcUrl, 23483134);

        address WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
        address CHAINLINK_ETH_USD_PRICE_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

        ERC4626RatioNode memory erc4626RatioNode = ERC4626RatioNode(1157209899495068171, 1708004591, 0.06 ether);
        ChainlinkNode memory chainlinkNode = ChainlinkNode(
            AggregatorV3Interface(CHAINLINK_ETH_USD_PRICE_FEED), ConversionDirection.IN_TO_OUT, 2 hours, 18, 36
        );
        ERC4626RatioChainlinkOracleWSTETH oracle =
            new ERC4626RatioChainlinkOracleWSTETH(OWNER, WSTETH, erc4626RatioNode, chainlinkNode);

        uint256 price = oracle.getPrice();
        console2.log("price from AltoWstEthLendingOracle", price);
        assertApproxEqRel(price, 5225.6 * 1e36, 1e15, "Invalid price from AltoWstEthLendingOracle");

        uint256 wstETHstEthRatio = IWstEth(WSTETH).stEthPerToken();
        (, int256 ethUsdChainlinkPrice,,,) = AggregatorV3Interface(CHAINLINK_ETH_USD_PRICE_FEED).latestRoundData();
        uint256 ethUsdPrice = uint256(ethUsdChainlinkPrice) * 1e18 / 1e8;
        uint256 expected = wstETHstEthRatio * ethUsdPrice;
        assertEq(expected, price, "Invalid price from AltoWstEthLendingOracle");
    }
}

