// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.22;

// External
import {IERC20} from "@boringcrypto/boring-solidity/contracts/interfaces/IERC20.sol";

// Lz
import {TestHelper} from "./LZSetup/TestHelper.sol";

// Tapioca
import {TOFTInitStruct, TOFTModulesInitStruct} from "tap-utils/interfaces/oft/ITOFT.sol";

import {Cluster} from "tap-utils/Cluster/Cluster.sol";
import {SingularityMock} from "./SingularityMock.sol";
import {MagnetarMock} from "./MagnetarMock.sol";

import {TestUtils} from "./TestUtils.t.sol";

contract TOFTTestHelper is TestHelper, TestUtils {
    //     function createMagnetar(address cluster, address owner) public returns (MagnetarV2) {
    //         MagnetarMarketModule marketModule = new MagnetarMarketModule();
    //         return new MagnetarV2(cluster, owner, payable(marketModule));
    //     }

    function createSingularity(address _collateral, address _asset) public returns (SingularityMock) {
        return new SingularityMock(_collateral, _asset);
    }

    function createMagnetar(address cluster) public returns (MagnetarMock) {
        return new MagnetarMock(cluster);
    }

    function createCluster(uint32 hostEid, address owner) public returns (Cluster) {
        return new Cluster(hostEid, owner);
    }
}
