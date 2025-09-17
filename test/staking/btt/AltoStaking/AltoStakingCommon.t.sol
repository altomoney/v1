// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {AltoStaking} from "@alto/staking/AltoStaking.sol";
import {
    Container,
    MinMaxEpochs,
    ITVLWeightedContainersErrors,
    ITVLWeightedContainersEvents
} from "@alto/staking/interfaces/ITVLWeightedContainers.sol";
import {
    StakingPosition,
    StakingContainer,
    IAltoStakingErrors,
    IAltoStakingEvents
} from "@alto/staking/interfaces/IAltoStaking.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";
import {ERC20Mock} from "@alto-test/helpers/ERC20Mock.sol";
import {MockAltoStaking} from "@alto-test/staking/helpers/MockAltoStaking.sol";

bytes32 constant PAUSE_TYPE = keccak256("PAUSE");
bytes32 constant RESCUE_MODE_PAUSE_TYPE = keccak256("RESCUE_MODE");

contract AltoStakingCommon is Test {
    // Test addresses
    address public constant OWNER = address(0x1);
    address public constant USER = address(0x2);
    address public constant USER_2 = address(0x3);
    address public constant RECEIVER = address(0x4);
    address public constant PAUSER = address(0x5);

    // Test constants
    uint256 public constant EPOCH_DURATION = 1 weeks;
    uint256 public constant LOCK_AMOUNT = 1000 ether;

    // Contracts
    MockAltoStaking public staking;
    ERC20Mock public lockToken;

    // Default containers
    Container public shortContainer;
    Container public mediumContainer;
    Container public longContainer;

    function setUp() public virtual {
        vm.warp(1000000); // Set a reasonable starting timestamp

        // Deploy mock token
        lockToken = new ERC20Mock("Lock Token", "LOCK");

        // Set up default containers
        shortContainer = Container({
            growthRate: MinMaxEpochs({min: 1, max: 3}),
            decayRate: MinMaxEpochs({min: 1, max: 2}),
            duration: MinMaxEpochs({min: 1, max: 8}),
            maxRateDifferenceEpochs: 4,
            currentDurationEpochs: 0,
            isActive: false
        });

        mediumContainer = Container({
            growthRate: MinMaxEpochs({min: 1, max: 3}),
            decayRate: MinMaxEpochs({min: 1, max: 2}),
            duration: MinMaxEpochs({min: 2, max: 12}),
            maxRateDifferenceEpochs: 10,
            currentDurationEpochs: 0,
            isActive: false
        });

        longContainer = Container({
            growthRate: MinMaxEpochs({min: 1, max: 3}),
            decayRate: MinMaxEpochs({min: 1, max: 2}),
            duration: MinMaxEpochs({min: 3, max: 16}),
            maxRateDifferenceEpochs: 4,
            currentDurationEpochs: 0,
            isActive: false
        });

        // Fund test accounts
        deal(address(lockToken), address(this), type(uint256).max);
        deal(address(lockToken), USER, type(uint256).max);
        deal(address(lockToken), USER_2, type(uint256).max);
    }

    function _deployWithContainers(Container[] memory containers, uint256[] memory multipliers) internal {
        staking = new MockAltoStaking(address(lockToken), OWNER, EPOCH_DURATION, containers, multipliers);

        // Setup approvals
        lockToken.approve(address(staking), type(uint256).max);
        vm.prank(USER);
        lockToken.approve(address(staking), type(uint256).max);
        vm.prank(USER_2);
        lockToken.approve(address(staking), type(uint256).max);

        // Setup authorization for this test contract to act on behalf of users
        vm.prank(USER);
        staking.setAuthorization(address(this), true);
        vm.prank(USER_2);
        staking.setAuthorization(address(this), true);
    }

    function _deployWithThreeContainers() internal {
        Container[] memory containers = new Container[](3);
        containers[0] = shortContainer;
        containers[1] = mediumContainer;
        containers[2] = longContainer;

        uint256[] memory multipliers = new uint256[](3);
        multipliers[0] = 0.3 ether; // 30%
        multipliers[1] = 0.6 ether; // 60%
        multipliers[2] = 1.0 ether; // 100%

        _deployWithContainers(containers, multipliers);
    }

    function _deployWithSingleContainer() internal {
        Container[] memory containers = new Container[](1);
        containers[0] = shortContainer;

        uint256[] memory multipliers = new uint256[](1);
        multipliers[0] = 0.5 ether; // 50%

        _deployWithContainers(containers, multipliers);
    }

    function _deployEmpty() internal {
        Container[] memory containers = new Container[](0);
        uint256[] memory multipliers = new uint256[](0);

        _deployWithContainers(containers, multipliers);
    }

    function _activateAllContainers() internal {
        vm.startPrank(OWNER);
        for (uint256 i = 1; i <= staking.totalContainerCount(); i++) {
            staking.activateContainer(i);
        }
        vm.stopPrank();
    }

    function _startEpoch() internal {
        vm.prank(OWNER);
        staking.startEpoch();
    }

    function _setupStandardStaking() internal {
        _deployWithThreeContainers();
        _activateAllContainers();
        _startEpoch();
    }

    function _createCustomContainer(
        uint24 growthMin,
        uint24 growthMax,
        uint24 decayMin,
        uint24 decayMax,
        uint24 durationMin,
        uint24 durationMax,
        uint24 maxRateDifference
    ) internal pure returns (Container memory) {
        return Container({
            growthRate: MinMaxEpochs({min: growthMin, max: growthMax}),
            decayRate: MinMaxEpochs({min: decayMin, max: decayMax}),
            duration: MinMaxEpochs({min: durationMin, max: durationMax}),
            maxRateDifferenceEpochs: maxRateDifference,
            currentDurationEpochs: 0,
            isActive: false
        });
    }

    function _lockPosition(address onBehalf, uint256 amount, uint256 containerId, bool isReuse)
        internal
        returns (uint256)
    {
        return staking.lock(onBehalf, amount, containerId, isReuse, 0);
    }

    function _lockPositionWithMaxEpochs(
        address onBehalf,
        uint256 amount,
        uint256 containerId,
        bool isReuse,
        uint256 maxEpochsToLockFor
    ) internal returns (uint256) {
        return staking.lock(onBehalf, amount, containerId, isReuse, maxEpochsToLockFor);
    }

    function _unlockPosition(address onBehalf, address receiver, uint256 containerId) internal returns (uint256) {
        return staking.unlock(onBehalf, receiver, containerId);
    }

    function _advanceTime(uint256 duration) internal {
        vm.warp(block.timestamp + duration);
    }

    function _advanceEpochs(uint256 numEpochs) internal {
        _advanceTime(numEpochs * EPOCH_DURATION + 1);
    }

    function _pauseContract() internal {
        vm.prank(OWNER);
        staking.setPauser(PAUSER, PAUSE_TYPE, true);
        vm.prank(PAUSER);
        staking.pause(PAUSE_TYPE, true);
    }

    function _enableRescueMode() internal {
        vm.prank(OWNER);
        staking.setPauser(PAUSER, RESCUE_MODE_PAUSE_TYPE, true);
        vm.prank(PAUSER);
        staking.pause(RESCUE_MODE_PAUSE_TYPE, true);
    }

    function _assertPositionEquals(
        StakingPosition memory actual,
        uint256 expectedLocked,
        uint256 expectedExpiry,
        uint256 expectedLockedTimestamp
    ) internal {
        assertEq(actual.amountLocked, expectedLocked, "Amount locked mismatch");
        assertEq(actual.expiryTimestamp, expectedExpiry, "Expiry timestamp mismatch");
        assertEq(actual.lockedTimestamp, expectedLockedTimestamp, "Locked timestamp mismatch");
    }

    function _assertPositionEmpty(StakingPosition memory position) internal {
        assertEq(position.amountLocked, 0, "Position should be empty - amount");
        assertEq(position.expiryTimestamp, 0, "Position should be empty - expiry");
        assertEq(position.lockedTimestamp, 0, "Position should be empty - locked timestamp");
    }
}
