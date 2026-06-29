// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {ICurveStablePool} from "@alto/positions/interfaces/ICurveStablePool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20MockMintable} from "@alto-test/helpers/ERC20MockMintable.sol";

/// @notice Curve pool mock that mints LP 1:1 with deposited token sums.
/// @dev The pool contract is also the LP token, matching real Curve stable pools.
contract MockCurvePool is ICurveStablePool, ERC20MockMintable {
    using SafeERC20 for IERC20;

    error MockCurvePoolMinLpNotMet(uint256 minMintAmount, uint256 lpMinted);

    IERC20 public immutable token0;
    IERC20 public immutable token1;

    uint256 public addLiquidityCallCount;
    uint256 public removeLiquidityCallCount;
    uint256 public lastLpMinted;
    uint256 public lastLpRemoved;

    /// @notice When enabled, `add_liquidity` returns `lpMintOverride` instead of the deposited sum.
    uint256 public lpMintOverride;
    bool public useLpMintOverride;
    uint256 public nCoins = 2;

    constructor(address token0_, address token1_) ERC20MockMintable("Curve LP", "cLP") {
        token0 = IERC20(token0_);
        token1 = IERC20(token1_);
    }

    function setLpMintOverride(uint256 lpMintOverride_, bool enabled_) external {
        lpMintOverride = lpMintOverride_;
        useLpMintOverride = enabled_;
    }

    function setNCoins(uint256 nCoins_) external {
        nCoins = nCoins_;
    }

    function coins(uint256 i) external view returns (address) {
        return i == 0 ? address(token0) : address(token1);
    }

    function N_COINS() external view returns (uint256) {
        return nCoins;
    }

    function add_liquidity(uint256[] calldata amounts, uint256 minMintAmount, address receiver)
        external
        returns (uint256)
    {
        require(amounts.length == 2, "MockCurvePool: invalid amounts length");
        addLiquidityCallCount++;
        if (amounts[0] > 0) token0.safeTransferFrom(msg.sender, address(this), amounts[0]);
        if (amounts[1] > 0) token1.safeTransferFrom(msg.sender, address(this), amounts[1]);

        uint256 lpMinted = useLpMintOverride ? lpMintOverride : amounts[0] + amounts[1];
        if (lpMinted < minMintAmount) revert MockCurvePoolMinLpNotMet(minMintAmount, lpMinted);

        lastLpMinted = lpMinted;
        _mint(receiver, lpMinted);
        return lpMinted;
    }

    function remove_liquidity(uint256 amount, uint256[] calldata)
        external
        returns (uint256[] memory received)
    {
        removeLiquidityCallCount++;
        lastLpRemoved = amount;
        _burn(msg.sender, amount);

        uint256 half = amount / 2;
        received = new uint256[](2);
        received[0] = half;
        received[1] = amount - half;
        if (received[0] > 0) ERC20MockMintable(address(token0)).mint(msg.sender, received[0]);
        if (received[1] > 0) ERC20MockMintable(address(token1)).mint(msg.sender, received[1]);
    }
}
