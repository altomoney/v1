// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {PegResponsiveExponentialIrmConfig} from "@alto/lending/interfaces/IPegResponsiveExponentialIrm.sol";
import {PegResponsiveExponentialIrm} from "@alto/lending/irm/PegResponsiveExponentialIrm.sol";
import {AltoOwnable2Step, Ownable} from "@alto/utils/AltoOwnable2Step.sol";

/// @title Owner Peg Responsive Exponential Interest Rate Model Factory
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice Deterministically deploys PegResponsiveExponentialIrms owned by the factory owner.
/// @dev A newly deployed IRM has a permissionless, one-time `setMarket`. Deploy it and wire it to its market
///      atomically so another account cannot consume that initialization first.
contract OwnerPegResponsiveExponentialIrmFactory is AltoOwnable2Step {
    struct Deployment {
        address irm;
        address owner;
        address pegOracle;
    }

    address public pegOracle;

    mapping(address market => Deployment) public deployments;

    event SetPegOracle(address indexed oldPegOracle, address indexed newPegOracle);
    event PegResponsiveExponentialIrmDeployed(
        address indexed market, address indexed irm, address indexed owner, address pegOracle
    );

    constructor(address initialOwner, address initialPegOracle) Ownable(initialOwner) {
        _setPegOracle(initialPegOracle);
    }

    /// @notice Changes the peg oracle used for future IRM deployments.
    function setPegOracle(address newPegOracle) external onlyOwner {
        _setPegOracle(newPegOracle);
    }

    /// @notice Deploys one IRM for a market, or returns an exact prior deployment.
    function deploy(address market, PegResponsiveExponentialIrmConfig calldata config)
        external
        onlyOwner
        returns (address irm)
    {
        require(market != address(0), "Invalid market");

        address irmOwner = owner();
        Deployment memory existing = deployments[market];
        if (existing.irm != address(0)) {
            _validateExisting(existing, _predictIrmAddress(market, existing.pegOracle, config, irmOwner), irmOwner);
            return existing.irm;
        }

        address currentPegOracle = pegOracle;
        irm = address(new PegResponsiveExponentialIrm{salt: _salt(market)}(currentPegOracle, config, irmOwner));
        deployments[market] = Deployment(irm, irmOwner, currentPegOracle);

        emit PegResponsiveExponentialIrmDeployed(market, irm, irmOwner, currentPegOracle);
    }

    function predictIrmAddress(address market, PegResponsiveExponentialIrmConfig memory config)
        public
        view
        returns (address)
    {
        require(market != address(0), "Invalid market");

        address irmOwner = owner();
        Deployment memory existing = deployments[market];
        if (existing.irm != address(0)) {
            _validateExisting(existing, _predictIrmAddress(market, existing.pegOracle, config, irmOwner), irmOwner);
            return existing.irm;
        }

        return _predictIrmAddress(market, pegOracle, config, irmOwner);
    }

    function _setPegOracle(address newPegOracle) private {
        require(newPegOracle != address(0), "Invalid peg oracle");
        emit SetPegOracle(pegOracle, newPegOracle);
        pegOracle = newPegOracle;
    }

    function _predictIrmAddress(
        address market,
        address oracle,
        PegResponsiveExponentialIrmConfig memory config,
        address irmOwner
    ) private view returns (address) {
        bytes32 initCodeHash = keccak256(
            abi.encodePacked(type(PegResponsiveExponentialIrm).creationCode, abi.encode(oracle, config, irmOwner))
        );

        return address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), _salt(market), initCodeHash))))
        );
    }

    function _validateExisting(Deployment memory existing, address expectedIrm, address irmOwner) private view {
        require(existing.irm == expectedIrm && existing.owner == irmOwner, "Market already deployed");
        require(existing.irm.code.length != 0 && Ownable(existing.irm).owner() == irmOwner, "Invalid deployment");
    }

    function _salt(address market) private pure returns (bytes32) {
        return keccak256(abi.encode(market));
    }
}
