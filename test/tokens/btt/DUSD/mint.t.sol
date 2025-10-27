// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {DUSDCommon} from "./DUSDCommon.t.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";
import {IPausable} from "@alto/utils/Pausable.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DUSDMint is DUSDCommon {
    modifier givenContractIsPaused() {
        _pauseContract();
        _;
    }

    modifier givenCallerIsNotAuthorizedMinter() {
        // Don't set up minter, so caller is not authorized
        _;
    }

    modifier givenCallerIsAuthorizedMinter() {
        _setupMinter();
        _;
    }

    function test_RevertWhen_ContractIsPaused() external givenContractIsPaused {
        _setupMinter();

        vm.prank(MINTER);
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSE_TYPE));
        dusd.mint(USER, MINT_AMOUNT);
    }

    function test_RevertWhen_CallerIsNotAuthorizedMinter() external givenCallerIsNotAuthorizedMinter {
        vm.prank(NON_OWNER);
        vm.expectRevert(IDUSD.DUSDNotAuthorized.selector);
        dusd.mint(USER, MINT_AMOUNT);
    }

    function test_RevertWhen_ToAddressIsZeroAddress() external givenCallerIsAuthorizedMinter {
        vm.prank(MINTER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        dusd.mint(address(0), MINT_AMOUNT);
    }

    function test_WhenAmountIsZero() external givenCallerIsAuthorizedMinter {
        uint256 initialSupply = dusd.totalSupply();
        uint256 initialBalance = dusd.balanceOf(USER);

        vm.prank(MINTER);
        dusd.mint(USER, 0);

        // it should mint zero tokens successfully
        assertEq(dusd.totalSupply(), initialSupply);
        assertEq(dusd.balanceOf(USER), initialBalance);
    }

    function test_WhenAmountIsValid() external givenCallerIsAuthorizedMinter {
        uint256 initialSupply = dusd.totalSupply();
        uint256 initialBalance = dusd.balanceOf(USER);

        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(address(0), USER, MINT_AMOUNT);

        vm.prank(MINTER);
        dusd.mint(USER, MINT_AMOUNT);

        // it should mint the specified amount to the recipient
        assertEq(dusd.balanceOf(USER), initialBalance + MINT_AMOUNT);

        // it should increase total supply by the amount
        assertEq(dusd.totalSupply(), initialSupply + MINT_AMOUNT);
    }

    function test_WhenMintingToContractAddress() external givenCallerIsAuthorizedMinter {
        address contractAddress = address(this);
        uint256 initialSupply = dusd.totalSupply();
        uint256 initialBalance = dusd.balanceOf(contractAddress);

        vm.prank(MINTER);
        dusd.mint(contractAddress, MINT_AMOUNT);

        // it should mint tokens successfully to contract
        assertEq(dusd.balanceOf(contractAddress), initialBalance + MINT_AMOUNT);
        assertEq(dusd.totalSupply(), initialSupply + MINT_AMOUNT);
    }
}
