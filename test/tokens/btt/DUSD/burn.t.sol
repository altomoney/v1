// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {DUSDCommon} from "./DUSDCommon.t.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";
import {IPausable} from "@alto/utils/Pausable.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DUSDBurn is DUSDCommon {
    modifier givenContractIsPaused() {
        _pauseContract();
        _;
    }

    modifier givenCallerIsNotAuthorizedBurner() {
        // Don't set up burner, so caller is not authorized
        _;
    }

    modifier givenCallerIsAuthorizedBurner() {
        _setupBurner();
        _;
    }

    function test_RevertWhen_ContractIsPaused() external {
        // First mint tokens while contract is not paused
        _setupBurner();
        _mintTokensToUser(MINT_AMOUNT);

        // Then pause the contract
        _pauseContract();

        vm.startPrank(BURNER);
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSE_TYPE));
        dusd.burn(USER, BURN_AMOUNT);
        vm.stopPrank();
    }

    function test_RevertWhen_CallerIsNotAuthorizedBurner() external givenCallerIsNotAuthorizedBurner {
        _mintTokensToUser(MINT_AMOUNT);

        vm.startPrank(NON_OWNER);
        vm.expectRevert(IDUSD.DUSDNotAuthorized.selector);
        dusd.burn(USER, BURN_AMOUNT);
        vm.stopPrank();
    }

    function test_RevertWhen_FromAddressIsZeroAddress() external givenCallerIsAuthorizedBurner {
        vm.startPrank(BURNER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        dusd.burn(address(0), BURN_AMOUNT);
        vm.stopPrank();
    }

    function test_RevertWhen_AmountExceedsBalance() external givenCallerIsAuthorizedBurner {
        _mintTokensToUser(MINT_AMOUNT);
        uint256 excessiveAmount = MINT_AMOUNT + 1;

        vm.startPrank(BURNER);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, USER, MINT_AMOUNT, excessiveAmount)
        );
        dusd.burn(USER, excessiveAmount);
        vm.stopPrank();
    }

    function test_WhenAmountIsZero() external givenCallerIsAuthorizedBurner {
        _mintTokensToUser(MINT_AMOUNT);
        uint256 initialSupply = dusd.totalSupply();
        uint256 initialBalance = dusd.balanceOf(USER);

        vm.startPrank(BURNER);
        dusd.burn(USER, 0);

        // it should burn zero tokens successfully
        assertEq(dusd.totalSupply(), initialSupply);
        assertEq(dusd.balanceOf(USER), initialBalance);
        vm.stopPrank();
    }

    function test_WhenAmountIsValidAndWithinBalance() external givenCallerIsAuthorizedBurner {
        _mintTokensToUser(MINT_AMOUNT);
        uint256 initialSupply = dusd.totalSupply();
        uint256 initialBalance = dusd.balanceOf(USER);

        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(USER, address(0), BURN_AMOUNT);

        vm.startPrank(BURNER);
        dusd.burn(USER, BURN_AMOUNT);

        // it should burn the specified amount from the account
        assertEq(dusd.balanceOf(USER), initialBalance - BURN_AMOUNT);

        // it should decrease total supply by the amount
        assertEq(dusd.totalSupply(), initialSupply - BURN_AMOUNT);
        vm.stopPrank();
    }

    function test_WhenBurningEntireBalance() external givenCallerIsAuthorizedBurner {
        _mintTokensToUser(MINT_AMOUNT);
        uint256 initialSupply = dusd.totalSupply();
        uint256 userBalance = dusd.balanceOf(USER);

        vm.startPrank(BURNER);
        dusd.burn(USER, userBalance);

        // it should burn all tokens and set balance to zero
        assertEq(dusd.balanceOf(USER), 0);
        assertEq(dusd.totalSupply(), initialSupply - userBalance);
        vm.stopPrank();
    }
}
