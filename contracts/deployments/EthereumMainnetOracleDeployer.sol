// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ChainlinkNode, ConversionDirection, ERC4626RatioNode} from "@alto/oracles/interfaces/IModuleNode.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {AltoMultiChainlinkLendingOracle} from "@alto/oracles/AltoMultiChainlinkLendingOracle.sol";
import {
    ERC4626RatioChainlinkOracleWSTETH,
    IWstEth
} from "@alto/oracles/AltoERC4626RatioChainlinkOracle/implementations/ERC4626RatioChainlinkOracleWSTETH.sol";
import {
    ERC4626RatioChainlinkOracleRETH,
    IReth
} from "@alto/oracles/AltoERC4626RatioChainlinkOracle/implementations/ERC4626RatioChainlinkOracleRETH.sol";
import {
    ERC4626RatioChainlinkOracleMETH,
    IMethStaking
} from "@alto/oracles/AltoERC4626RatioChainlinkOracle/implementations/ERC4626RatioChainlinkOracleMETH.sol";
import {
    ERC4626RatioChainlinkOracleSUSDE,
    IERC4626
} from "@alto/oracles/AltoERC4626RatioChainlinkOracle/implementations/ERC4626RatioChainlinkOracleSUSDE.sol";

enum EthereumMainnetLendingOracleAsset {
    WETH,
    WBTC,
    cbBTC,
    SUSDE,
    METH,
    tBTC,
    rETH,
    stETH
}

