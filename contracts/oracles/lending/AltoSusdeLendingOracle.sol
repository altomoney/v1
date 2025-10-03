// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.7;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {
    ERC4626RatioNode,
    ChainlinkNode,
    RedstoneNode,
    ChainlinkRedstoneNode
} from "@alto/oracles/interfaces/IModuleNode.sol";
import {MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";
import {ModuleERC4626Ratio} from "@alto/oracles/lending/modules/ModuleERC4626Ratio.sol";
import {ModuleChainlink} from "@alto/oracles/lending/modules/ModuleChainlink.sol";
import {ModuleRedstone} from "@alto/oracles/lending/modules/ModuleRedstone.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {OracleValidation} from "@alto/oracles/lending/libraries/OracleValidation.sol";
import {FixedPointMath} from "@alto/utils/FixedPointMath.sol";
import {ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {
    IAltoSusdeLendingOracleStaticTypes,
    IAltoSusdeLendingOracleBase
} from "@alto/oracles/interfaces/IAltoSusdeLendingOracle.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/// @title AltoSusdeLendingOracle
/// @author Pearl Labs
/// @notice An oracle that gets the price of SUSDE in USD using the ERC4626 ratio of SUSDE to USDE.
/// @dev Uses chainlink and redstone USDE/USD price feed
contract AltoSusdeLendingOracle is
    Ownable2Step,
    ModuleERC4626Ratio,
    ModuleChainlink,
    ModuleRedstone,
    IAltoSusdeLendingOracleStaticTypes
{
    /// @inheritdoc IAltoSusdeLendingOracleStaticTypes
    ERC4626RatioNode public erc4626RatioNode;

    /// @inheritdoc IAltoSusdeLendingOracleStaticTypes
    ChainlinkRedstoneNode public chainlinkRedstoneNode;

    /// @inheritdoc IAltoSusdeLendingOracleBase
    address public immutable SUSDE;

    /// @notice Constructor
    /// @param _owner The owner of the contract
    /// @param _erc4626RatioNode The ERC4626 ratio node
    /// @param _chainlinkRedstoneNode The chainlink and redstone node
    /// @param _susde The address of the SUSDE token
    constructor(
        address _owner,
        ERC4626RatioNode memory _erc4626RatioNode,
        ChainlinkRedstoneNode memory _chainlinkRedstoneNode,
        address _susde
    ) Ownable(_owner) {
        _validateERC4626RatioParams(_erc4626RatioNode);
        _validateChainlinkParams(_chainlinkRedstoneNode.chainlinkNode);
        _validateRedstoneParams(_chainlinkRedstoneNode.redstoneNode);

        erc4626RatioNode = _erc4626RatioNode;
        emit SetERC4626RatioNode(ERC4626RatioNode(0, 0, 0), _erc4626RatioNode);

        if (_chainlinkRedstoneNode.chainlinkWeightWad + _chainlinkRedstoneNode.redstoneWeightWad != MATH_PRECISION) {
            revert AltoSusdeLendingOracleInvalidInput();
        }
        if (
            _chainlinkRedstoneNode.maxAllowedDeviationWad == 0
                || _chainlinkRedstoneNode.maxAllowedDeviationWad > MATH_PRECISION
        ) {
            revert AltoSusdeLendingOracleInvalidInput();
        }

        if (_chainlinkRedstoneNode.chainlinkNode.outDecimals != _chainlinkRedstoneNode.redstoneNode.outDecimals) {
            revert AltoSusdeLendingOracleInvalidInput();
        }

        chainlinkRedstoneNode = _chainlinkRedstoneNode;
        emit SetChainlinkRedstoneNode(
            ChainlinkRedstoneNode(
                ChainlinkNode(AggregatorV3Interface(address(0)), 0, 0, 0, 0),
                RedstoneNode(AggregatorV3Interface(address(0)), 0, 0, 0, 0),
                0,
                0,
                0
            ),
            _chainlinkRedstoneNode
        );

        SUSDE = _susde;
    }

    /// @inheritdoc IAltoSusdeLendingOracleBase
    function getPrice() external view returns (uint256) {
        // gets susde to usde ratio in decimals of SUSDE vault
        uint256 susdeUsdeRatio = IERC4626(SUSDE).convertToAssets(10 ** IERC20Metadata(SUSDE).decimals());

        // caps the ratio to the maximum allowed growth rate in case something goes wrong with the SUSDE vault
        susdeUsdeRatio = readLatestRatio(susdeUsdeRatio, erc4626RatioNode);

        // susdeUsdeRatio is in MATH_PRECISION(i.e. 1e18) decimals
        susdeUsdeRatio = FixedPointMath.divideWithRounding(
            susdeUsdeRatio, MATH_PRECISION, 10 ** IERC20Metadata(SUSDE).decimals(), false
        );

        // gets the price of susde in usde from chainlink and redstone oracle in chainlinkRedstoneNode.chainlinkNode.outDecimals decimals
        uint256 usdePriceChainlink =
            readChainlinkFeed(10 ** chainlinkRedstoneNode.chainlinkNode.inDecimals, chainlinkRedstoneNode.chainlinkNode);
        uint256 usdePriceRedstone =
            readRedstoneFeed(10 ** chainlinkRedstoneNode.redstoneNode.inDecimals, chainlinkRedstoneNode.redstoneNode);
        uint256 usdeUsdPrice;
        if (
            !OracleValidation.isPriceWithinAllowedDeviation(
                usdePriceChainlink, usdePriceRedstone, chainlinkRedstoneNode.maxAllowedDeviationWad
            )
        ) {
            revert AltoSusdeLendingOracleInvalidPrice();
        } else {
            usdeUsdPrice = (
                usdePriceChainlink * chainlinkRedstoneNode.chainlinkWeightWad
                    + usdePriceRedstone * chainlinkRedstoneNode.redstoneWeightWad
            ) / MATH_PRECISION;
        }

        // usdePrice is in MATH_PRECISION(i.e. 1e18) decimals
        usdeUsdPrice = FixedPointMath.divideWithRounding(
            usdeUsdPrice, MATH_PRECISION, 10 ** chainlinkRedstoneNode.chainlinkNode.outDecimals, false
        );

        // susdeUsdPrice is in ORACLE_PRICE_PRECISION(i.e. 1e36) decimals
        // usdeUsdPrice is in MATH_PRECISION(i.e. 1e18) decimals
        // susdeUsdeRatio is in MATH_PRECISION(i.e. 1e18) decimals
        uint256 susdeUsdPrice = susdeUsdeRatio * usdeUsdPrice;
        return susdeUsdPrice;
    }

    /// @inheritdoc IAltoSusdeLendingOracleBase
    function updateERC4626RatioNode(ERC4626RatioNode memory _erc4626RatioNode) external onlyOwner {
        _validateERC4626RatioParams(_erc4626RatioNode);

        emit SetERC4626RatioNode(erc4626RatioNode, _erc4626RatioNode);
        erc4626RatioNode = _erc4626RatioNode;
    }

    /// @inheritdoc IAltoSusdeLendingOracleBase
    function updateChainlinkRedstoneNode(ChainlinkRedstoneNode memory _chainlinkRedstoneNode) external onlyOwner {
        _validateChainlinkParams(_chainlinkRedstoneNode.chainlinkNode);
        _validateRedstoneParams(_chainlinkRedstoneNode.redstoneNode);

        if (_chainlinkRedstoneNode.chainlinkWeightWad + _chainlinkRedstoneNode.redstoneWeightWad != MATH_PRECISION) {
            revert AltoSusdeLendingOracleInvalidInput();
        }
        if (
            _chainlinkRedstoneNode.maxAllowedDeviationWad == 0
                || _chainlinkRedstoneNode.maxAllowedDeviationWad > MATH_PRECISION
        ) {
            revert AltoSusdeLendingOracleInvalidInput();
        }

        if (_chainlinkRedstoneNode.chainlinkNode.outDecimals != _chainlinkRedstoneNode.redstoneNode.outDecimals) {
            revert AltoSusdeLendingOracleInvalidInput();
        }

        emit SetChainlinkRedstoneNode(chainlinkRedstoneNode, _chainlinkRedstoneNode);
        chainlinkRedstoneNode = _chainlinkRedstoneNode;
    }
}
