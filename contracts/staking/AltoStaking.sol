// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

import {Pausable} from "@alto/utils/Pausable.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {StakingPosition, StakingContainer} from "./interfaces/IAltoStaking.sol";
import {TVLWeightedContainers, Container} from "./TVLWeightedContainers.sol";
import {IAltoStakingStaticTypes, IAltoStakingBase} from "./interfaces/IAltoStaking.sol";
import {ITVLWeightedContainers} from "./interfaces/ITVLWeightedContainers.sol";
import {MATH_PRECISION, FixedPointMath} from "@alto/utils/FixedPointMath.sol";
import {Auth} from "@alto/utils/Auth.sol";

bytes32 constant PAUSE_TYPE = keccak256("PAUSE");
bytes32 constant RESCUE_MODE_PAUSE_TYPE = keccak256("RESCUE_MODE");

contract AltoStaking is IAltoStakingStaticTypes, TVLWeightedContainers, Ownable2Step, Auth, Pausable {
    using SafeERC20 for IERC20;
    using FixedPointMath for uint256;

    /// @inheritdoc IAltoStakingBase
    address public immutable lockToken;

    /// @inheritdoc IAltoStakingStaticTypes
    mapping(uint256 => StakingContainer) public stakingContainerById;

    /// @inheritdoc IAltoStakingStaticTypes
    mapping(address => mapping(uint256 => StakingPosition)) public positions;

    /// @inheritdoc IAltoStakingBase
    uint256 public maxMultiplierStakingContainerId;

    constructor(
        address _lockToken,
        address _owner,
        uint256 _epochDuration,
        Container[] memory _containers,
        uint256[] memory _containerMultipliers
    ) TVLWeightedContainers(_epochDuration, _containers) Ownable(_owner) {
        if (_containers.length != _containerMultipliers.length) {
            revert AltoStakingInvalidInput();
        }
        for (uint256 i = 0; i < _containers.length; i++) {
            // we add 1 to the containerId because the containerId starts from 1
            _updateContainerMultiplier(i + 1, _containerMultipliers[i]);
        }

        if (_lockToken == address(0)) {
            revert AltoStakingInvalidInput();
        }

        lockToken = _lockToken;
    }

    /// @inheritdoc IPausable
    function setPauser(address pauser, bytes32 pauseType, bool status)
        external
        override(Pausable, IPausable)
        onlyOwner
    {
        _setPauser(pauser, pauseType, status);
    }

    /// @dev we restrict rescue mode to be one-way emergency mode
    function _onPause(bytes32 pauseType, bool _paused) internal override {
        if (pauseType == RESCUE_MODE_PAUSE_TYPE && !_paused) {
            revert AltoStakingInvalidInput();
        }
    }

    /// @inheritdoc IAltoStakingBase
    function getPosition(address account, uint256 containerId)
        external
        view
        returns (StakingPosition memory position)
    {
        return positions[account][containerId];
    }

    /// @inheritdoc IAltoStakingBase
    function getVotes(address account) external view returns (uint256 votes) {
        // if contract is in one of the rescue modes we return 0
        if (paused[PAUSE_TYPE] || paused[RESCUE_MODE_PAUSE_TYPE]) {
            return 0;
        }

        for (uint256 i = 0; i < activeContainerIds.length; i++) {
            uint256 containerId = activeContainerIds[i];
            if (!_isExpiredPosition(positions[account][containerId])) {
                // votes will have same decimals as the lock token
                votes += positions[account][containerId].amountLocked.multiplyWithPrecision(
                    stakingContainerById[containerId].multiplier
                );
            }
        }
    }

    /// @inheritdoc IAltoStakingBase
    function lock(address onBehalf, uint256 amount, uint256 containerId, bool isReuse, uint256 maxEpochsToLockFor)
        external
        whenNot(PAUSE_TYPE)
        whenNot(RESCUE_MODE_PAUSE_TYPE)
        returns (uint256)
    {
        // Note: containerId is validated in _updateContainerTVL

        if (onBehalf == address(0) || amount == 0) {
            revert AltoStakingInvalidInput();
        }

        if (!_isSenderAuthorized(onBehalf)) {
            revert AltoStakingUnauthorized();
        }

        if (stakingContainerById[containerId].isDeprecated) {
            revert AltoStakingContainerDeprecated();
        }

        if (nextEpochToProcess != currentEpoch()) {
            _advanceEpoch(currentEpoch() - nextEpochToProcess);
        }

        StakingPosition storage position = positions[onBehalf][containerId];

        if (isReuse) {
            if (position.amountLocked != amount) {
                revert AltoStakingNoPosition();
            }
        } else {
            amount += position.amountLocked;
        }

        uint256 currentEpochDuration = containerById[containerId].currentDurationEpochs;

        if (maxEpochsToLockFor > 0 && currentEpochDuration > maxEpochsToLockFor) {
            revert AltoStakingTryingToLockForTooManyEpochs();
        }

        uint256 lockedTimestamp = block.timestamp;
        uint256 expiryTimestamp = lockedTimestamp + (currentEpochDuration * EPOCH_DURATION);

        if (position.amountLocked > 0) {
            // Remove old TVL, but only from epochs that haven't been processed yet
            // position.expiryTimestamp can't be 0 in this case
            uint256 oldLastTvlEpoch = _timestampToEpoch(position.expiryTimestamp);
            if (oldLastTvlEpoch > nextEpochToProcess) {
                _updateContainerTVL(containerId, position.amountLocked, nextEpochToProcess, oldLastTvlEpoch, false);
            }
        }

        _updateContainerTVL(
            containerId, amount, _timestampToEpoch(lockedTimestamp), _timestampToEpoch(expiryTimestamp), true
        );

        uint256 amountPrevious = position.amountLocked;
        position.lockedTimestamp = lockedTimestamp;
        position.expiryTimestamp = expiryTimestamp;
        position.amountLocked = amount;

        if (!isReuse) {
            IERC20(lockToken).safeTransferFrom(msg.sender, address(this), amount - amountPrevious);
        }

        emit LockPosition(msg.sender, onBehalf, containerId, amount, expiryTimestamp, isReuse);

        return amount;
    }

    /// @inheritdoc IAltoStakingBase
    function unlock(address onBehalf, address receiver, uint256 containerId)
        external
        whenNot(PAUSE_TYPE)
        returns (uint256 releasedAmount)
    {
        if (!_isSenderAuthorized(onBehalf)) {
            revert AltoStakingUnauthorized();
        }

        if (receiver == address(0)) {
            revert AltoStakingInvalidInput();
        }

        StakingPosition memory position = positions[onBehalf][containerId];

        // Allow early unlock only in rescue mode
        bool isExpired = _isExpiredPosition(position);
        bool inRescueMode = paused[RESCUE_MODE_PAUSE_TYPE];

        if (!isExpired && !inRescueMode) {
            revert AltoStakingPositionNotExpired();
        }

        if (position.amountLocked == 0) {
            revert AltoStakingNoPosition();
        }

        releasedAmount = position.amountLocked;

        // We don't update (subtract) TVL when removing position in rescue mode as rescue mode is a one-way emergency mode

        positions[onBehalf][containerId].amountLocked = 0;
        positions[onBehalf][containerId].expiryTimestamp = 0;
        positions[onBehalf][containerId].lockedTimestamp = 0;

        IERC20(lockToken).safeTransfer(receiver, releasedAmount);
        emit UnlockPosition(msg.sender, onBehalf, receiver, containerId, releasedAmount);
    }

    /// @inheritdoc IAltoStakingBase
    function advanceEpoch(uint256 limit) external whenNot(PAUSE_TYPE) whenNot(RESCUE_MODE_PAUSE_TYPE) {
        _advanceEpoch(limit);
    }

    /// @inheritdoc IAltoStakingBase
    function emergencySweep() external onlyOwner {
        if (!paused[PAUSE_TYPE]) {
            revert AltoStakingNotPausedForEmergencySweep();
        }

        emit EmergencySweep(msg.sender, owner(), IERC20(lockToken).balanceOf(address(this)));

        IERC20(lockToken).safeTransfer(owner(), IERC20(lockToken).balanceOf(address(this)));
    }

    /// @inheritdoc IAltoStakingBase
    function addContainer(Container memory container, uint256 multiplier) external onlyOwner {
        uint256 containerId = _addContainer(container);
        _updateContainerMultiplier(containerId, multiplier);

        // no need to update max multiplier staking container id because it will be updated
        // when container is activated (it is inactive by default)
    }

    /// @inheritdoc IAltoStakingBase
    function updateContainer(uint256 containerId, Container memory container, uint256 multiplier) external onlyOwner {
        if (stakingContainerById[containerId].isDeprecated) {
            revert AltoStakingInvalidInput();
        }

        _updateContainerMultiplier(containerId, multiplier);
        _updateContainer(containerId, container);

        // if multiplier is not 0, we need to update max multiplier staking container id
        // as the multiplier has changed
        if (multiplier != 0) {
            _updateMaxMultiplierStakingContainerId();
        }
    }

    /// @inheritdoc IAltoStakingBase
    function activateContainer(uint256 containerId) external onlyOwner {
        if (stakingContainerById[containerId].isDeprecated) {
            revert AltoStakingInvalidInput();
        }
        _activateContainer(containerId);

        // only active containers are able to used for locking so we need to update
        _updateMaxMultiplierStakingContainerId();
    }

    /// @inheritdoc IAltoStakingBase
    function deactivateContainer(uint256 containerId) external onlyOwner {
        if (!stakingContainerById[containerId].isDeprecated) {
            revert AltoStakingInvalidInput();
        }
        _deactivateContainer(containerId);

        // no need to update max multiplier staking container id because it was updated
        // when container was deprecated (which is the requirement for function to run)
    }

    /// @inheritdoc IAltoStakingBase
    function deprecateContainer(uint256 containerId) external onlyOwner {
        // container does not have to be active to be deprecated
        if (stakingContainerById[containerId].isDeprecated) {
            revert AltoStakingInvalidInput();
        }
        // check if container exists
        if (!_isContainerExists(containerId)) {
            revert AltoStakingInvalidInput();
        }

        stakingContainerById[containerId].isDeprecated = true;
        emit ContainerDeprecate(containerId);

        // deprecated containers are unable to used for locking so we need to update
        _updateMaxMultiplierStakingContainerId();
    }

    /// @inheritdoc ITVLWeightedContainers
    function startEpoch() external override(TVLWeightedContainers, ITVLWeightedContainers) onlyOwner {
        _startEpoch();
    }

    /// @dev Internal function to update the max multiplier staking container id.
    /// @dev Used for locking in max multiplier container during AltoRewardsDistributor.claimRewardTokens.
    function _updateMaxMultiplierStakingContainerId() internal {
        uint256 containerId = 0;
        uint256 multiplier = 0;

        // check if container is active
        for (uint256 i = 0; i < activeContainerIds.length; i++) {
            // and not deprecated
            if (stakingContainerById[activeContainerIds[i]].isDeprecated) {
                continue;
            }
            uint256 currentContainerId = activeContainerIds[i];
            if (stakingContainerById[currentContainerId].multiplier > multiplier) {
                multiplier = stakingContainerById[currentContainerId].multiplier;
                containerId = currentContainerId;
            }
        }

        if (containerId != maxMultiplierStakingContainerId) {
            maxMultiplierStakingContainerId = containerId;
            emit MaxMultiplierStakingContainerIdUpdated(containerId, multiplier);
        }
    }

    /// @dev Internal function to validate and update the multiplier of a container.
    function _updateContainerMultiplier(uint256 containerId, uint256 multiplier) internal {
        if (multiplier > MATH_PRECISION || multiplier == 0) {
            revert AltoStakingInvalidInput();
        }

        if (stakingContainerById[containerId].multiplier == multiplier) {
            // we should not emit event in this case
            return;
        }

        stakingContainerById[containerId].multiplier = multiplier;

        emit ContainerMultiplierUpdated(containerId, multiplier);
    }

    /// @dev Internal function to check if a position is expired.
    function _isExpiredPosition(StakingPosition memory position) internal view returns (bool) {
        return block.timestamp >= position.expiryTimestamp;
    }
}
