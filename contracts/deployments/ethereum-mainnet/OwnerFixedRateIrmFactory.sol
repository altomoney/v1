// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {AltoOwnable2Step, Ownable} from "@alto/utils/AltoOwnable2Step.sol";

/// @title Owner Fixed Rate Interest Rate Model Factory
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice Deterministically deploys FixedRateIrms owned by the factory owner.
/// @dev A newly deployed IRM has a permissionless, one-time `setMarket`. Deploy it and wire it to its market
///      atomically so another account cannot consume that initialization first.
contract OwnerFixedRateIrmFactory is AltoOwnable2Step {
    struct Deployment {
        address irm;
        address owner;
        uint256 borrowRate;
    }

    mapping(address market => mapping(uint256 version => Deployment)) public deployments;

    event FixedRateIrmDeployed(
        address indexed market, address indexed irm, address indexed owner, uint256 borrowRate, uint256 version
    );

    constructor(address initialOwner) Ownable(initialOwner) {}

    /// @notice Deploys one immutable FixedRateIrm for a market version, or returns an exact prior deployment.
    function deploy(address market, uint256 version, uint256 borrowRate)
        external
        onlyOwner
        returns (address fixedRateIrm)
    {
        require(market != address(0), "Invalid market");

        address irmOwner = owner();
        Deployment memory existing = deployments[market][version];
        if (existing.irm != address(0)) {
            require(existing.owner == irmOwner && existing.borrowRate == borrowRate, "Version already used");
            require(existing.irm.code.length != 0 && Ownable(existing.irm).owner() == irmOwner, "Invalid deployment");
            return existing.irm;
        }

        fixedRateIrm = address(new FixedRateIrm{salt: _salt(market, version)}(borrowRate, irmOwner));
        deployments[market][version] = Deployment(fixedRateIrm, irmOwner, borrowRate);

        emit FixedRateIrmDeployed(market, fixedRateIrm, irmOwner, borrowRate, version);
    }

    function predictIrmAddress(address market, uint256 version, uint256 borrowRate) public view returns (address) {
        address irmOwner = owner();
        Deployment memory existing = deployments[market][version];
        if (existing.irm != address(0)) {
            require(existing.owner == irmOwner && existing.borrowRate == borrowRate, "Version already used");
            return existing.irm;
        }

        bytes32 initCodeHash =
            keccak256(abi.encodePacked(type(FixedRateIrm).creationCode, abi.encode(borrowRate, irmOwner)));

        return address(
            uint160(
                uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), _salt(market, version), initCodeHash)))
            )
        );
    }

    function _salt(address market, uint256 version) private pure returns (bytes32) {
        return keccak256(abi.encode(market, version));
    }
}
