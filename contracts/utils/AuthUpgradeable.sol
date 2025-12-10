// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.19;

import {IAuth, Authorization, Signature} from "./interfaces/IAuth.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

/// @title AuthUpgradeable
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice A contract that allows for authorization of addresses (upgradeable version).
/// @dev This is used in several Alto contracts to authorize addresses to manage positions.
/// The main purpose is to allow for transaction bundling.
abstract contract AuthUpgradeable is IAuth, EIP712Upgradeable {
    bytes32 internal constant _AUTHORIZATION_TYPEHASH = keccak256(
        "Authorization(address owner,address spender,bool isAuthorizedStatus,uint256 nonce,uint256 deadline)"
    );

    /// @inheritdoc IAuth
    mapping(address => mapping(address => bool)) public isAuthorized;
    /// @inheritdoc IAuth
    mapping(address => uint256) public nonce;

    function __Auth_init() internal onlyInitializing {
        __EIP712_init("Alto", "1");
    }

    /// @inheritdoc IAuth
    function setAuthorization(address spender, bool isAuthorizedStatus) external {
        if (isAuthorizedStatus == isAuthorized[msg.sender][spender]) {
            revert AuthAuthorizationAlreadySet();
        }

        isAuthorized[msg.sender][spender] = isAuthorizedStatus;

        emit SetAuthorization(msg.sender, msg.sender, spender, isAuthorizedStatus);
    }

    /// @inheritdoc IAuth
    function setAuthorizationWithSignature(Authorization memory authData, Signature calldata sigData) external {
        if (block.timestamp > authData.deadline) {
            revert AuthSignatureExpired();
        }
        if (authData.nonce != nonce[authData.owner]++) {
            revert AuthInvalidNonce();
        }

        bytes32 structHash = keccak256(abi.encode(_AUTHORIZATION_TYPEHASH, authData));
        bytes32 hash = _hashTypedDataV4(structHash);

        bool isValid = SignatureChecker.isValidSignatureNow(
            authData.owner, hash, abi.encodePacked(sigData.r, sigData.s, sigData.v)
        );
        if (!isValid) {
            revert AuthInvalidSignature();
        }

        isAuthorized[authData.owner][authData.spender] = authData.isAuthorizedStatus;

        emit IncrementNonce(msg.sender, authData.owner, authData.nonce);
        emit SetAuthorization(msg.sender, authData.owner, authData.spender, authData.isAuthorizedStatus);
    }

    /// @dev Returns whether the sender is authorized to manage `owner`'s positions.
    function _isSenderAuthorized(address owner) internal view returns (bool) {
        return msg.sender == owner || isAuthorized[owner][msg.sender];
    }
}
