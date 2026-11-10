// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {Container, MinMaxEpochs} from "@alto/staking/interfaces/ITVLWeightedContainers.sol";
import {MockTVLWeightedContainers} from "@alto-test/staking/helpers/MockTVLWeightedContainers.sol";

contract TVLWeightedContainersCommon is Test {
    MockTVLWeightedContainers public containers;

    // Test constants
    uint256 public constant EPOCH_DURATION = 1 weeks;
    address public constant USER = address(0x1);
    address public constant OWNER = address(0x2);

    // Default container parameters
    Container public defaultContainer;

    /// @notice Struct to hold container parameters for easier readability
    struct ContainerParams {
        uint24 growthMin;
        uint24 growthMax;
        uint24 decayMin;
        uint24 decayMax;
        uint24 durationMin;
        uint24 durationMax;
        uint24 maxRateDifference;
    }

    function setUp() public virtual {
        vm.warp(1000000); // Set a reasonable starting timestamp

        // Set up default container
        defaultContainer = Container({
            growthRate: MinMaxEpochs({min: 1, max: 5}),
            decayRate: MinMaxEpochs({min: 1, max: 3}),
            duration: MinMaxEpochs({min: 10, max: 100}),
            isActive: false,
            maxRateDifferenceEpochs: 50,
            currentDurationEpochs: 0
        });
    }

    function _createContainerWithCustomParams(ContainerParams memory params) internal pure returns (Container memory) {
        return Container({
            growthRate: MinMaxEpochs({min: params.growthMin, max: params.growthMax}),
            decayRate: MinMaxEpochs({min: params.decayMin, max: params.decayMax}),
            duration: MinMaxEpochs({min: params.durationMin, max: params.durationMax}),
            isActive: false,
            maxRateDifferenceEpochs: params.maxRateDifference,
            currentDurationEpochs: 0
        });
    }

    function _deployWithContainers(Container[] memory initialContainers) internal {
        containers = new MockTVLWeightedContainers(EPOCH_DURATION, initialContainers);
    }

    function _deployWithoutContainers() internal {
        Container[] memory emptyContainers = new Container[](0);
        containers = new MockTVLWeightedContainers(EPOCH_DURATION, emptyContainers);
    }

    function _deployWithSingleContainer() internal {
        Container[] memory singleContainer = new Container[](1);
        singleContainer[0] = defaultContainer;
        containers = new MockTVLWeightedContainers(EPOCH_DURATION, singleContainer);
    }
}
