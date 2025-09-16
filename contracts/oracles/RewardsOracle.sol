// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.7;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {ModuleChainlinkMulti} from "@alto/oracles/modules/ModuleChainlinkMulti.sol";
import {ModuleUniswapMulti} from "@alto/oracles/modules/ModuleUniswapMulti.sol";
import {IUsdOracle, USD_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IUsdOracle.sol";

/// @title RewardsOracle
/// @author Pearl Labs
/// @author Adapted from Angle Core (https://github.com/AngleProtocol/angle-core)
/// @notice Oracle contract, one contract is deployed per collateral/stablecoin pair
/// @dev This contract concerns an oracle that only uses both Chainlink and Uniswap for multiple pools
/// @dev This is going to be used for like ALTO/USD oracles
/// @dev A rate gives the price of the out-currency with respect to the in-currency in base `BASE`. For instance
/// if the out-currency is ALTO worth 10 USD and BASE is 10**8, then the rate ALTO-USD is 10**9
contract RewardsOracle is ModuleChainlinkMulti, ModuleUniswapMulti, IUsdOracle {
    /// @notice Base used for computation
    uint256 public constant BASE = 10 ** 18;
    /// @notice Unit of the in-currency
    uint256 public immutable inBase;

    /// @notice Unit out Uniswap currency
    uint256 public immutable outBase;

    /// @notice Whether the final rate obtained with Uniswap should be multiplied to last rate from Chainlink
    uint8 public immutable uniFinalCurrency;

    bytes32 public description;

    /// @notice Constructor for an oracle using both Uniswap and Chainlink with multiple pools to read from
    /// @param addressInAndOutUni List of 2 addresses representing the in-currency address and the out-currency address
    /// @param _circuitUniswap Path of the Uniswap pools
    /// @param _circuitUniIsMultiplied Whether we should multiply or divide by this rate in the path
    /// @param _twapPeriod Time weighted average window for all Uniswap pools
    /// @param observationLength Number of observations that each pool should have stored
    /// @param _uniFinalCurrency Whether we need to use the last Chainlink oracle to convert to another
    /// currency / asset (Forex for instance)
    /// @param _circuitChainlink Chainlink pool addresses put in order
    /// @param _circuitChainIsMultiplied Whether we should multiply or divide by this rate
    /// @param _owner The initial owner of the contract.
    /// @param stalePeriod The stale period for the Chainlink oracle
    /// @param _description Description of the assets concerned by the oracle
    /// @dev When deploying this contract, it is important to check in the case where Uniswap circuit is not final whether
    /// Chainlink and Uniswap circuits are compatible. If Chainlink is UNI-WBTC and WBTC-USD and Uniswap is just UNI-WETH,
    /// then Chainlink cannot be the final circuit
    constructor(
        address[] memory addressInAndOutUni,
        IUniswapV3Pool[] memory _circuitUniswap,
        uint8[] memory _circuitUniIsMultiplied,
        uint32 _twapPeriod,
        uint16 observationLength,
        uint8 _uniFinalCurrency,
        address[] memory _circuitChainlink,
        uint8[] memory _circuitChainIsMultiplied,
        address _owner,
        uint32 stalePeriod,
        bytes32 _description
    )
        ModuleUniswapMulti(_circuitUniswap, _circuitUniIsMultiplied, _twapPeriod, observationLength)
        ModuleChainlinkMulti(_circuitChainlink, _circuitChainIsMultiplied, stalePeriod)
        Ownable(_owner)
    {
        if (addressInAndOutUni.length != 2) revert InvalidInput();
        if (_owner == address(0)) revert InvalidInput();
        // Using the tokens' metadata to get the in and out currencies decimals
        IERC20Metadata inCur = IERC20Metadata(addressInAndOutUni[0]);
        IERC20Metadata outCur = IERC20Metadata(addressInAndOutUni[1]);
        inBase = 10 ** (inCur.decimals());
        outBase = 10 ** (outCur.decimals());

        uniFinalCurrency = _uniFinalCurrency;
        description = _description;
    }

    /// @notice Gets the price of the asset in USD_ORACLE_PRICE_PRECISION
    /// @return The price of the asset in USD_ORACLE_PRICE_PRECISION
    function getPrice() external view override returns (uint256) {
        return _readUniswapQuote(inBase);
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
        uniAmount = (uniAmount * BASE) / outBase;
        if (uniFinalCurrency > 0) {
            uniAmount = _changeUniswapNotFinal(0, uniAmount);
        }
        // The current uniAmount is in BASE. we want our rate to be in USD_ORACLE_PRICE_PRECISION
        uniAmount = uniAmount * USD_ORACLE_PRICE_PRECISION / BASE;
    }
}
