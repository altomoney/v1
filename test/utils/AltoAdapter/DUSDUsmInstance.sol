// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {DUSDUsm} from "@alto/usm/DUSDUsm.sol";

contract DUSDUsmInstance is DUSDUsm {
    constructor(address dusd, address underlyingAsset) DUSDUsm(dusd, underlyingAsset) {}
}

