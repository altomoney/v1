// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// external
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// utils
import {Constants} from "./Constants.sol";

// Tapioca


import {Cluster} from "tap-utils/Cluster/Cluster.sol";


// tests
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
    function _createToken(string memory _name, uint8 _decimals) internal returns (ERC20Mock_test) {
        ERC20Mock_test _token = new ERC20Mock_test(_name, _name, _decimals);
        vm.label(address(_token), _name);
        return _token;
    }

    // Creates user from Private key
    function _createUser(uint256 _key, string memory _name) internal returns (address) {
        address _user = vm.addr(_key);
        vm.deal(_user, LARGE_AMOUNT);
        vm.label(_user, _name);
        return _user;
    }

    // Creates real Pearlmit
    function _createPearlmit(address _owner) internal returns (Pearlmit) {
        Pearlmit pearlmit = new Pearlmit("Pearlmit Test", "1", _owner, 0);
        vm.label(address(pearlmit), "Pearlmit Test");
        return pearlmit;
    }

    // Creates real Cluster
    function _createCluster(address _owner) internal returns (Cluster) {
        Cluster cluster = new Cluster(0, _owner);
        vm.label(address(cluster), "Cluster Test");
        return cluster;
    }


    // ************************ //
    // *** APPROVAL HELPERS *** //
    // ************************ //

    function _approveViaERC20(address token, address from, address operator, uint256 amount) internal {
        _resetPrank({msgSender: from});
        IERC20(token).approve(address(operator), amount);
    }

    function _approveViaPearlmit(
        uint256 tokenType,
        address token,
        IPearlmit pearlmit,
        address from,
        address operator,
        uint256 amount,
        uint256 expiration,
        uint256 tokenId
    ) internal {
        // Reset prank
        _resetPrank({msgSender: from});

        // Approve via pearlmit
        pearlmit.approve(tokenType, token, tokenId, operator, uint200(amount), uint48(expiration));
    }

    function _approveYieldBoxAssetId(YieldBox yieldBox, address from, address operator, uint256 assetId) internal {
        _resetPrank({msgSender: from});
        yieldBox.setApprovalForAsset(operator, assetId, true);
    }

    function _approveYieldBoxForAll(YieldBox yieldBox, address from, address operator) internal {
        _resetPrank({msgSender: from});
        yieldBox.setApprovalForAll(operator, true);
    }
}
