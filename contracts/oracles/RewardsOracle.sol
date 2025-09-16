// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.7;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

import {ModuleChainlinkMulti} from "@alto/oracles/modules/ModuleChainlinkMulti.sol";
import {ModuleUniswapMulti} from "@alto/oracles/modules/ModuleUniswapMulti.sol";
import {IRewardsOracle} from "@alto/oracles/interfaces/IRewardsOracle.sol";
import {USD_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IUsdOracle.sol";
import {FixedPointMath, MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";

/// @title RewardsOracle
/// @author Pearl Labs
/// @author Adapted from Angle Core (https://github.com/AngleProtocol/angle-core)
/// @notice Oracle contract, one contract is deployed per collateral/stablecoin pair
/// @dev This contract concerns an oracle that only uses both Chainlink and Uniswap for multiple pools
/// @dev This is going to be used for like ALTO/USD oracles
/// @dev A rate gives the price of the out-currency with respect to the in-currency in base `BASE`. For instance
/// if the out-currency is ALTO worth 10 USD and BASE is 10**8, then the rate ALTO-USD is 10**9
contract RewardsOracle is Ownable2Step, ModuleChainlinkMulti, ModuleUniswapMulti, IRewardsOracle {
    /// @notice Base used for computation
    uint256 public constant BASE = MATH_PRECISION;
    /// @notice Unit of the in-currency
    uint256 public immutable inBase;

    /// @notice Unit out Uniswap currency
    uint256 public immutable outBase;

    /// @notice Whether the final rate obtained with Uniswap should be multiplied to last rate from Chainlink
    uint8 public immutable uniFinalCurrency;

    /// @notice Timestamp when this oracle was last updated to return the new price
    uint256 public lastUpdateTimestamp;

    /// @notice Initial price of the asset between timestamp when twap period is started and when price is updated
    uint256 public immutable initialPrice;

    /// @notice Cached price of the asset to be returned by getPrice function
    uint256 public cachedPrice;

    /// @notice Description of the oracle
    bytes32 public description;

    /// @dev When deploying this contract, it is important to check in the case where Uniswap circuit is not final whether
    /// Chainlink and Uniswap circuits are compatible. If Chainlink is UNI-WBTC and WBTC-USD and Uniswap is just UNI-WETH,
    /// then Chainlink cannot be the final circuit
    constructor(RewardsOracleInitParams memory _initParams)
        ModuleUniswapMulti(
            _initParams.circuitUniswap,
            _initParams.circuitUniIsMultiplied,
            _initParams.twapPeriod,
            _initParams.observationLength
        )
        ModuleChainlinkMulti(_initParams.circuitChainlink, _initParams.circuitChainIsMultiplied, _initParams.stalePeriod)
        Ownable(_initParams.owner)
    {
        if (_initParams.addressInAndOutUni.length != 2) revert InvalidInput();
        if (_initParams.owner == address(0)) revert InvalidInput();
        // Using the tokens' metadata to get the in and out currencies decimals
        IERC20Metadata inCur = IERC20Metadata(_initParams.addressInAndOutUni[0]);
        IERC20Metadata outCur = IERC20Metadata(_initParams.addressInAndOutUni[1]);
        inBase = 10 ** (inCur.decimals());
        outBase = 10 ** (outCur.decimals());

        initialPrice = _initParams.initialPrice;
        uniFinalCurrency = _initParams.uniFinalCurrency;
        description = _initParams.description;
    }

    /// @notice Gets the price of the asset in USD_ORACLE_PRICE_PRECISION
    /// @return The price of the asset in USD_ORACLE_PRICE_PRECISION
    function getPrice() external view override returns (uint256) {
        if (lastUpdateTimestamp == 0) revert NotInitiated();
        return cachedPrice;
    }

    /// @notice Starts the TWAP period
    /// @dev This function will be called after Uniswap pool has been created
    /// @dev getPrice function will return the cached price until the price is updated through updatePrice function
    function startTwapPeriod() external onlyOwner {
        if (lastUpdateTimestamp != 0) revert AlreadyStartedTwapPeriod();
        lastUpdateTimestamp = block.timestamp;
        cachedPrice = initialPrice;

        emit PriceUpdated(block.timestamp, cachedPrice, 0);
    }

    /// @notice Updates the price of the asset based on the Uniswap V3 twap period
    /// @dev This function will be called periodically to update the price of the asset
    /// @dev This function will revert if the twap period has not been passed since the last update
    function updatePrice() external {
        if (lastUpdateTimestamp == 0) revert NotInitiated();
        if (block.timestamp - lastUpdateTimestamp < twapPeriod) revert TooEarlyToUpdatePrice();

        uint256 oldPrice = cachedPrice;
        cachedPrice = _readUniswapQuote(inBase);
        lastUpdateTimestamp = block.timestamp;

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
    /// @dev The amount returned is expressed with base `BASE` (and not the base of the out-currency)
    function _readUniswapQuote(uint256 quoteAmount) internal view returns (uint256 uniAmount) {
        uniAmount = _quoteUniswap(quoteAmount);
        // The current uni rate is in outBase we want it in BASE to avoid precision loss in _changeUniswapNotFinal function
        uniAmount = FixedPointMath.divideWithRounding(uniAmount, BASE, outBase, true);
        if (uniFinalCurrency > 0) {
            uniAmount = _changeUniswapNotFinal(0, uniAmount);
        }
        // The current uniAmount is in BASE. we want our rate to be in USD_ORACLE_PRICE_PRECISION
        uniAmount = FixedPointMath.divideWithRounding(uniAmount, USD_ORACLE_PRICE_PRECISION, BASE, true);
    }
}
