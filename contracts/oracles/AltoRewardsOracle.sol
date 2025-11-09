// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.7;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {ModuleChainlink} from "@alto/oracles/modules/ModuleChainlink.sol";
import {ModuleUniswap} from "@alto/oracles/modules/ModuleUniswap/ModuleUniswap.sol";
import {UniswapNode, ChainlinkNode, ConversionDirection} from "@alto/oracles/interfaces/IModuleNode.sol";
import {
    IAltoRewardsOracleBase,
    AltoRewardsOracleInitParams,
    IAltoRewardsOracleStaticTypes
} from "@alto/oracles/interfaces/IAltoRewardsOracle.sol";
import {USD_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IUsdOracle.sol";
import {FixedPointMath} from "@alto/utils/FixedPointMath.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/// @title Alto Rewards Oracle
/// @author Pearl Labs
/// @notice Oracle contract used in AltoRewardsDistributor to calculate extended TWAP of ALTO token
/// @dev Provides a fixed price for claiming (exercising) call options in AltoRewardsDistributor
/// @dev Returns USD price of ALTO token in `USD_ORACLE_PRICE_PRECISION` as per `IUsdOracle` interface
contract AltoRewardsOracle is Ownable2Step, ModuleChainlink, ModuleUniswap, IAltoRewardsOracleStaticTypes {
    /// @inheritdoc IAltoRewardsOracleBase
    uint256 public immutable IN_BASE;

    /// @inheritdoc IAltoRewardsOracleStaticTypes
    UniswapNode public uniswapNode;

    /// @inheritdoc IAltoRewardsOracleStaticTypes
    ChainlinkNode public chainlinkNode;

    /// @inheritdoc IAltoRewardsOracleBase
    uint256 public lastPriceUpdateTimestamp;

    /// @inheritdoc IAltoRewardsOracleBase
    uint256 public priceUpdateCooldownPeriod;

    /// @inheritdoc IAltoRewardsOracleBase
    uint256 public cachedPrice;

    /// @inheritdoc IAltoRewardsOracleBase
    bytes32 public description;

    /// @notice Constructor
    /// @param _initParams The initialization parameters
    /// @dev The inDecimals of chainlink node should be the same as decimals of token apart from Alto token of uniswap pool
    constructor(AltoRewardsOracleInitParams memory _initParams) Ownable(_initParams.owner) {
        if (_initParams.inBase == 0) {
            revert AltoRewardsOracleInvalidInput();
        }

        IN_BASE = _initParams.inBase;

        _validateUniswapParams(_initParams.uniswapNode);
        _validateChainlinkParams(_initParams.chainlinkNode);

        uniswapNode = _initParams.uniswapNode;
        emit SetUniswapNode(UniswapNode(IUniswapV3Pool(address(0)), 0, 0), _initParams.uniswapNode);

        chainlinkNode = _initParams.chainlinkNode;
        emit SetChainlinkNode(
            ChainlinkNode(AggregatorV3Interface(address(0)), ConversionDirection.IN_TO_OUT, 0, 0, 0),
            _initParams.chainlinkNode
        );

        description = _initParams.description;

        priceUpdateCooldownPeriod = _initParams.priceUpdateCooldownPeriod;
        emit PriceUpdateCooldownPeriodUpdated(0, _initParams.priceUpdateCooldownPeriod);
    }

    /// @inheritdoc IAltoRewardsOracleBase
    function getPrice() external view override returns (uint256) {
        if (lastPriceUpdateTimestamp == 0) {
            revert AltoRewardsOracleNotInitiated();
        }

        return cachedPrice;
    }

    /// @inheritdoc IAltoRewardsOracleBase
    function startTwapPeriod(uint256 _initialPrice) external onlyOwner {
        if (lastPriceUpdateTimestamp != 0) {
            revert AltoRewardsOracleAlreadyStartedTwapPeriod();
        }

        lastPriceUpdateTimestamp = block.timestamp;
        cachedPrice = _initialPrice;

        emit PriceUpdated(block.timestamp, cachedPrice, 0);
    }

    /// @inheritdoc IAltoRewardsOracleBase
    function updatePrice() external {
        if (lastPriceUpdateTimestamp == 0) {
            revert AltoRewardsOracleNotInitiated();
        }

        if (block.timestamp - lastPriceUpdateTimestamp < priceUpdateCooldownPeriod) {
            revert AltoRewardsOracleTooEarlyToUpdatePrice();
        }

        uint256 oldPrice = cachedPrice;

        // reads the amount of out currency for 1 full unit of in-currency
        // the decimals of newPrice will be the decimals of the out-currency
        uint256 newPrice = readUniswapPool(IN_BASE, uniswapNode);

        // converts the price from the out-currency to chainlinkNode.outDecimals decimals
        cachedPrice = readChainlinkFeed(newPrice, chainlinkNode);

        lastPriceUpdateTimestamp = block.timestamp;

        emit PriceUpdated(block.timestamp, newPrice, oldPrice);
    }

    /// @inheritdoc IAltoRewardsOracleBase
    function updatePriceUpdateCooldownPeriod(uint256 _priceUpdateCooldownPeriod) external onlyOwner {
        if (priceUpdateCooldownPeriod == _priceUpdateCooldownPeriod) {
            revert AltoRewardsOracleInvalidInput();
        }

        emit PriceUpdateCooldownPeriodUpdated(priceUpdateCooldownPeriod, _priceUpdateCooldownPeriod);
        priceUpdateCooldownPeriod = _priceUpdateCooldownPeriod;
    }

    /// @inheritdoc IAltoRewardsOracleBase
    function updateChainlinkNode(ChainlinkNode memory _chainlinkNode) external onlyOwner {
        _validateChainlinkParams(_chainlinkNode);

        emit SetChainlinkNode(chainlinkNode, _chainlinkNode);
        chainlinkNode = _chainlinkNode;
    }

    /// @inheritdoc IAltoRewardsOracleBase
    function updateUniswapNode(UniswapNode memory _uniswapNode) external onlyOwner {
        _validateUniswapParams(_uniswapNode);

        emit SetUniswapNode(uniswapNode, _uniswapNode);
        uniswapNode = _uniswapNode;
    }
}
