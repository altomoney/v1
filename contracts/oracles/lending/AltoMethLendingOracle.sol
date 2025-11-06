// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.7;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ModuleChainlink} from "@alto/oracles/lending/modules/ModuleChainlink.sol";
import {ModuleERC4626Ratio} from "@alto/oracles/lending/modules/ModuleERC4626Ratio.sol";
import {ChainlinkNode, ERC4626RatioNode, ConversionDirection} from "@alto/oracles/interfaces/IModuleNode.sol";
import {MATH_PRECISION, FixedPointMath} from "@alto/utils/FixedPointMath.sol";
import {IMethStaking} from "@alto/oracles/interfaces/IMethStaking.sol";
import {
    IAltoMethLendingOracleStaticTypes,
    IAltoMethLendingOracleBase
} from "@alto/oracles/interfaces/IAltoMethLendingOracle.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/// @title AltoMethLendingOracle
/// @author Pearl Labs
/// @notice Oracle contract that is used to get the price of mETH in USD in ORACLE_PRICE_PRECISION(i.e. 1e36)
/// @dev Uses the ERC4626 ratio to cap the ratio of mETH to ETH and also uses chainlink ETH/USD price feed
contract AltoMethLendingOracle is Ownable2Step, ModuleChainlink, ModuleERC4626Ratio, IAltoMethLendingOracleStaticTypes {
    /// @inheritdoc IAltoMethLendingOracleBase
    address public immutable METH_STAKING;

    /// @inheritdoc IAltoMethLendingOracleStaticTypes
    ERC4626RatioNode public erc4626RatioNode;

    /// @inheritdoc IAltoMethLendingOracleStaticTypes
    ChainlinkNode public chainlinkNode;

    /// @notice Constructor
    /// @param _owner The owner of the contract
    /// @param _methStaking The address of the mETH Staking contract
    /// @param _erc4626RatioNode The ERC4626 ratio node configuration
    /// @param _chainlinkNode The chainlink node configuration
    constructor(
        address _owner,
        address _methStaking,
        ERC4626RatioNode memory _erc4626RatioNode,
        ChainlinkNode memory _chainlinkNode
    ) Ownable(_owner) {
        if (_methStaking == address(0)) {
            revert AltoMethLendingOracleInvalidInput();
        }
        _validateChainlinkParams(_chainlinkNode);
        _validateERC4626RatioParams(_erc4626RatioNode);

        METH_STAKING = _methStaking;

        erc4626RatioNode = _erc4626RatioNode;
        emit SetERC4626RatioNode(ERC4626RatioNode(0, 0, 0), _erc4626RatioNode);

        chainlinkNode = _chainlinkNode;
        emit SetChainlinkNode(
            ChainlinkNode(AggregatorV3Interface(address(0)), ConversionDirection.IN_TO_OUT, 0, 0, 0), _chainlinkNode
        );
    }

    /// @inheritdoc IAltoMethLendingOracleBase
    function getPrice() external view returns (uint256) {
        // getting the latest ratio of mETH to ETH.
        uint256 mETHToETHRatio = IMethStaking(METH_STAKING).mETHToETH(1 ether);

        // the ratio returned may be capped to the maximum allowed growth rate
        mETHToETHRatio = readLatestRatio(mETHToETHRatio, erc4626RatioNode);

        // getting the price of eth in usd from chainlink in chainlinkNode.outDecimals decimals
        return readChainlinkFeed(mETHToETHRatio, chainlinkNode);
    }

    /// @inheritdoc IAltoMethLendingOracleBase
    function updateERC4626RatioNode(ERC4626RatioNode memory _erc4626RatioNode) external onlyOwner {
        _validateERC4626RatioParams(_erc4626RatioNode);

        emit SetERC4626RatioNode(erc4626RatioNode, _erc4626RatioNode);
        erc4626RatioNode = _erc4626RatioNode;
    }

    /// @inheritdoc IAltoMethLendingOracleBase
    function updateChainlinkNode(ChainlinkNode memory _chainlinkNode) external onlyOwner {
        _validateChainlinkParams(_chainlinkNode);

        emit SetChainlinkNode(chainlinkNode, _chainlinkNode);
        chainlinkNode = _chainlinkNode;
    }
}
