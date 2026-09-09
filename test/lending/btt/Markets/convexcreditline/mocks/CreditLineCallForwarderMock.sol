// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract CreditLineCallForwarderMock {
    address public immutable CALLBACK_TARGET;
    address public immutable CREDIT_ACCOUNT;

    constructor(address callbackTarget_, address creditAccount_) {
        CALLBACK_TARGET = callbackTarget_;
        CREDIT_ACCOUNT = creditAccount_;
    }

    fallback(bytes calldata) external returns (bytes memory) {
        (bool success, bytes memory reason) = CALLBACK_TARGET.call(
            abi.encodeWithSignature("repay(uint256,uint256,address)", uint256(1), uint256(0), CREDIT_ACCOUNT)
        );
        if (!success) {
            assembly ("memory-safe") {
                revert(add(reason, 0x20), mload(reason))
            }
        }
        return abi.encode(uint256(0), uint256(0));
    }
}
