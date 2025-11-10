// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import {OFT} from "@alto/utils/OFT.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @title Alto Token
/// @author Pearl Labs
/// @custom:contact security@tapioca.xyz
/// @notice The Alto Token is the native token of the Alto Protocol.
contract AltoToken is Ownable2Step, OFT {
    constructor(address endpoint, address owner) OFT("ALTO", "ALTO", endpoint, owner) Ownable(owner) {
        _mint(owner, 100_000_000 ether);
    }

    /// @dev we need to override the _transferOwnership function as inherited contracts use Ownable
    function _transferOwnership(address newOwner) internal virtual override(Ownable, Ownable2Step) {
        super._transferOwnership(newOwner);
    }

    /// @dev we need to override the transferOwnership function as inherited contracts use Ownable
    function transferOwnership(address newOwner) public virtual override(Ownable, Ownable2Step) {
        super.transferOwnership(newOwner);
    }
}
