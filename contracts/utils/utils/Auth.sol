// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IAuth, Authorization, Signature} from "../interfaces/common/IAuth.sol";
import {AUTHORIZATION_TYPEHASH} from "./Constants.sol";

abstract contract Auth is IAuth {
    mapping(address => mapping(address => bool)) public isAuthorized;
    mapping(address => uint256) public nonce;

    /// @dev Sets the authorization for `authorized` to `newIsAuthorized`.
    /// @param authorized The address to authorize.
    /// @param newIsAuthorized The new authorization status.
    function setAuthorization(address authorized, bool newIsAuthorized) external {
        require(newIsAuthorized != isAuthorized[msg.sender][authorized], ALREADY_SET());

        isAuthorized[msg.sender][authorized] = newIsAuthorized;

        emit SetAuthorization(msg.sender, msg.sender, authorized, newIsAuthorized);
    }

    /// @dev Sets the authorization for `authorized` to `newIsAuthorized` using a signature.
    /// @param authorization The authorization to set.
    /// @param signature The signature of the authorizer.
    function setAuthorizationWithSig(Authorization memory authorization, Signature calldata signature) external {
        /// Do not check whether authorization is already set because the nonce increment is a desired side effect.
        require(block.timestamp <= authorization.deadline, SIGNATURE_EXPIRED());
        require(authorization.nonce == nonce[authorization.authorizer]++, INVALID_NONCE());

        bytes32 hashStruct = keccak256(abi.encode(AUTHORIZATION_TYPEHASH, authorization));
        bytes32 digest = keccak256(bytes.concat("\x19\x01", _getDomainSeparator(), hashStruct));
        address signatory = ecrecover(digest, signature.v, signature.r, signature.s);

        require(signatory != address(0) && authorization.authorizer == signatory, INVALID_SIGNATURE());

        emit IncrementNonce(msg.sender, authorization.authorizer, authorization.nonce);

        isAuthorized[authorization.authorizer][authorization.authorized] = authorization.isAuthorized;

        emit SetAuthorization(
            msg.sender, authorization.authorizer, authorization.authorized, authorization.isAuthorized
        );
    }

    /// @dev Returns whether the sender is authorized to manage `onBehalf`'s positions.
    function _isSenderAuthorized(address onBehalf) internal view returns (bool) {
        return msg.sender == onBehalf || isAuthorized[onBehalf][msg.sender];
    }

    function _getDomainSeparator() internal view virtual returns (bytes32);
}
