// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

/// @notice Minimal Convex stash-wrapper mock.
contract MockConvexStashTokenWrapper {
    address public token;
    address public rewardPool;
    address public booster;

    constructor(address token_) {
        token = token_;
    }

    function setConvexContext(address rewardPool_, address booster_) external {
        rewardPool = rewardPool_;
        booster = booster_;
    }
}
