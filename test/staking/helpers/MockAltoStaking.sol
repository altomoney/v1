// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import {AltoStaking} from "@alto/staking/AltoStaking.sol";
import {Container} from "@alto/staking/interfaces/ITVLWeightedContainers.sol";

contract MockAltoStaking is AltoStaking {
    constructor(
        address _lockToken,
        address _owner,
        uint256 _epochDuration,
        Container[] memory _containers,
        uint256[] memory _containerMultipliers
    ) AltoStaking(_lockToken, _owner, _epochDuration, _containers, _containerMultipliers) {}

    function getContainer(uint256 containerId) external view returns (Container memory) {
        return containerById[containerId];
    }
}
