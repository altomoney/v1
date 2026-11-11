// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {IConvexBooster} from "@alto/positions/interfaces/IConvex.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MockConvexRewardPool} from "./MockConvexRewardPool.sol";

/// @notice Convex booster mock that forwards LP to the reward pool.
contract MockConvexBooster is IConvexBooster {
    using SafeERC20 for IERC20;

    MockConvexRewardPool public rewardPool;
    IERC20 public lpToken;
    bool public shutdown;

    uint256 public depositCallCount;
    uint256 public lastDepositAmount;

    constructor(address rewardPool_, address lpToken_) {
        rewardPool = MockConvexRewardPool(rewardPool_);
        lpToken = IERC20(lpToken_);
    }

    function setShutdown(bool shutdown_) external {
        shutdown = shutdown_;
    }

    function deposit(uint256, uint256 amount, bool) external returns (bool) {
        depositCallCount++;
        lastDepositAmount = amount;
        lpToken.safeTransferFrom(msg.sender, address(this), amount);
        rewardPool.stake(msg.sender, amount);
        return true;
    }

    function poolInfo(uint256)
        external
        view
        returns (address lptoken, address token, address gauge, address crvRewards, address stash, bool shutdown_)
    {
        return (address(lpToken), address(0), address(0), address(rewardPool), address(0), shutdown);
    }
}
