// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {
    ChainlinkNode,
    ConversionDirection,
    ERC4626RatioNode,
    MultiplierNode
} from "@alto/oracles/interfaces/IModuleNode.sol";
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
import {
    ISyrupAsset
} from "@alto/oracles/AltoERC4626RatioChainlinkOracle/implementations/ERC4626RatioChainlinkOracleSYRUPUSDC.sol";
import {
    ERC4626RatioChainlinkOracleSYRUPUSDC
} from "@alto/oracles/AltoERC4626RatioChainlinkOracle/implementations/ERC4626RatioChainlinkOracleSYRUPUSDC.sol";
import {
    AltoChainlinkERC4626RatioMultiplierOracle
} from "@alto/oracles/AltoChainlinkERC4626RatioMultiplierOracle/AltoChainlinkERC4626RatioMultiplierOracle.sol";

import {
    CHAINLINK_ETH_USD_PRICE_FEED,
    CHAINLINK_BTC_USD_PRICE_FEED,
    CHAINLINK_WBTC_BTC_RATIO_FEED,
    CHAINLINK_USDE_USD_PRICE_FEED,
    CHAINLINK_USDC_USD_PRICE_FEED,
    CHAINLINK_PAXG_USD_PRICE_FEED,
    CHAINLINK_REUSD_USD_PRICE_FEED,
    WSTETH_MAINNET,
    RETH_MAINNET,
    METH_STAKING_MAINNET,
    SUSDE_MAINNET,
    SYRUPUSDC_MAINNET
} from "@alto/deployments/ethereum-mainnet/Constants.sol";

enum EthereumMainnetLendingOracleAsset {
    WETH,
    WBTC,
    cbBTC,
    SUSDE,
    METH,
    tBTC,
    rETH,
    stETH,
    SYRUPUSDC,
    PAXG,
    REUSD
}

