// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Authorization} from "tap-utils/interfaces/common/IAuth.sol";

// TODO v5 here is temporary, can remove once we update our main openzeppelin version to v5
import {MessageHashUtils} from "@openzeppelin/contracts-v5/utils/cryptography/MessageHashUtils.sol";

import {DOMAIN_TYPEHASH, AUTHORIZATION_TYPEHASH, PERMIT_TYPEHASH} from "@alto-monorepo/utils/utils/Constants.sol";

struct Permit {
    address owner;
    address spender;
    uint256 value;
    uint256 nonce;
    uint256 deadline;
}

library SigUtils {
    function toTypedDataHash(bytes32 domainSeparator, Permit memory permit) internal pure returns (bytes32) {
        return MessageHashUtils.toTypedDataHash(
            domainSeparator,
            keccak256(
                abi.encode(PERMIT_TYPEHASH, permit.owner, permit.spender, permit.value, permit.nonce, permit.deadline)
            )
        );
    }

    function toTypedDataHash(bytes32 domainSeparator, Authorization memory authorization)
        internal
        pure
        returns (bytes32)
    {
        return MessageHashUtils.toTypedDataHash(
            domainSeparator,
            keccak256(
                abi.encode(
                    AUTHORIZATION_TYPEHASH,
                    authorization.authorizer,
                    authorization.authorized,
                    authorization.isAuthorized,
                    authorization.nonce,
                    authorization.deadline
                )
            )
        );
    }
}
