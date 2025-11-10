// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.7;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ERC4626RatioNode, ChainlinkNode} from "@alto/oracles/interfaces/IModuleNode.sol";
import {MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";
import {ModuleERC4626Ratio} from "@alto/oracles/lending/modules/ModuleERC4626Ratio.sol";
import {ModuleChainlink} from "@alto/oracles/lending/modules/ModuleChainlink.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {FixedPointMath} from "@alto/utils/FixedPointMath.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {
    IAltoRethLendingOracleStaticTypes,
    IAltoRethLendingOracleBase
} from "@alto/oracles/interfaces/IAltoRethLendingOracle.sol";
import {IReth} from "@alto/oracles/interfaces/IReth.sol";

/// @title AltoRethLendingOracle
/// @author Pearl Labs
/// @notice An oracle that gets the price of RETH in USD using the ERC4626 ratio of RETH to ETH and chainlink ETH/USD price feed
contract AltoRethLendingOracle is Ownable2Step, ModuleERC4626Ratio, ModuleChainlink, IAltoRethLendingOracleStaticTypes {
    /// @inheritdoc IAltoRethLendingOracleStaticTypes
    ERC4626RatioNode public erc4626RatioNode;

    /// @inheritdoc IAltoRethLendingOracleStaticTypes
    ChainlinkNode public chainlinkNode;

    /// @inheritdoc IAltoRethLendingOracleBase
    address public immutable RETH;

    /// @notice Constructor
    /// @param _owner The owner of the contract
    /// @param _erc4626RatioNode The ERC4626 ratio node
    /// @param _chainlinkNode The chainlink node
    /// @param _reth The address of the RETH token
    constructor(
        address _owner,
        ERC4626RatioNode memory _erc4626RatioNode,
        ChainlinkNode memory _chainlinkNode,
        address _reth
    ) Ownable(_owner) {
        _validateERC4626RatioParams(_erc4626RatioNode);
        _validateChainlinkParams(_chainlinkNode);

        if (_reth == address(0)) {
            revert AltoRethLendingOracleInvalidInput();
        }

        erc4626RatioNode = _erc4626RatioNode;
        emit SetERC4626RatioNode(ERC4626RatioNode(0, 0, 0), _erc4626RatioNode);

        chainlinkNode = _chainlinkNode;
        emit SetChainlinkNode(ChainlinkNode(AggregatorV3Interface(address(0)), 0, 0, 0, 0), _chainlinkNode);

        RETH = _reth;
    }

    /// @inheritdoc IAltoRethLendingOracleBase
    function getPrice() external view returns (uint256) {
        // gets the ratio of RETH to ETH in 18 decimals
        uint256 rETHToETHRatio = IReth(RETH).getExchangeRate();

        // the ratio returned may be capped to the maximum allowed growth rate
        rETHToETHRatio = readLatestRatio(rETHToETHRatio, erc4626RatioNode);

        // gets the price of ETH in USD from chainlink in chainlinkNode.outDecimals decimals
        return readChainlinkFeed(rETHToETHRatio, chainlinkNode);
    }

    /// @inheritdoc IAltoRethLendingOracleBase
    function updateERC4626RatioNode(ERC4626RatioNode memory _erc4626RatioNode) external onlyOwner {
        _validateERC4626RatioParams(_erc4626RatioNode);

        emit SetERC4626RatioNode(erc4626RatioNode, _erc4626RatioNode);
        erc4626RatioNode = _erc4626RatioNode;
    }

    /// @inheritdoc IAltoRethLendingOracleBase
    function updateChainlinkNode(ChainlinkNode memory _chainlinkNode) external onlyOwner {
        _validateChainlinkParams(_chainlinkNode);

        emit SetChainlinkNode(chainlinkNode, _chainlinkNode);
        chainlinkNode = _chainlinkNode;
    }
}
