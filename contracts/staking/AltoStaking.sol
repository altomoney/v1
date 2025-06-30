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

    /// @dev Modifier to check if the contract is not paused.
    modifier whenNotPaused() {
        if (paused[PAUSE_TYPE]) {
            revert IPausable.IsPaused(PAUSE_TYPE);
        }
        _;
    }

    /// @dev Modifier to check if the contract is not in rescue mode.
    modifier whenNotRescueMode() {
        if (paused[RESCUE_MODE_PAUSE_TYPE]) {
            revert IPausable.IsPaused(RESCUE_MODE_PAUSE_TYPE);
        }
        _;
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
        for (uint256 i = 0; i < activeContainerIds.length; i++) {
            uint256 containerId = activeContainerIds[i];
            if (!_isExpiredPosition(positions[account][containerId])) {
                // votes will have same decimals the the lock token
                votes += positions[account][containerId].amountLocked.multiplyWithPrecision(
                    stakingContainerById[containerId].multiplier
                );
            }
        }
    }

    /// @inheritdoc IAltoStakingBase
    function lock(address onBehalf, uint256 amount, uint256 containerId, bool isReuse)
        external
        whenNotPaused
        whenNotRescueMode
        returns (uint256)
    {
        // Note: containerId is validated in _updateContainerTVL

        if (!_isSenderAuthorized(onBehalf)) {
            revert AltoStakingUnauthorized();
        }

        if (onBehalf == address(0) || amount == 0) {
            revert AltoStakingInvalidInput();
        }

        if (stakingContainerById[containerId].isDeprecated) {
            revert AltoStakingContainerDeprecated();
        }

        if (nextEpochToProcess != currentEpoch()) _advanceEpoch(currentEpoch() - nextEpochToProcess);

        StakingPosition storage position = positions[onBehalf][containerId];

        if (isReuse) {
            if (position.amountLocked != amount) {
                revert AltoStakingNoPosition();
            }
        } else {
            amount += position.amountLocked;
        }

        uint256 currentEpochDuration = containerById[containerId].currentDurationEpochs;

        uint256 lockedTimestamp = block.timestamp;
        uint256 expiryTimestamp = lockedTimestamp + (currentEpochDuration * EPOCH_DURATION);

        uint256 firstTvlEpoch = _timestampToEpoch(lockedTimestamp);
        uint256 lastTvlEpoch = _timestampToEpoch(expiryTimestamp);

        if (position.amountLocked > 0) {
            // Remove old TVL, but only from epochs that haven't been processed yet
            // position.expiryTimestamp can't be 0 in this case
            uint256 oldLastTvlEpoch = _timestampToEpoch(position.expiryTimestamp);
            if (oldLastTvlEpoch > nextEpochToProcess) {
                _updateContainerTVL(containerId, position.amountLocked, nextEpochToProcess, oldLastTvlEpoch, false);
            }
        }

        _updateContainerTVL(containerId, amount, firstTvlEpoch, lastTvlEpoch, true);
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
        whenNotPaused
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

        // Update TVL when removing position in rescue mode
        if (inRescueMode && !isExpired) {
            uint256 currentEpochNum = currentEpoch();
            uint256 expiryEpoch = _timestampToEpoch(position.expiryTimestamp);
            if (expiryEpoch > currentEpochNum) {
                if (nextEpochToProcess != currentEpoch()) _advanceEpoch(currentEpoch() - nextEpochToProcess);
                _updateContainerTVL(containerId, position.amountLocked, currentEpochNum, expiryEpoch, false);
            }
        }

        positions[onBehalf][containerId].amountLocked = 0;
        positions[onBehalf][containerId].expiryTimestamp = 0;
        positions[onBehalf][containerId].lockedTimestamp = 0;

        IERC20(lockToken).safeTransfer(receiver, releasedAmount);
        emit UnlockPosition(msg.sender, onBehalf, receiver, containerId, releasedAmount);
    }

    /// @inheritdoc IAltoStakingBase
    function advanceEpoch(uint256 limit) external whenNotPaused {
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
    }

    /// @inheritdoc IAltoStakingBase
    function updateContainer(uint256 containerId, Container memory container, uint256 multiplier) external onlyOwner {
        if (stakingContainerById[containerId].isDeprecated) {
            revert AltoStakingInvalidInput();
        }

        _updateContainerMultiplier(containerId, multiplier);
        _updateContainer(containerId, container);
    }

    /// @inheritdoc IAltoStakingBase
    function activateContainer(uint256 containerId) external onlyOwner {
        if (stakingContainerById[containerId].isDeprecated) {
            revert AltoStakingInvalidInput();
        }
        _activateContainer(containerId);
    }

    /// @inheritdoc IAltoStakingBase
    function deactivateContainer(uint256 containerId) external onlyOwner {
        if (!stakingContainerById[containerId].isDeprecated) {
            revert AltoStakingInvalidInput();
        }
        _deactivateContainer(containerId);
    }

    /// @inheritdoc IAltoStakingBase
    function deprecateContainer(uint256 containerId) external onlyOwner {
        // container does not have to be active to be deprecated
        if (stakingContainerById[containerId].isDeprecated) {
            revert AltoStakingInvalidInput();
        }
        stakingContainerById[containerId].isDeprecated = true;
        emit ContainerDeprecate(containerId);
    }

    /// @inheritdoc ITVLWeightedContainers
    function startEpoch() external override(TVLWeightedContainers, ITVLWeightedContainers) onlyOwner {
        _startEpoch();
    }

    /// @dev Internal function to validate and update the multiplier of a container.
    function _updateContainerMultiplier(uint256 containerId, uint256 multiplier) internal {
        if (multiplier > MATH_PRECISION || multiplier == 0) {
            revert AltoStakingInvalidInput();
        }
        stakingContainerById[containerId].multiplier = multiplier;

        emit ContainerMultiplierUpdated(containerId, multiplier);
    }

    /// @dev Internal function to check if a position is expired.
    function _isExpiredPosition(StakingPosition memory position) internal view returns (bool) {
        return block.timestamp >= position.expiryTimestamp;
    }
}
