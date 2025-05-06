// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;


struct Authorization {
    address authorizer;
    address authorized;
    bool isAuthorized;
    uint256 nonce;
    uint256 deadline;
}

struct Signature {
    uint8 v;
    bytes32 r;
    bytes32 s;
}

interface IAuth {
    event SetAuthorization(address indexed caller, address indexed authorizer, address indexed authorized, bool isAuthorized);
    event IncrementNonce(address indexed caller, address indexed authorizer, uint256 nonce);

    error ALREADY_SET();
    error SIGNATURE_EXPIRED();
    error INVALID_NONCE();
    error INVALID_SIGNATURE();

    /// @dev Returns whether the sender is authorized to manage `onBehalf`'s positions.
    /// @param authorizer The address of the authorizer.
    /// @param authorized The address of the authorized address.
    /// @return isAuthorized Whether the sender is authorized to manage `onBehalf`'s positions.
    function isAuthorized(address authorizer, address authorized) external view returns (bool);

    /// @dev Returns the nonce for the authorizer.
    /// @param authorizer The address of the authorizer.
    /// @return nonce The nonce for the authorizer.
    function nonce(address authorizer) external view returns (uint256);

    /// @dev Sets the authorization for `authorized` to `newIsAuthorized`.
    /// @param authorized The address to authorize.
    /// @param newIsAuthorized The new authorization status.
    function setAuthorization(address authorized, bool newIsAuthorized) external;

    /// @dev Sets the authorization for `authorized` to `newIsAuthorized` using a signature.
    /// @param authorization The authorization to set.
    /// @param signature The signature of the authorizer.
    function setAuthorizationWithSig(Authorization memory authorization, Signature calldata signature) external;
}
