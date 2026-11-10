// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {ProtocolFeeCollector} from "@alto/sdusd/ProtocolFeeCollector.sol";
import {ProtocolFeeCollectorInitParams} from "@alto/sdusd/interfaces/IProtocolFeeCollector.sol";
import {ProtocolFeeCollectorCommon} from "./ProtocolFeeCollectorCommon.t.sol";

contract ProtocolFeeCollector_Constructor_Test is ProtocolFeeCollectorCommon {
    function test_DeploysImplementationSuccessfully() public {
        ProtocolFeeCollector deployedImplementation = new ProtocolFeeCollector();

        assertGt(address(deployedImplementation).code.length, 0);
    }

    function test_DisablesInitializersOnImplementation() public {
        ProtocolFeeCollector deployedImplementation = new ProtocolFeeCollector();
        ProtocolFeeCollectorInitParams memory params = _validInitParams();

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        deployedImplementation.initialize(params);
    }
}
