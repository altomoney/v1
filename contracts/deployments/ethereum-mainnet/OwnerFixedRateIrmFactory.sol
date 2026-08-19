// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {AltoOwnable2Step, Ownable} from "@alto/utils/AltoOwnable2Step.sol";

/// @notice Deterministically deploys FixedRateIrms owned by the caller-designated owner.
/// @dev Only the factory owner can consume the global nonce. The factory intentionally does not bind
///      the IRM to a market; a later `market.setIrm(irm, false)` call performs the one-time binding.
contract OwnerFixedRateIrmFactory is AltoOwnable2Step {
    uint256 public nonce;

    event FixedRateIrmDeployed(
        address indexed market,
        address indexed irm,
        address indexed initialOwner,
        uint256 borrowRate,
        uint256 deploymentNonce
    );

    constructor(address initialOwner) Ownable(initialOwner) {}

    /// @notice Deploys, or returns, the FixedRateIrm at the next deterministic nonce.
    function deploy(address market, uint256 borrowRate, address initialOwner)
        external
        onlyOwner
        returns (address fixedRateIrm)
    {
        uint256 deploymentNonce = nonce;
        fixedRateIrm = predictIrmAddress(borrowRate, initialOwner, deploymentNonce);
        nonce = deploymentNonce + 1;

        // Check before CREATE2 so an occupied deterministic address does not revert this call.
        if (fixedRateIrm.code.length != 0) return fixedRateIrm;

        fixedRateIrm = address(new FixedRateIrm{salt: bytes32(deploymentNonce)}(borrowRate, initialOwner));

        emit FixedRateIrmDeployed(market, fixedRateIrm, initialOwner, borrowRate, deploymentNonce);
    }

    /// @notice Predicts the CREATE2 address for a borrow rate, initial owner, and factory nonce.
    function predictIrmAddress(uint256 borrowRate, address initialOwner, uint256 deploymentNonce)
        public
        view
        returns (address)
    {
        bytes32 initCodeHash =
            keccak256(abi.encodePacked(type(FixedRateIrm).creationCode, abi.encode(borrowRate, initialOwner)));

        return address(
            uint160(
                uint256(
                    keccak256(abi.encodePacked(bytes1(0xff), address(this), bytes32(deploymentNonce), initCodeHash))
                )
            )
        );
    }
}
