// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.7;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ModuleChainlink} from "@alto/oracles/lending/modules/ModuleChainlink.sol";
import {ModuleRedstone} from "@alto/oracles/lending/modules/ModuleRedstone.sol";
import {IOracle, ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {OracleNode, ChainlinkNode, RedstoneNode, OracleType} from "@alto/oracles/interfaces/IAltoLendingOracle.sol";
import {IAltoWethLendingOracleErrors} from "@alto/oracles/interfaces/IAltoLendingOracle.sol";
import {MATH_PRECISION, FixedPointMath} from "@alto/utils/FixedPointMath.sol";

contract AltoWethLendingOracle is Ownable2Step, ModuleChainlink, ModuleRedstone, IOracle {
    uint256 public chainlinkWeight;
    uint256 public redstoneWeight;
    uint256 public maxAllowedDeviation;
    OracleNode[] public oracleNodes;

    constructor(
        address _owner,
        uint256 _chainlinkWeight,
        uint256 _redstoneWeight,
        uint256 _maxAllowedDeviation,
        OracleNode[] memory _oracleNodes
    ) Ownable(_owner) {
        if (_chainlinkWeight + _redstoneWeight != MATH_PRECISION) {
            revert IAltoWethLendingOracleErrors.AltoWethLendingOracleInvalidInput();
        }
        if (_maxAllowedDeviation == 0 || _maxAllowedDeviation > MATH_PRECISION) {
            revert IAltoWethLendingOracleErrors.AltoWethLendingOracleInvalidInput();
        }
        if (_oracleNodes.length != 2) {
            revert IAltoWethLendingOracleErrors.AltoWethLendingOracleInvalidInput();
        }
        if (_oracleNodes[0].oracleType != OracleType.CHAINLINK || _oracleNodes[1].oracleType != OracleType.REDSTONE) {
            revert IAltoWethLendingOracleErrors.AltoWethLendingOracleInvalidInput();
        }
        chainlinkWeight = _chainlinkWeight;
        redstoneWeight = _redstoneWeight;
        maxAllowedDeviation = _maxAllowedDeviation;
        for (uint256 i = 0; i < _oracleNodes.length; i++) {
            oracleNodes.push(_oracleNodes[i]);
        }
    }

    function getPrice() external view returns (uint256) {
        ChainlinkNode memory chainlinkNode = abi.decode(oracleNodes[0].data, (ChainlinkNode));
        RedstoneNode memory redstoneNode = abi.decode(oracleNodes[1].data, (RedstoneNode));

        if (
            chainlinkNode.inDecimals != redstoneNode.inDecimals || chainlinkNode.outDecimals != redstoneNode.outDecimals
        ) {
            revert IAltoWethLendingOracleErrors.AltoWethLendingOracleInvalidInput();
        }

        uint256 chainlinkPrice = readChainlinkFeed(
            1e18,
            chainlinkNode.feed,
            chainlinkNode.multiplied,
            chainlinkNode.stalePeriod,
            chainlinkNode.inDecimals,
            chainlinkNode.outDecimals
        );
        uint256 redstonePrice = readRedstoneFeed(
            1e18,
            redstoneNode.feed,
            redstoneNode.multiplied,
            redstoneNode.stalePeriod,
            redstoneNode.inDecimals,
            redstoneNode.outDecimals
        );
        uint256 price;
        if (!_isPriceWithinAllowedDeviation(chainlinkPrice, redstonePrice)) {
            price = chainlinkPrice;
        } else {
            price = (chainlinkPrice * chainlinkWeight + redstonePrice * redstoneWeight) / MATH_PRECISION;
        }
        price = FixedPointMath.divideWithRounding(price, ORACLE_PRICE_PRECISION, 10 ** chainlinkNode.outDecimals, false);
        return price;
    }

    function _isPriceWithinAllowedDeviation(uint256 _chainlinkPrice, uint256 _redstonePrice)
        internal
        view
        returns (bool)
    {
        uint256 deviation;
        if (_chainlinkPrice > _redstonePrice) {
            // using the minimum of two as denominator in deviation so that we don't underestimate the deviation and revert if there isn't enough confidence in price
            deviation = FixedPointMath.divideWithPrecisionUp(_chainlinkPrice - _redstonePrice, _redstonePrice);
        } else {
            deviation = FixedPointMath.divideWithPrecisionUp(_redstonePrice - _chainlinkPrice, _chainlinkPrice);
        }
        return deviation <= maxAllowedDeviation;
    }

    function updateWeights(uint256 _chainlinkWeight, uint256 _redstoneWeight) external onlyOwner {
        if (_chainlinkWeight + _redstoneWeight != MATH_PRECISION) {
            revert IAltoWethLendingOracleErrors.AltoWethLendingOracleInvalidInput();
        }
        chainlinkWeight = _chainlinkWeight;
        redstoneWeight = _redstoneWeight;
    }

    function updateMaxAllowedDeviation(uint256 _maxAllowedDeviation) external onlyOwner {
        if (_maxAllowedDeviation == 0 || _maxAllowedDeviation > MATH_PRECISION) {
            revert IAltoWethLendingOracleErrors.AltoWethLendingOracleInvalidInput();
        }
        maxAllowedDeviation = _maxAllowedDeviation;
    }
}
