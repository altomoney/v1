// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Extra reward pool mock that can expose a wrapper while paying its underlying token.
contract MockConvexExtraRewardPool {
    using SafeERC20 for IERC20;

    address internal rewardTokenAddress;
    IERC20 public payoutToken;
    bool public rewardTokenReverts;

    constructor(address rewardToken_, address payoutToken_) {
        rewardTokenAddress = rewardToken_;
        payoutToken = IERC20(payoutToken_);
    }

    function rewardToken() external view returns (address) {
        require(!rewardTokenReverts, "reward token query failed");
        return rewardTokenAddress;
    }

    function setRewardTokenReverts(bool reverts_) external {
        rewardTokenReverts = reverts_;
    }

    function getReward(address recipient) external {
        uint256 balance = payoutToken.balanceOf(address(this));
        if (balance > 0) payoutToken.safeTransfer(recipient, balance);
    }
}