library EthereumMainnetOracleDeployer {
    function deployOracle(EthereumMainnetLendingOracleAsset asset, address owner) internal returns (address) {
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
        } else if (asset == EthereumMainnetLendingOracleAsset.SYRUPUSDC) {
            return deploySyrupUsdcOracle(owner);
        } else if (asset == EthereumMainnetLendingOracleAsset.PAXG) {
            return deployPaxgOracle(owner);
        } else if (asset == EthereumMainnetLendingOracleAsset.REUSD) {
            return deployReusdOracle(owner);
        }

        revert("Invalid asset");
    }

    function deployWethOracle(address owner) internal returns (address) {
        ChainlinkNode[] memory chainlinkNodes = new ChainlinkNode[](1);

        chainlinkNodes[0] = ChainlinkNode({
            feed: AggregatorV3Interface(CHAINLINK_ETH_USD_PRICE_FEED),
            direction: ConversionDirection.IN_TO_OUT, // ETH to USD
            stalePeriod: 3900, // 3900 seconds
            inDecimals: 18, // ETH decimals
            outDecimals: 36, // LENDING_ORACLE_PRICE_PRECISION + DUSD decimals - WETH decimals
            feedDecimals: 8
        });

        return address(new AltoMultiChainlinkLendingOracle(owner, chainlinkNodes));
    }

    function deployWstEthOracle(address owner) internal returns (address) {
        uint256 stEthPerToken = IWstEth(WSTETH_MAINNET).stEthPerToken() * 1005 / 1000; // +0.5%

        ERC4626RatioNode memory erc4626RatioNode = ERC4626RatioNode({
            initialRatio: stEthPerToken,
            initialTimestamp: block.timestamp,
            maxYearlyGrowthRatioWad: 0.07 ether // 7%
        });

        ChainlinkNode memory chainlinkNode = ChainlinkNode({
            feed: AggregatorV3Interface(CHAINLINK_ETH_USD_PRICE_FEED),
            direction: ConversionDirection.IN_TO_OUT, // ETH to USD
            stalePeriod: 3900, // 3900 seconds
            inDecimals: 18, // stETH/ETH decimals
            outDecimals: 36, // LENDING_ORACLE_PRICE_PRECISION + DUSD decimals - stETH decimals
            feedDecimals: 8
        });

        return address(new ERC4626RatioChainlinkOracleWSTETH(owner, WSTETH_MAINNET, erc4626RatioNode, chainlinkNode));
    }

    function deployRethOracle(address owner) internal returns (address) {
        uint256 rethPerToken = IReth(RETH_MAINNET).getExchangeRate() * 1005 / 1000; // +0.5%

        ERC4626RatioNode memory erc4626RatioNode = ERC4626RatioNode({
            initialRatio: rethPerToken,
            initialTimestamp: block.timestamp,
            maxYearlyGrowthRatioWad: 0.07 ether // 7%
        });

        ChainlinkNode memory chainlinkNode = ChainlinkNode({
            feed: AggregatorV3Interface(CHAINLINK_ETH_USD_PRICE_FEED),
            direction: ConversionDirection.IN_TO_OUT, // ETH to USD
            stalePeriod: 3900, // 3900 seconds
            inDecimals: 18, // ETH decimals
            outDecimals: 36, // LENDING_ORACLE_PRICE_PRECISION + DUSD decimals - rETH decimals
            feedDecimals: 8
        });

        return address(new ERC4626RatioChainlinkOracleRETH(owner, RETH_MAINNET, erc4626RatioNode, chainlinkNode));
    }

    function deployMethOracle(address owner) internal returns (address) {
        uint256 methPerToken = IMethStaking(METH_STAKING_MAINNET).mETHToETH(1 ether) * 1005 / 1000; // +0.5%

        ERC4626RatioNode memory erc4626RatioNode = ERC4626RatioNode({
            initialRatio: methPerToken,
            initialTimestamp: block.timestamp,
            maxYearlyGrowthRatioWad: 0.08 ether // 8%
        });

        ChainlinkNode memory chainlinkNode = ChainlinkNode({
            feed: AggregatorV3Interface(CHAINLINK_ETH_USD_PRICE_FEED),
            direction: ConversionDirection.IN_TO_OUT, // ETH to USD
            stalePeriod: 3900, // 3900 seconds
            inDecimals: 18, // ETH decimals
            outDecimals: 36, // LENDING_ORACLE_PRICE_PRECISION + DUSD decimals - mETH decimals
            feedDecimals: 8
        });

        return
            address(new ERC4626RatioChainlinkOracleMETH(owner, METH_STAKING_MAINNET, erc4626RatioNode, chainlinkNode));
    }

    function deployTbtcOracle(address owner) internal returns (address) {
        ChainlinkNode[] memory chainlinkNodes = new ChainlinkNode[](1);

        chainlinkNodes[0] = ChainlinkNode({
            feed: AggregatorV3Interface(CHAINLINK_BTC_USD_PRICE_FEED),
            direction: ConversionDirection.IN_TO_OUT, // BTC to USD
            stalePeriod: 3900, // 3900 seconds
            inDecimals: 18, // tBTC/BTC decimals
            outDecimals: 36, // LENDING_ORACLE_PRICE_PRECISION + DUSD decimals - tBTC decimals
            feedDecimals: 8
        });

        return address(new AltoMultiChainlinkLendingOracle(owner, chainlinkNodes));
    }

    function deployWbtcOracle(address owner) internal returns (address) {
        ChainlinkNode[] memory chainlinkNodes = new ChainlinkNode[](2);

        chainlinkNodes[0] = ChainlinkNode({
            feed: AggregatorV3Interface(CHAINLINK_WBTC_BTC_RATIO_FEED),
            direction: ConversionDirection.IN_TO_OUT, // BTC to USD
            stalePeriod: 86700, // 86700 seconds
            inDecimals: 8, // WBTC decimals
            outDecimals: 8, // BTC
            feedDecimals: 8
        });

        chainlinkNodes[1] = ChainlinkNode({
            feed: AggregatorV3Interface(CHAINLINK_BTC_USD_PRICE_FEED),
            direction: ConversionDirection.IN_TO_OUT, // BTC to USD
            stalePeriod: 3900, // 3900 seconds
            inDecimals: 8, // BTC decimals
            outDecimals: 46, // LENDING_ORACLE_PRICE_PRECISION + DUSD decimals - wBTC decimals
            feedDecimals: 8
        });

        return address(new AltoMultiChainlinkLendingOracle(owner, chainlinkNodes));
    }

    function deployCbbtcOracle(address owner) internal returns (address) {
        ChainlinkNode[] memory chainlinkNodes = new ChainlinkNode[](1);

        chainlinkNodes[0] = ChainlinkNode({
            feed: AggregatorV3Interface(CHAINLINK_BTC_USD_PRICE_FEED),
            direction: ConversionDirection.IN_TO_OUT, // BTC to USD
            stalePeriod: 3900, // 3900 seconds
            inDecimals: 8, // cbBTC/BTC decimals
            outDecimals: 46, // LENDING_ORACLE_PRICE_PRECISION + DUSD decimals - cbBTC decimals
            feedDecimals: 8
        });

        return address(new AltoMultiChainlinkLendingOracle(owner, chainlinkNodes));
    }

    function deploySusdeOracle(address owner) internal returns (address) {
        uint256 susdePerToken = IERC4626(SUSDE_MAINNET).convertToAssets(1 ether) * 1015 / 1000; // +1.5%

        ERC4626RatioNode memory erc4626RatioNode = ERC4626RatioNode({
            initialRatio: susdePerToken,
            initialTimestamp: block.timestamp,
            maxYearlyGrowthRatioWad: 0.185 ether // 18.5%
        });

        ChainlinkNode memory chainlinkNode = ChainlinkNode({
            feed: AggregatorV3Interface(CHAINLINK_USDE_USD_PRICE_FEED),
            direction: ConversionDirection.IN_TO_OUT, // USDe to USD
            stalePeriod: 83100, // 83100 seconds
            inDecimals: 18, // USDe decimals
            outDecimals: 36, // LENDING_ORACLE_PRICE_PRECISION + DUSD decimals - USDe decimals
            feedDecimals: 8
        });

        return address(new ERC4626RatioChainlinkOracleSUSDE(owner, SUSDE_MAINNET, erc4626RatioNode, chainlinkNode));
    }

    function deploySyrupUsdcOracle(address owner) internal returns (address) {
        uint256 usdcPerToken = ISyrupAsset(SYRUPUSDC_MAINNET).convertToExitAssets(1e6) * 1005 / 1000; // +0.5%

        ERC4626RatioNode memory erc4626RatioNode = ERC4626RatioNode({
            initialRatio: usdcPerToken,
            initialTimestamp: block.timestamp,
            maxYearlyGrowthRatioWad: 0.12 ether // 12%
        });

        ChainlinkNode memory chainlinkNode = ChainlinkNode({
            feed: AggregatorV3Interface(CHAINLINK_USDC_USD_PRICE_FEED),
            direction: ConversionDirection.IN_TO_OUT, // USDC to USD
            stalePeriod: 86700, // 86700 seconds
            inDecimals: 6, // decimals of syrup USDC ratio
            outDecimals: 48, // LENDING_ORACLE_PRICE_PRECISION + DUSD decimals - USDC decimals
            feedDecimals: 8
        });

        return
            address(new ERC4626RatioChainlinkOracleSYRUPUSDC(owner, SYRUPUSDC_MAINNET, erc4626RatioNode, chainlinkNode));
    }

    function deployPaxgOracle(address owner) internal returns (address) {
        ChainlinkNode[] memory chainlinkNodes = new ChainlinkNode[](1);

        chainlinkNodes[0] = ChainlinkNode({
            feed: AggregatorV3Interface(CHAINLINK_PAXG_USD_PRICE_FEED),
            direction: ConversionDirection.IN_TO_OUT, // PAXG to USD
            stalePeriod: 86700, // 86700 seconds
            inDecimals: 18, // PAXG decimals
            outDecimals: 36, // LENDING_ORACLE_PRICE_PRECISION + DUSD decimals - PAXG decimals
            feedDecimals: 8
        });

        return address(new AltoMultiChainlinkLendingOracle(owner, chainlinkNodes));
    }

    function deployReusdOracle(address owner) internal returns (address) {
        (, int256 initialRatio,, uint256 navUpdatedAt,) =
            AggregatorV3Interface(CHAINLINK_REUSD_USD_PRICE_FEED).latestRoundData();
        require(initialRatio > 0, "reUSD: invalid NAV");
        require(block.timestamp - navUpdatedAt <= 86700, "reUSD: stale NAV");
        initialRatio = initialRatio * 1015 / 1000; // +1.5%
        ERC4626RatioNode memory erc4626RatioNode = ERC4626RatioNode({
            initialRatio: uint256(initialRatio),
            initialTimestamp: block.timestamp,
            maxYearlyGrowthRatioWad: 0.185 ether // 18.5%
        });

        ChainlinkNode memory chainlinkNode = ChainlinkNode({
            feed: AggregatorV3Interface(CHAINLINK_REUSD_USD_PRICE_FEED),
            direction: ConversionDirection.IN_TO_OUT, // reUSD to USD
            stalePeriod: 86700, // 86700 seconds
            inDecimals: 18, // reUSD decimals
            outDecimals: 18, // the decimals of ratio used in erc4626RatioNode
            feedDecimals: 18
        });

        MultiplierNode memory multiplierNode = MultiplierNode({multiplier: 10 ** 18});

        // the decimals of reUSD is 18, so we want output in 36 decimals since decimals of DUSD is also 18
        // the decimals of chainlink node output is 18, so we want to multiply by 10 ** 18 to get the price in 36 decimals
        return
            address(
                new AltoChainlinkERC4626RatioMultiplierOracle(owner, chainlinkNode, erc4626RatioNode, multiplierNode)
            );
    }
}
