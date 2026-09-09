// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IConvexBooster} from "@alto/lending/interfaces/vendor/IConvexBooster.sol";

import {ConvexRewardPoolMock} from "./ConvexRewardPoolMock.sol";

contract ConvexBoosterMock is IConvexBooster {
    address public lpToken;
    address public depositToken;
    address public gauge;
    address public rewardPool;
    address public stash;
    bool public shutdown;
    bool public depositResult = true;
    bool public revertDeposit;
    uint256 public depositTransferAmount = type(uint256).max;
    uint256 public depositStakeAmount = type(uint256).max;
    uint256 public depositCalls;
    uint256 public lastPid;
    uint256 public lastAmount;
    bool public lastStake;
    address public callbackTarget;
    bytes public callbackData;

    constructor(address lpToken_, address depositToken_, address gauge_, address rewardPool_) {
        setPoolInfo(lpToken_, depositToken_, gauge_, rewardPool_, address(0), false);
    }

    function setPoolInfo(
        address lpToken_,
        address depositToken_,
        address gauge_,
        address rewardPool_,
        address stash_,
        bool shutdown_
    ) public {
        lpToken = lpToken_;
        depositToken = depositToken_;
        gauge = gauge_;
        rewardPool = rewardPool_;
        stash = stash_;
        shutdown = shutdown_;
    }

    function setDepositBehavior(bool shouldRevert, bool result, uint256 transferAmount, uint256 stakeAmount) external {
        revertDeposit = shouldRevert;
        depositResult = result;
        depositTransferAmount = transferAmount;
        depositStakeAmount = stakeAmount;
    }

    function setCallback(address target, bytes calldata data) external {
        callbackTarget = target;
        callbackData = data;
    }

    function poolInfo(uint256) external view returns (address, address, address, address, address, bool) {
        return (lpToken, depositToken, gauge, rewardPool, stash, shutdown);
    }

    function deposit(uint256 poolId, uint256 amount, bool stake) external returns (bool) {
        if (revertDeposit) revert("DEPOSIT_REVERTED");
        ++depositCalls;
        lastPid = poolId;
        lastAmount = amount;
        lastStake = stake;
        if (!depositResult) return false;

        uint256 transferAmount = depositTransferAmount == type(uint256).max ? amount : depositTransferAmount;
        if (transferAmount != 0) require(IERC20(lpToken).transferFrom(msg.sender, rewardPool, transferAmount));
        uint256 stakeAmount = depositStakeAmount == type(uint256).max ? amount : depositStakeAmount;
        ConvexRewardPoolMock(rewardPool).stakeFor(msg.sender, stakeAmount);

        if (callbackTarget != address(0)) {
            (bool success, bytes memory reason) = callbackTarget.call(callbackData);
            if (!success) {
                assembly ("memory-safe") {
                    revert(add(reason, 0x20), mload(reason))
                }
            }
        }
        return true;
    }
}
