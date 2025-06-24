// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct Authorization {
    address owner;
    address spender;
    bool isAuthorizedStatus;
    uint256 nonce;
    uint256 deadline;
}

struct Signature {
    uint8 v;
    bytes32 r;
    bytes32 s;
}

interface IAuth {
    /// @notice Emitted when the authorization is set.
    /// @param caller The address of the caller.
    /// @param owner The address of the owner.
    /// @param spender The address of the spender.
    /// @param isAuthorized The authorization status.
    event SetAuthorization(address indexed caller, address indexed owner, address indexed spender, bool isAuthorized);

    /// @notice Emitted when the nonce is incremented.
    /// @param caller The address of the caller.
    /// @param owner The address of the owner.
    /// @param nonce The nonce.
    event IncrementNonce(address indexed caller, address indexed owner, uint256 nonce);

    /// @notice Error thrown when the authorization is already set.
    error AuthAuthorizationAlreadySet();

    /// @notice Error thrown when the signature's deadline expired.
    error AuthSignatureExpired();

    /// @notice Error thrown when the nonce is invalid.
    error AuthInvalidNonce();

    /// @notice Error thrown when the signature is invalid because of various reasons.
    error AuthInvalidSignature();

    /// @dev Returns whether the sender is authorized to manage `owner`'s positions.
    /// @param owner The address of the owner.
    /// @param spender The address of the spender.
    /// @return isAuthorized Whether the sender is authorized to manage `owner`'s positions.
    function isAuthorized(address owner, address spender) external view returns (bool);

    /// @dev Returns the nonce for the owner.
    /// @param owner The address of the owner.
    /// @return nonce The nonce for the owner.
    function nonce(address owner) external view returns (uint256);

    /// @dev Sets the authorization for `spender` to `isAuthorizedStatus`.
    /// @param spender The address to set the authorization for.
    /// @param isAuthorizedStatus The authorization status to set.
    function setAuthorization(address spender, bool isAuthorizedStatus) external;

    /// @dev Sets the authorization for `spender` to `isAuthorizedStatus` status using a signature.
    /// @param authData The authorization to set.
    /// @param sigData The signature of the owner.
    function setAuthorizationWithSignature(Authorization memory authData, Signature calldata sigData) external;
}
