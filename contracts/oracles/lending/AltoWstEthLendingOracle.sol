// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.7;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ModuleChainlink} from "@alto/oracles/lending/modules/ModuleChainlink.sol";
import {ModuleERC4626Ratio} from "@alto/oracles/lending/modules/ModuleERC4626Ratio.sol";
import {ChainlinkNode, ERC4626RatioNode, ConversionDirection} from "@alto/oracles/interfaces/IModuleNode.sol";
import {MATH_PRECISION, FixedPointMath} from "@alto/utils/FixedPointMath.sol";
import {IWstEth} from "@alto/oracles/interfaces/IWstEth.sol";
import {
    IAltoWstEthLendingOracleStaticTypes,
    IAltoWstEthLendingOracleBase
} from "@alto/oracles/interfaces/IAltoWstEthLendingOracle.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/// @title AltoWstEthLendingOracle
/// @author Pearl Labs
/// @notice Oracle contract that is used to get the price of WSTETH in USD
/// @dev Uses ERC4626Ratio to cap the ratio of wsteth/steth and also uses chainlink ETH/USD feed
/// @dev this contract uses the invariant that stEth and Eth is pegged at 1:1
contract AltoWstEthLendingOracle is
    Ownable2Step,
    ModuleERC4626Ratio,
    ModuleChainlink,
    IAltoWstEthLendingOracleStaticTypes
{
    /// @inheritdoc IAltoWstEthLendingOracleBase
    address public immutable WSTETH;

    /// @inheritdoc IAltoWstEthLendingOracleStaticTypes
    ERC4626RatioNode public erc4626RatioNode;

    /// @inheritdoc IAltoWstEthLendingOracleStaticTypes
    ChainlinkNode public chainlinkNode;

    /// @notice Constructor
    /// @param _owner The owner of the contract
    /// @param _wstEth The address of the WSTETH token
    /// @param _erc4626RatioNode The ERC4626 ratio node configuration
    /// @param _chainlinkNode The chainlink node configuration
    constructor(
        address _owner,
        address _wstEth,
        ERC4626RatioNode memory _erc4626RatioNode,
        ChainlinkNode memory _chainlinkNode
    ) Ownable(_owner) {
        if (_wstEth == address(0)) {
            revert AltoWstEthLendingOracleInvalidInput();
        }
        _validateChainlinkParams(_chainlinkNode);
        _validateERC4626RatioParams(_erc4626RatioNode);

        WSTETH = _wstEth;

        erc4626RatioNode = _erc4626RatioNode;
        emit SetERC4626RatioNode(ERC4626RatioNode(0, 0, 0), _erc4626RatioNode);

        chainlinkNode = _chainlinkNode;
        emit SetChainlinkNode(
            ChainlinkNode(AggregatorV3Interface(address(0)), ConversionDirection.IN_TO_OUT, 0, 0, 0), _chainlinkNode
        );
    }

    /// @inheritdoc IAltoWstEthLendingOracleBase
    function getPrice() external view returns (uint256) {
        // getting the latest ratio of wsteth/steth.
        uint256 stEthToEthRatio = IWstEth(WSTETH).stEthPerToken();

        // the ratio returned may be capped to the maximum allowed growth rate
        stEthToEthRatio = readLatestRatio(stEthToEthRatio, erc4626RatioNode);

        // getting the price of eth in usd from chainlink in chainlinkNode.outDecimals decimals
        return readChainlinkFeed(stEthToEthRatio, chainlinkNode);
    }

    /// @inheritdoc IAltoWstEthLendingOracleBase
    function updateERC4626RatioNode(ERC4626RatioNode memory _erc4626RatioNode) external onlyOwner {
        _validateERC4626RatioParams(_erc4626RatioNode);

        emit SetERC4626RatioNode(erc4626RatioNode, _erc4626RatioNode);
        erc4626RatioNode = _erc4626RatioNode;
    }

    /// @inheritdoc IAltoWstEthLendingOracleBase
    function updateChainlinkNode(ChainlinkNode memory _chainlinkNode) external onlyOwner {
        _validateChainlinkParams(_chainlinkNode);

        emit SetChainlinkNode(chainlinkNode, _chainlinkNode);
        chainlinkNode = _chainlinkNode;
    }
}