library EthereumMainnetOracleDeployer {
    address constant CHAINLINK_ETH_USD_PRICE_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address constant CHAINLINK_BTC_USD_PRICE_FEED = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;
    address constant CHAINLINK_WBTC_BTC_RATIO_FEED = 0xfdFD9C85aD200c506Cf9e21F1FD8dd01932FBB23;
    address constant CHAINLINK_USDE_USD_FEED = 0xa569d910839Ae8865Da8F8e70FfFb0cBA869F961;

    address constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address constant RETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;
    address constant METH_STAKING = 0xe3cBd06D7dadB3F4e6557bAb7EdD924CD1489E8f;
    address constant SUSDE = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;

    function deployOracle(EthereumMainnetLendingOracleAsset asset, address owner) public returns (address) {
        if (asset == EthereumMainnetLendingOracleAsset.WETH) {
            return deployWethOracle(owner);
        } else if (asset == EthereumMainnetLendingOracleAsset.WBTC) {
            return deployWbtcOracle(owner);
        } else if (asset == EthereumMainnetLendingOracleAsset.cbBTC) {
            return deployCbbtcOracle(owner);
        } else if (asset == EthereumMainnetLendingOracleAsset.SUSDE) {
            return deploySusdeOracle(owner);
        } else if (asset == EthereumMainnetLendingOracleAsset.METH) {
            return deployMethOracle(owner);
        } else if (asset == EthereumMainnetLendingOracleAsset.tBTC) {
            return deployTbtcOracle(owner);
        } else if (asset == EthereumMainnetLendingOracleAsset.rETH) {
            return deployRethOracle(owner);
        } else if (asset == EthereumMainnetLendingOracleAsset.stETH) {
            return deployWstEthOracle(owner);
        }

        revert("Invalid asset");
    }

    function deployWethOracle(address owner) public returns (address) {
        ChainlinkNode[] memory chainlinkNodes = new ChainlinkNode[](1);

        chainlinkNodes[0] = ChainlinkNode({
            feed: AggregatorV3Interface(CHAINLINK_ETH_USD_PRICE_FEED),
            direction: ConversionDirection.IN_TO_OUT, // ETH to USD
            stalePeriod: 2 hours, // TODO placeholder value
            inDecimals: 18, // ETH decimals
            outDecimals: 36 // LENDING_ORACLE_PRICE_PRECISION + DUSD decimals - WETH decimals
        });

        return address(new AltoMultiChainlinkLendingOracle(owner, chainlinkNodes));
    }

    function deployWstEthOracle(address owner) public returns (address) {
        uint256 stEthPerToken = IWstEth(WSTETH).stEthPerToken() * 1005 / 1000; // +0.5%

        ERC4626RatioNode memory erc4626RatioNode = ERC4626RatioNode({
            initialRatio: stEthPerToken,
            initialTimestamp: block.timestamp,
            maxYearlyGrowthRatioWad: 0.07 ether // 7%
        });

        ChainlinkNode memory chainlinkNode = ChainlinkNode({
            feed: AggregatorV3Interface(CHAINLINK_ETH_USD_PRICE_FEED),
            direction: ConversionDirection.IN_TO_OUT, // ETH to USD
            stalePeriod: 2 hours, // TODO placeholder value
            inDecimals: 18, // stETH/ETH decimals
            outDecimals: 36 // LENDING_ORACLE_PRICE_PRECISION + DUSD decimals - stETH decimals
        });

        return address(new ERC4626RatioChainlinkOracleWSTETH(owner, WSTETH, erc4626RatioNode, chainlinkNode));
    }

    function deployRethOracle(address owner) public returns (address) {
        uint256 rethPerToken = IReth(RETH).getExchangeRate() * 1005 / 1000; // +0.5%

        ERC4626RatioNode memory erc4626RatioNode = ERC4626RatioNode({
            initialRatio: rethPerToken,
            initialTimestamp: block.timestamp,
            maxYearlyGrowthRatioWad: 0.07 ether // 7%
        });

        ChainlinkNode memory chainlinkNode = ChainlinkNode({
            feed: AggregatorV3Interface(CHAINLINK_ETH_USD_PRICE_FEED),
            direction: ConversionDirection.IN_TO_OUT, // ETH to USD
            stalePeriod: 2 hours, // TODO placeholder value
            inDecimals: 18, // ETH decimals
            outDecimals: 36 // LENDING_ORACLE_PRICE_PRECISION + DUSD decimals - rETH decimals
        });

        return address(new ERC4626RatioChainlinkOracleRETH(owner, RETH, erc4626RatioNode, chainlinkNode));
    }

    function deployMethOracle(address owner) public returns (address) {
        uint256 methPerToken = IMethStaking(METH_STAKING).mETHToETH(1 ether) * 1005 / 1000; // +0.5%

        ERC4626RatioNode memory erc4626RatioNode = ERC4626RatioNode({
            initialRatio: methPerToken,
            initialTimestamp: block.timestamp,
            maxYearlyGrowthRatioWad: 0.08 ether // 8%
        });

        ChainlinkNode memory chainlinkNode = ChainlinkNode({
            feed: AggregatorV3Interface(CHAINLINK_ETH_USD_PRICE_FEED),
            direction: ConversionDirection.IN_TO_OUT, // ETH to USD
            stalePeriod: 2 hours, // TODO placeholder value
            inDecimals: 18, // ETH decimals
            outDecimals: 36 // LENDING_ORACLE_PRICE_PRECISION + DUSD decimals - mETH decimals
        });

        return address(new ERC4626RatioChainlinkOracleMETH(owner, METH_STAKING, erc4626RatioNode, chainlinkNode));
    }

    function deployTbtcOracle(address owner) public returns (address) {
        ChainlinkNode[] memory chainlinkNodes = new ChainlinkNode[](1);

        chainlinkNodes[0] = ChainlinkNode({
            feed: AggregatorV3Interface(CHAINLINK_BTC_USD_PRICE_FEED),
            direction: ConversionDirection.IN_TO_OUT, // BTC to USD
            stalePeriod: 2 hours, // TODO placeholder value
            inDecimals: 18, // tBTC/BTC decimals
            outDecimals: 36 // LENDING_ORACLE_PRICE_PRECISION + DUSD decimals - tBTC decimals
        });

        return address(new AltoMultiChainlinkLendingOracle(owner, chainlinkNodes));
    }

    function deployWbtcOracle(address owner) public returns (address) {
        ChainlinkNode[] memory chainlinkNodes = new ChainlinkNode[](2);

        chainlinkNodes[0] = ChainlinkNode({
            feed: AggregatorV3Interface(CHAINLINK_WBTC_BTC_RATIO_FEED),
            direction: ConversionDirection.IN_TO_OUT, // BTC to USD
            stalePeriod: 26 hours, // TODO placeholder value
            inDecimals: 8, // WBTC decimals
            outDecimals: 8 // BTC
        });

        chainlinkNodes[1] = ChainlinkNode({
            feed: AggregatorV3Interface(CHAINLINK_BTC_USD_PRICE_FEED),
            direction: ConversionDirection.IN_TO_OUT, // BTC to USD
            stalePeriod: 2 hours, // TODO placeholder value
            inDecimals: 8, // BTC decimals
            outDecimals: 46 // LENDING_ORACLE_PRICE_PRECISION + DUSD decimals - wBTC decimals
        });

        return address(new AltoMultiChainlinkLendingOracle(owner, chainlinkNodes));
    }

    function deployCbbtcOracle(address owner) public returns (address) {
        ChainlinkNode[] memory chainlinkNodes = new ChainlinkNode[](1);

        chainlinkNodes[0] = ChainlinkNode({
            feed: AggregatorV3Interface(CHAINLINK_BTC_USD_PRICE_FEED),
            direction: ConversionDirection.IN_TO_OUT, // BTC to USD
            stalePeriod: 2 hours, // TODO placeholder value
            inDecimals: 8, // cbBTC/BTC decimals
            outDecimals: 46 // LENDING_ORACLE_PRICE_PRECISION + DUSD decimals - cbBTC decimals
        });

        return address(new AltoMultiChainlinkLendingOracle(owner, chainlinkNodes));
    }

    function deploySusdeOracle(address owner) public returns (address) {
        uint256 rethPerToken = IERC4626(SUSDE).convertToAssets(1 ether) * 1015 / 1000; // +1.5%

        ERC4626RatioNode memory erc4626RatioNode = ERC4626RatioNode({
            initialRatio: rethPerToken,
            initialTimestamp: block.timestamp,
            maxYearlyGrowthRatioWad: 0.185 ether // 18.5%
        });

        ChainlinkNode memory chainlinkNode = ChainlinkNode({
            feed: AggregatorV3Interface(CHAINLINK_USDE_USD_FEED),
            direction: ConversionDirection.IN_TO_OUT, // USDe to USD
            stalePeriod: 26 hours, // TODO placeholder value
            inDecimals: 18, // USDe decimals
            outDecimals: 36 // LENDING_ORACLE_PRICE_PRECISION + DUSD decimals - USDe decimals
        });

        return address(new ERC4626RatioChainlinkOracleSUSDE(owner, SUSDE, erc4626RatioNode, chainlinkNode));
    }
}
