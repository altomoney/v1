// SPDX-License-Identifier: UNLICENSED
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
    event SetAuthorization(address indexed caller, address indexed owner, address indexed spender, bool isAuthorized);
    event IncrementNonce(address indexed caller, address indexed owner, uint256 nonce);

    error AuthAuthorizationAlreadySet();
    error AuthSignatureExpired();
    error AuthInvalidNonce();
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
