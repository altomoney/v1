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
import {ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {
    IAltoSusdeLendingOracleStaticTypes,
    IAltoSusdeLendingOracleBase
} from "@alto/oracles/interfaces/IAltoSusdeLendingOracle.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/// @title AltoSusdeLendingOracle
/// @author Pearl Labs
/// @notice An oracle that gets the price of SUSDE in USD using the ERC4626 ratio of SUSDE to USDE.
/// @dev Uses chainlink  USDE/USD price feed
contract AltoSusdeLendingOracle is
    Ownable2Step,
    ModuleERC4626Ratio,
    ModuleChainlink,
    IAltoSusdeLendingOracleStaticTypes
{
    /// @inheritdoc IAltoSusdeLendingOracleStaticTypes
    ERC4626RatioNode public erc4626RatioNode;

    /// @inheritdoc IAltoSusdeLendingOracleStaticTypes
    ChainlinkNode public chainlinkNode;

    /// @inheritdoc IAltoSusdeLendingOracleBase
    address public immutable SUSDE;

    /// @notice Constructor
    /// @param _owner The owner of the contract
    /// @param _erc4626RatioNode The ERC4626 ratio node
    /// @param _chainlinkNode The chainlink node
    /// @param _susde The address of the SUSDE token
    constructor(
        address _owner,
        ERC4626RatioNode memory _erc4626RatioNode,
        ChainlinkNode memory _chainlinkNode,
        address _susde
    ) Ownable(_owner) {
        _validateERC4626RatioParams(_erc4626RatioNode);
        _validateChainlinkParams(_chainlinkNode);

        if (_susde == address(0)) {
            revert AltoSusdeLendingOracleInvalidInput();
        }

        erc4626RatioNode = _erc4626RatioNode;
        emit SetERC4626RatioNode(ERC4626RatioNode(0, 0, 0), _erc4626RatioNode);

        chainlinkNode = _chainlinkNode;
        emit SetChainlinkNode(ChainlinkNode(AggregatorV3Interface(address(0)), 0, 0, 0, 0), _chainlinkNode);

        SUSDE = _susde;
    }

    /// @inheritdoc IAltoSusdeLendingOracleBase
    function getPrice() external view returns (uint256) {
        // gets susde to usde ratio in decimals of SUSDE vault
        uint256 susdeUsdeRatio = IERC4626(SUSDE).convertToAssets(10 ** IERC20Metadata(SUSDE).decimals());

        // caps the ratio to the maximum allowed growth rate in case something goes wrong with the SUSDE vault
        susdeUsdeRatio = readLatestRatio(susdeUsdeRatio, erc4626RatioNode);

        // gets the price of susde in usde from chainlink in chainlinkNode.outDecimals decimals
        return readChainlinkFeed(susdeUsdeRatio, chainlinkNode);
    }

    /// @inheritdoc IAltoSusdeLendingOracleBase
    function updateERC4626RatioNode(ERC4626RatioNode memory _erc4626RatioNode) external onlyOwner {
        _validateERC4626RatioParams(_erc4626RatioNode);

        emit SetERC4626RatioNode(erc4626RatioNode, _erc4626RatioNode);
        erc4626RatioNode = _erc4626RatioNode;
    }

    /// @inheritdoc IAltoSusdeLendingOracleBase
    function updateChainlinkNode(ChainlinkNode memory _chainlinkNode) external onlyOwner {
        _validateChainlinkParams(_chainlinkNode);

        emit SetChainlinkNode(chainlinkNode, _chainlinkNode);
        chainlinkNode = _chainlinkNode;
    }
}
