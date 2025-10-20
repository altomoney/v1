// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {AdapterContractApproval} from "@alto/utils/AdapterContractApproval.sol";

contract AdapterContractApprovalInstance is AdapterContractApproval {
    constructor(address owner_) AdapterContractApproval(owner_) {}
}
