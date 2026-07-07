// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {UsmType} from "@alto/usm/interfaces/IUsmCommon.sol";
import {MockUsmTyped} from "@alto-test/usm/mocks/MockUsmTyped.sol";

abstract contract UsmRegistryCommon is Test {
    function _deployMockUsm(UsmType usmType_) internal returns (address) {
        return address(new MockUsmTyped(usmType_));
    }
}
