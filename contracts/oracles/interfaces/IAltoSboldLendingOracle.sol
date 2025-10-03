// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import {
    ERC4626RatioNode,
    ChainlinkNode,
    RedstoneNode,
    CurveNode,
    ChainlinkRedstoneNode
} from "@alto/oracles/interfaces/IModuleNode.sol";
import {IOracle} from "@alto/oracles/interfaces/IOracle.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {ICurvePool} from "@alto/oracles/interfaces/ICurvePool.sol";

interface IAltoSboldLendingOracleErrors {
    /// @notice Thrown when the input is invalid
    error AltoSboldLendingOracleInvalidInput();

    /// @notice Thrown when the price is invalid
    error AltoSboldLendingOracleInvalidPrice();

    /// @notice Thrown when the liquidity pool is insufficient
    error AltoSboldLendingOracleInsufficientLiquidity();
}

interface IAltoSboldLendingOracleEvents {
    /// @notice Event emitted when the ERC4626 ratio node is updated
    event SetERC4626RatioNode(ERC4626RatioNode oldERC4626RatioNode, ERC4626RatioNode newERC4626RatioNode);

    /// @notice Event emitted when the curve node is updated
    event SetCurveNode(CurveNode oldCurveNode, CurveNode newCurveNode);

    /// @notice Event emitted when the chainlink and redstone node is updated
    event SetChainlinkRedstoneNode(
        ChainlinkRedstoneNode oldChainlinkRedstoneNode, ChainlinkRedstoneNode newChainlinkRedstoneNode
    );

    /// @notice Event emitted when the minimum allowed liquidity pool is updated
    event SetMinAllowedLiquidityPool(uint256[] oldMinAllowedLiquidityPool, uint256[] newMinAllowedLiquidityPool);
}

interface IAltoSboldLendingOracleBase is IOracle, IAltoSboldLendingOracleErrors, IAltoSboldLendingOracleEvents {
    /// @notice The address of the SBOLD token
    /// @return Returns the address of the SBOLD token
    function SBOLD() external view returns (address);

    /// @notice Gets the price of SBOLD in USD in ORACLE_PRICE_PRECISION(i.e. 1e36)
    /// @dev uses the SBOLD -> BOLD fundamental ratio. Uses ERC4626 ratio to cap the ratio of SBOLD/BOLD at max allowed ratio
    /// @dev uses the curve pool to get the price of BOLD in USDC
    /// @dev uses the chainlink and redstone prices to get the price of USDC in USD
    /// @return The price of SBOLD in USD in ORACLE_PRICE_PRECISION(i.e. 1e36)
    function getPrice() external view returns (uint256);

    /// @notice Updates the ERC4626 ratio node
    /// @param _erc4626RatioNode The new ERC4626 ratio node
    function updateERC4626RatioNode(ERC4626RatioNode memory _erc4626RatioNode) external;

    /// @notice Updates the curve node
    /// @param _curveNode The new curve node
    function updateCurveNode(CurveNode memory _curveNode) external;

    /// @notice Updates the chainlink node
    /// @param _chainlinkRedstoneNode The new chainlink and redstone node
    function updateChainlinkRedstoneNode(ChainlinkRedstoneNode memory _chainlinkRedstoneNode) external;
}

interface IAltoSboldLendingOracle is IAltoSboldLendingOracleBase {
    /// @notice Gets the ERC4626 ratio node
    /// @return The ERC4626 ratio node
    function erc4626RatioNode() external view returns (ERC4626RatioNode memory);

    /// @notice Gets the curve node
    /// @return The curve node
    function curveNode() external view returns (CurveNode memory);

    /// @notice Gets the chainlink and redstone node
    /// @return The chainlink and redstone node
    function chainlinkRedstoneNode() external view returns (ChainlinkRedstoneNode memory);

    /// @notice Gets the minimum allowed liquidity pool
    /// @return The minimum allowed liquidity pool
    function minAllowedLiquidityPool() external view returns (uint256[] memory);
}

interface IAltoSboldLendingOracleStaticTypes is IAltoSboldLendingOracleBase {
    /// @notice Gets the ERC4626 ratio node
    /// @return The ERC4626 ratio node
    function erc4626RatioNode() external view returns (uint256, uint256, uint256);

    /// @notice Gets the curve node
    /// @return The curve node
    function curveNode() external view returns (ICurvePool, uint256, uint8, uint8, uint8, uint256, uint32);

    /// @notice Gets the chainlink and redstone node
    /// @return The chainlink and redstone node
    function chainlinkRedstoneNode()
        external
        view
        returns (ChainlinkNode memory, RedstoneNode memory, uint256, uint256, uint256);

    /// @notice Gets the minimum allowed liquidity pool for asset at index
    /// @return The minimum allowed liquidity pool for asset at index
    function minAllowedLiquidityPool(uint256 index) external view returns (uint256);
}
