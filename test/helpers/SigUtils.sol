// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Authorization} from "@alto/utils/interfaces/common/IAuth.sol";

import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

struct Permit {
    address owner;
    address spender;
    uint256 value;
    uint256 nonce;
    uint256 deadline;
}

library SigUtils {
    bytes32 constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    function toTypedDataHash(bytes32 domainSeparator, Permit memory permit) internal pure returns (bytes32) {
        return MessageHashUtils.toTypedDataHash(
            domainSeparator,
            keccak256(
                abi.encode(PERMIT_TYPEHASH, permit.owner, permit.spender, permit.value, permit.nonce, permit.deadline)
            )
        );
    }

    function toTypedDataHash(bytes32 authorizationTypeHash, bytes32 domainSeparator, Authorization memory authorization)
        internal
        pure
        returns (bytes32)
    {
        return MessageHashUtils.toTypedDataHash(
            domainSeparator,
            keccak256(
                abi.encode(
                    authorizationTypeHash,
                    authorization.owner,
                    authorization.spender,
                    authorization.isAuthorizedStatus,
                    authorization.nonce,
                    authorization.deadline
                )
            )
        );
    }
}
