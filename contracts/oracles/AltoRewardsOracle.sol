// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.7;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

import {ModuleChainlinkMulti} from "@alto/oracles/modules/ModuleChainlinkMulti.sol";
import {ModuleUniswapMulti} from "@alto/oracles/modules/ModuleUniswapMulti.sol";
import {IAltoRewardsOracle, AltoRewardsOracleInitParams} from "@alto/oracles/interfaces/IAltoRewardsOracle.sol";
import {USD_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IUsdOracle.sol";
import {FixedPointMath} from "@alto/utils/FixedPointMath.sol";

/// @title AltoRewardsOracle
/// @author Pearl Labs
/// @author Adapted from Angle Core (https://github.com/AngleProtocol/angle-core)
/// @notice Oracle contract, one contract is deployed per collateral/stablecoin pair
/// @dev This contract concerns an oracle that only uses both Chainlink and Uniswap for multiple pools
/// @dev This is going to be used for like ALTO/USD oracles
/// @dev A rate gives the price of the out-currency with respect to the in-currency in base `USD_ORACLE_PRICE_PRECISION`. For instance
/// if the out-currency is ALTO worth 10 USD and USD_ORACLE_PRICE_PRECISION is 10**8, then the rate ALTO-USD is 10**9
contract AltoRewardsOracle is Ownable2Step, ModuleChainlinkMulti, ModuleUniswapMulti, IAltoRewardsOracle {
    /// @inheritdoc IAltoRewardsOracle
    uint256 public immutable IN_BASE;

    /// @inheritdoc IAltoRewardsOracle
    uint256 public immutable OUT_BASE;

    /// @inheritdoc IAltoRewardsOracle
    uint8 public immutable UNI_FINAL_CURRENCY;

    /// @inheritdoc IAltoRewardsOracle
    uint256 public lastPriceUpdateTimestamp;

    /// @inheritdoc IAltoRewardsOracle
    uint256 public priceUpdateCooldownPeriod;

    /// @inheritdoc IAltoRewardsOracle
    uint256 public cachedPrice;

    /// @inheritdoc IAltoRewardsOracle
    bytes32 public description;

    /// @dev When deploying this contract, it is important to check in the case where Uniswap circuit is not final whether
    /// Chainlink and Uniswap circuits are compatible. If Chainlink is UNI-WBTC and WBTC-USD and Uniswap is just UNI-WETH,
    /// then Chainlink cannot be the final circuit
    constructor(AltoRewardsOracleInitParams memory _initParams)
        ModuleUniswapMulti(
            _initParams.circuitUniswap,
            _initParams.circuitUniIsMultiplied,
            _initParams.twapPeriod,
            _initParams.observationLength
        )
        ModuleChainlinkMulti(_initParams.circuitChainlink, _initParams.circuitChainIsMultiplied, _initParams.stalePeriod)
        Ownable(_initParams.owner)
    {
        if (_initParams.addressInAndOutUni.length != 2) revert AltoRewardsOracleInvalidInput();
        // Using the tokens' metadata to get the in and out currencies decimals
        IERC20Metadata inCur = IERC20Metadata(_initParams.addressInAndOutUni[0]);
        IERC20Metadata outCur = IERC20Metadata(_initParams.addressInAndOutUni[1]);
        IN_BASE = 10 ** (inCur.decimals());
        OUT_BASE = 10 ** (outCur.decimals());
        UNI_FINAL_CURRENCY = _initParams.uniFinalCurrency;
        description = _initParams.description;

        priceUpdateCooldownPeriod = _initParams.priceUpdateCooldownPeriod;
        emit PriceUpdateCooldownPeriodUpdated(0, _initParams.priceUpdateCooldownPeriod);
    }

    /// @inheritdoc IAltoRewardsOracle
    function getPrice() external view override returns (uint256) {
        if (lastPriceUpdateTimestamp == 0) revert AltoRewardsOracleNotInitiated();
        return cachedPrice;
    }

    /// @inheritdoc IAltoRewardsOracle
    function startTwapPeriod(uint256 _initialPrice) external onlyOwner {
        if (lastPriceUpdateTimestamp != 0) revert AltoRewardsOracleAlreadyStartedTwapPeriod();
        lastPriceUpdateTimestamp = block.timestamp;
        cachedPrice = _initialPrice;

        emit PriceUpdated(block.timestamp, cachedPrice, 0);
    }

    /// @inheritdoc IAltoRewardsOracle
    function updatePrice() external {
        if (lastPriceUpdateTimestamp == 0) revert AltoRewardsOracleNotInitiated();
        if (block.timestamp - lastPriceUpdateTimestamp < priceUpdateCooldownPeriod) {
            revert AltoRewardsOracleTooEarlyToUpdatePrice();
        }

        uint256 oldPrice = cachedPrice;
        cachedPrice = _readUniswapQuote(IN_BASE);
        lastPriceUpdateTimestamp = block.timestamp;

        emit PriceUpdated(block.timestamp, cachedPrice, oldPrice);
    }

    /// @notice Uses Chainlink's value to change Uniswap's rate
    /// @param ratio Value of the last oracle rate of Chainlink
    /// @param quoteAmountUni End quote computed from Uniswap's circuit
    /// @dev We use the last Chainlink rate to correct the value obtained with Uniswap. It may for instance be used
    /// to get a Uniswap price in EUR (ex: ETH -> USDC and we use this to do USDC -> EUR)
    function _changeUniswapNotFinal(uint256 ratio, uint256 quoteAmountUni) internal view returns (uint256) {
        uint256 idxLastPoolCL = circuitChainlink.length - 1;
        (quoteAmountUni,) = _readChainlinkFeed(
            quoteAmountUni,
            circuitChainlink[idxLastPoolCL],
            circuitChainIsMultiplied[idxLastPoolCL],
            chainlinkDecimals[idxLastPoolCL],
            ratio
        );
        return quoteAmountUni;
    }

    /// @notice Internal function to convert an in-currency quote amount to out-currency using only the Uniswap rate
    /// and by correcting it if needed from Chainlink last rate
    /// @param quoteAmount Amount (in the input collateral) to be converted in out-currency using Uniswap (and Chainlink)
    /// at the end of the funnel
    /// @return uniAmount Quote amount in out-currency from the base amount in in-currency
    /// @dev The amount returned is expressed with base `USD_ORACLE_PRICE_PRECISION` (and not the base of the out-currency)
    function _readUniswapQuote(uint256 quoteAmount) internal view returns (uint256 uniAmount) {
        uniAmount = _quoteUniswap(quoteAmount);
        // The current uni rate is in OUT_BASE we want it in MATH_PRECISION to avoid precision loss in _changeUniswapNotFinal function
        uniAmount = FixedPointMath.divideWithPrecisionUp(uniAmount, OUT_BASE);
        if (UNI_FINAL_CURRENCY > 0) {
            uniAmount = _changeUniswapNotFinal(0, uniAmount);
        }
        // The current uniAmount is in MATH_PRECISION. we want our rate to be in USD_ORACLE_PRICE_PRECISION
        uniAmount = FixedPointMath.multiplyWithPrecisionUp(uniAmount, USD_ORACLE_PRICE_PRECISION);
    }

    /// @inheritdoc IAltoRewardsOracle
    function updatePriceUpdateCooldownPeriod(uint256 _priceUpdateCooldownPeriod) external onlyOwner {
        if (priceUpdateCooldownPeriod == _priceUpdateCooldownPeriod) {
            revert AltoRewardsOracleInvalidInput();
        }
        emit PriceUpdateCooldownPeriodUpdated(priceUpdateCooldownPeriod, _priceUpdateCooldownPeriod);
        priceUpdateCooldownPeriod = _priceUpdateCooldownPeriod;
    }
}
