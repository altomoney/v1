// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {UsmType} from "@alto/usm/interfaces/IUsmCommon.sol";

contract MockUsmTyped {
    UsmType private immutable _usmType;

    constructor(UsmType usmType_) {
        _usmType = usmType_;
    }

    function USM_TYPE() external view returns (UsmType) {
        return _usmType;
    }
}
