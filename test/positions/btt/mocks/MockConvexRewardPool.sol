// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {IConvexRewardPool} from "@alto/positions/interfaces/IConvex.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20MockMintable} from "@alto-test/helpers/ERC20MockMintable.sol";

/// @notice Convex reward pool mock tracking staked balances per account.
contract MockConvexRewardPool is IConvexRewardPool {
    using SafeERC20 for IERC20;

    IERC20 public lpToken;
    IERC20 public crv;
    IERC20 public cvx;

    uint256 public withdrawCallCount;
    uint256 public claimRewardsCallCount;
    uint256 public lastWithdrawAmount;
    bool public lastWithdrawClaimRewards;

    mapping(address => uint256) internal stakedBalance;

    constructor(address lpToken_, address crv_, address cvx_) {
        lpToken = IERC20(lpToken_);
        crv = IERC20(crv_);
        cvx = IERC20(cvx_);
    }

    function stake(address account, uint256 amount) external {
        stakedBalance[account] += amount;
    }

    function balanceOf(address account) external view returns (uint256) {
        return stakedBalance[account];
    }

    function withdrawAndUnwrap(uint256 amount, bool claim) external returns (bool) {
        withdrawCallCount++;
        lastWithdrawAmount = amount;
        lastWithdrawClaimRewards = claim;
        stakedBalance[msg.sender] -= amount;
        ERC20MockMintable(address(lpToken)).mint(msg.sender, amount);

        if (claim) {
            _transferRewards(msg.sender);
        }

        return true;
    }

    function getReward() external returns (bool) {
        claimRewardsCallCount++;
        _transferRewards(msg.sender);
        return true;
    }

    function _transferRewards(address to) internal {
        uint256 crvBalance = crv.balanceOf(address(this));
        if (crvBalance > 0) crv.safeTransfer(to, crvBalance);

        uint256 cvxBalance = cvx.balanceOf(address(this));
        if (cvxBalance > 0) cvx.safeTransfer(to, cvxBalance);
    }
}
