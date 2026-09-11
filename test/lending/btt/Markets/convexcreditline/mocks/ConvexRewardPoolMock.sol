// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "morpho-blue/src/mocks/ERC20Mock.sol";

import {IConvexRewardPool} from "@alto/lending/interfaces/vendor/IConvexRewardPool.sol";

contract ConvexRewardPoolMock is IConvexRewardPool {
    uint256 public override pid;
    address public override operator;
    address public override stakingToken;
    address public override rewardToken;

    IERC20 public immutable LP_TOKEN;
    mapping(address => uint256) private _balanceOf;
    bool public withdrawResult = true;
    bool public getRewardResult = true;
    bool public revertWithdraw;
    bool public revertGetReward;
    uint256 public withdrawTransferAmount = type(uint256).max;
    uint256 public withdrawStakeReduction = type(uint256).max;
    uint256 public withdrawCalls;
    uint256 public getRewardCalls;
    uint256 public lastWithdrawAmount;
    bool public lastWithdrawClaim;
    address public lastRewardAccount;
    bool public lastClaimExtras;
    address public callbackTarget;
    bytes public callbackData;
    bool public callbackOnWithdraw;
    bool public callbackOnReward;
    address[] private _distributedTokens;
    uint256[] private _distributedAmounts;

    constructor(uint256 pid_, address operator_, address stakingToken_, address rewardToken_, address lpToken_) {
        pid = pid_;
        operator = operator_;
        stakingToken = stakingToken_;
        rewardToken = rewardToken_;
        LP_TOKEN = IERC20(lpToken_);
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balanceOf[account];
    }

    function setPoolMetadata(uint256 pid_, address operator_, address stakingToken_, address rewardToken_) external {
        pid = pid_;
        operator = operator_;
        stakingToken = stakingToken_;
        rewardToken = rewardToken_;
    }

    function setStake(address account, uint256 amount) external {
        _balanceOf[account] = amount;
    }

    function stakeFor(address account, uint256 amount) external {
        _balanceOf[account] += amount;
    }

    function setWithdrawBehavior(bool shouldRevert, bool result, uint256 transferAmount, uint256 stakeReduction)
        external
    {
        revertWithdraw = shouldRevert;
        withdrawResult = result;
        withdrawTransferAmount = transferAmount;
        withdrawStakeReduction = stakeReduction;
    }

    function setRewardBehavior(bool shouldRevert, bool result) external {
        revertGetReward = shouldRevert;
        getRewardResult = result;
    }

    function setRewards(address[] calldata tokens, uint256[] calldata amounts) external {
        delete _distributedTokens;
        delete _distributedAmounts;
        for (uint256 i; i < tokens.length; ++i) {
            _distributedTokens.push(tokens[i]);
            _distributedAmounts.push(amounts[i]);
            ERC20Mock token = ERC20Mock(tokens[i]);
            token.setBalance(address(this), token.balanceOf(address(this)) + amounts[i]);
        }
    }

    function setCallback(address target, bytes calldata data, bool onWithdraw, bool onReward) external {
        callbackTarget = target;
        callbackData = data;
        callbackOnWithdraw = onWithdraw;
        callbackOnReward = onReward;
    }

    function withdrawAndUnwrap(uint256 amount, bool claim) external returns (bool) {
        if (revertWithdraw) revert("WITHDRAW_REVERTED");
        ++withdrawCalls;
        lastWithdrawAmount = amount;
        lastWithdrawClaim = claim;
        if (!withdrawResult) return false;

        uint256 reduction = withdrawStakeReduction == type(uint256).max ? amount : withdrawStakeReduction;
        _balanceOf[msg.sender] -= reduction;
        uint256 transferAmount = withdrawTransferAmount == type(uint256).max ? amount : withdrawTransferAmount;
        if (transferAmount != 0) require(LP_TOKEN.transfer(msg.sender, transferAmount));
        if (callbackOnWithdraw) _callback();
        return true;
    }

    function getReward(address account, bool claimExtras) external returns (bool) {
        if (revertGetReward) revert("GET_REWARD_REVERTED");
        ++getRewardCalls;
        lastRewardAccount = account;
        lastClaimExtras = claimExtras;
        if (!getRewardResult) return false;

        for (uint256 i; i < _distributedTokens.length; ++i) {
            require(IERC20(_distributedTokens[i]).transfer(account, _distributedAmounts[i]));
        }
        if (callbackOnReward) _callback();
        return true;
    }

    function _callback() private {
        (bool success, bytes memory reason) = callbackTarget.call(callbackData);
        if (!success) {
            assembly ("memory-safe") {
                revert(add(reason, 0x20), mload(reason))
            }
        }
    }
}
