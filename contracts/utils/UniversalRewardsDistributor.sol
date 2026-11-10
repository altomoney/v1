// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

import {MerkleRootManager} from "@alto/utils/MerkleRootManager.sol";
import {AltoOwnable2Step, Ownable} from "@alto/utils/AltoOwnable2Step.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Auth} from "@alto/utils/Auth.sol";
import {IUniversalRewardsDistributor} from "@alto/utils/interfaces/IUniversalRewardsDistributor.sol";
import {Pausable, IPausable} from "@alto/utils/Pausable.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";

/// @title Universal Rewards Distributor
/// @author Inspired by Morpho Labs' implementation (https://github.com/morpho-org/universal-rewards-distributor).
/// @custom:contact security@altofoundation.org
/// @notice A contract for distributing rewards to multiple users using merkle trees
contract UniversalRewardsDistributor is
    IUniversalRewardsDistributor,
    MerkleRootManager,
    AltoOwnable2Step,
    Auth,
    Pausable
{
    using SafeERC20 for IERC20;

    /// @inheritdoc IUniversalRewardsDistributor
    mapping(address user => mapping(address rewardToken => uint256 amount)) public claimed;

    constructor(address _owner, uint256 initialTimelock) Ownable(_owner) {
        _setMerkleRootTimelock(initialTimelock);
    }

    /// @inheritdoc IUniversalRewardsDistributor
    function claim(
        address onBehalf,
        address rewardToken,
        uint256 totalRewardTokenAssignedToUser,
        bytes32[] calldata proof
    ) external whenNot(PAUSE_TYPE) returns (uint256 amount) {
        if (!_isSenderAuthorized(onBehalf)) {
            revert RewardsDistributorUnauthorized();
        }

        if (!_verifyProof(
                proof,
                keccak256(bytes.concat(keccak256(abi.encode(onBehalf, rewardToken, totalRewardTokenAssignedToUser))))
            )) {
            revert RewardsDistributorInvalidInput();
        }

        if (claimed[onBehalf][rewardToken] >= totalRewardTokenAssignedToUser) {
            revert RewardsDistributorInvalidInput();
        }

        amount = totalRewardTokenAssignedToUser - claimed[onBehalf][rewardToken];

        claimed[onBehalf][rewardToken] = totalRewardTokenAssignedToUser;

        IERC20(rewardToken).safeTransfer(onBehalf, amount);

        emit ClaimRewardToken(msg.sender, onBehalf, rewardToken, amount);
    }

    /// @inheritdoc IPausable
    function setPauser(address pauser, bytes32 pauseType, bool status)
        external
        override(Pausable, IPausable)
        onlyOwner
    {
        _setPauser(pauser, pauseType, status);
    }

    /// @notice Implementation of abstract function from MerkleRootManager
    function _getOwner() internal view override returns (address) {
        return owner();
    }

    /// @inheritdoc IUniversalRewardsDistributor
    function rescueRewardTokens(address token) external onlyOwner {
        if (!paused[PAUSE_TYPE]) {
            revert RewardsDistributorNotPaused();
        }

        uint256 balance = IERC20(token).balanceOf(address(this));

        if (balance != 0) {
            IERC20(token).safeTransfer(msg.sender, balance);
            emit RescueRewardTokens(token, msg.sender, balance);
        }
    }
}
