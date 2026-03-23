// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {IOracle} from "@alto/oracles/interfaces/IOracle.sol";
import {ERC4626RatioNode, LinearDiscountNode} from "@alto/oracles/interfaces/IModuleNode.sol";

interface IAltoERC4626RatioLinearDiscountOracleErrors {}

interface IAltoERC4626RatioLinearDiscountOracleEvents {
    /// @notice Emitted when the ERC4626 ratio node is updated
    event SetERC4626RatioNode(ERC4626RatioNode oldERC4626RatioNode, ERC4626RatioNode newERC4626RatioNode);

    /// @notice Emitted when the linear discount node is updated
    event SetLinearDiscountNode(LinearDiscountNode oldLinearDiscountNode, LinearDiscountNode newLinearDiscountNode);
}

interface IAltoERC4626RatioLinearDiscountOracleBase is
    IOracle,
    IAltoERC4626RatioLinearDiscountOracleErrors,
    IAltoERC4626RatioLinearDiscountOracleEvents
{
    /// @notice Updates the ERC4626 ratio node
    /// @param _erc4626RatioNode The new ERC4626 ratio node
    function updateERC4626RatioNode(ERC4626RatioNode memory _erc4626RatioNode) external;

    /// @notice Updates the linear discount node
    /// @param _linearDiscountNode The new linear discount node
    function updateLinearDiscountNode(LinearDiscountNode memory _linearDiscountNode) external;
}

interface IAltoERC4626RatioLinearDiscountOracle is IAltoERC4626RatioLinearDiscountOracleBase {
    /// @notice Gets the ERC4626RatioNode
    /// @return The ERC4626RatioNode
    function erc4626RatioNode() external view returns (ERC4626RatioNode memory);

    /// @notice Gets the LinearDiscountNode
    /// @return The LinearDiscountNode
    function linearDiscountNode() external view returns (LinearDiscountNode memory);
}

interface IAltoERC4626RatioLinearDiscountOracleStaticTypes is IAltoERC4626RatioLinearDiscountOracleBase {
    /// @notice Gets the ERC4626RatioNode
    /// @return initialRatio The initial ratio
    /// @return initialTimestamp The initial timestamp
    /// @return maxYearlyGrowthRatioWad The max yearly growth ratio in WAD
    function erc4626RatioNode()
        external
        view
        returns (uint256 initialRatio, uint256 initialTimestamp, uint256 maxYearlyGrowthRatioWad);

    /// @notice Gets the LinearDiscountNode
    /// @return ptToken The PT token address
    /// @return maturity The maturity timestamp
    /// @return baseDiscountPerYear The base discount rate per year in WAD
    /// @return inDecimals The decimals of the input amount (must match _getRatioOfWrappedAssetToUnderlyingAsset output)
    /// @return outDecimals The decimals of the output price
    function linearDiscountNode()
        external
        view
        returns (address ptToken, uint256 maturity, uint256 baseDiscountPerYear, uint8 inDecimals, uint8 outDecimals);
}
