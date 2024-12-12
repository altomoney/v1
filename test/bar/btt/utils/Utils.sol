// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// external
import {IERC20, IStrictERC20} from "@boringcrypto/boring-solidity/contracts/libraries/BoringERC20.sol";

// utils
import {Constants} from "./Constants.sol";

// tapioca

import {ICluster} from "tap-utils/interfaces/periph/ICluster.sol";


import {Cluster} from "tap-utils/Cluster/Cluster.sol";

import {Penrose} from "tapioca-bar/Penrose.sol";

import {ERC20PermitStruct, ERC20PermitApprovalMsg} from "tap-utils/interfaces/periph/ITapiocaOmnichainEngine.sol";

// tests
import {OracleMock_test} from "../mocks/OracleMock_test.sol";
import {ERC20Mock_test} from "../mocks/ERC20Mock_test.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Helper contract containing utilities.
abstract contract Utils is Test, Constants {
    // ************************ //
    // *** GENERAL: HELPERS *** //
    // ************************ //
    /// @dev Stops the active prank and sets a new one.
    function _resetPrank(address msgSender) internal {
        vm.stopPrank();
        vm.startPrank(msgSender);
    }

    // ********************** //
    // *** DEPLOY HELPERS *** //
    // ********************** //
    // ERC20Mock_test
    function _createToken(string memory _name) internal returns (ERC20Mock_test) {
        ERC20Mock_test _token = new ERC20Mock_test(_name, _name);
        vm.label(address(_token), _name);
        return _token;
    }

    // OracleMock_test; allows changing the current rate to simulate multiple situations
    function _createOracle(string memory _name) internal returns (OracleMock_test) {
        OracleMock_test _oracle = new OracleMock_test(_name, _name, 1 ether);
        vm.label(address(_oracle), _name);
        return _oracle;
    }

    // Creates user from Private key
    function _createUser(uint256 _key, string memory _name) internal returns (address) {
        address _user = vm.addr(_key);
        vm.deal(_user, LARGE_AMOUNT);
        vm.label(_user, _name);
        return _user;
    }

    // Creates real Cluster
    function _createCluster(address _owner) internal returns (Cluster) {
        Cluster cluster = new Cluster(0, _owner);
        vm.label(address(cluster), "Cluster Test");
        return cluster;
    }

    // Creates real Penrose
    function _createPenrose(
        address _cluster,
        address _tapToken,
        address _mainToken,
        address _owner
    ) internal returns (Penrose) {
        Penrose penrose = new Penrose(
            ICluster(_cluster),
            IERC20(_tapToken),
            IERC20(_mainToken),
            _owner
        );
        vm.label(address(penrose), "Penrose");
        return penrose;
    }

    // ************************ //
    // *** APPROVAL HELPERS *** //
    // ************************ //
    function _approveViaERC20(address token, address from, address operator, uint256 amount) internal {
        _resetPrank({msgSender: from});
        IERC20(token).approve(address(operator), amount);
    }

    // ******************** //
    // *** DATA HELPERS *** //
    // ******************** //
    function _createErc20PermitStruct(address user, address spender, uint256 amount, uint256 nonce)
        internal
        pure
        returns (ERC20PermitStruct memory permit_)
    {
        permit_ = ERC20PermitStruct({owner: user, spender: spender, value: amount, nonce: nonce, deadline: 1 days});
    }

    function __getERC20PermitData(ERC20PermitStruct memory _permit, bytes32 _digest, address _token, uint256 _pkSigner)
        internal
        pure
        returns (ERC20PermitApprovalMsg memory permitApproval_)
    {
        (uint8 v_, bytes32 r_, bytes32 s_) = vm.sign(_pkSigner, _digest);

        permitApproval_ = ERC20PermitApprovalMsg({
            token: _token,
            owner: _permit.owner,
            spender: _permit.spender,
            value: _permit.value,
            deadline: _permit.deadline,
            v: v_,
            r: r_,
            s: s_
        });
    }
}
