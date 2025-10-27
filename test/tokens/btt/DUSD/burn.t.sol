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
        _;
    }

    modifier givenCallerIsAuthorizedBurner() {
        _setupBurner();
        // Also set up the burner as a minter so they can burn
        vm.startPrank(OWNER);
        dusd.setMinterStatus(BURNER, true);
        dusd.setMinterCeiling(BURNER, MINT_AMOUNT * 2);
        vm.stopPrank();
        _;
    }

    modifier whenBurnerHasMintedEnoughToBurn() {
        // Mint tokens using BURNER as minter so they have enough to burn
        vm.prank(BURNER);
        dusd.mint(USER, MINT_AMOUNT);
        _;
    }

    modifier whenAmountIsZero() {
        _;
    }

    function test_RevertWhen_ContractIsPaused() external givenContractIsPaused {
        vm.startPrank(BURNER);
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSE_TYPE));
        dusd.burn(USER, BURN_AMOUNT);
        vm.stopPrank();
    }

    function test_RevertWhen_CallerIsNotAuthorizedBurner() external givenCallerIsNotAuthorizedBurner {
        vm.startPrank(NON_OWNER);
        vm.expectRevert(IDUSD.DUSDNotAuthorized.selector);
        dusd.burn(USER, BURN_AMOUNT);
        vm.stopPrank();
    }

    function test_RevertWhen_BurnerHasNotMintedEnoughToBurn() external givenCallerIsAuthorizedBurner {
        vm.startPrank(BURNER);
        vm.expectRevert(IDUSD.DUSDInvalidInput.selector);
        dusd.burn(USER, BURN_AMOUNT);
        vm.stopPrank();
    }

    function test_RevertWhen_FromAddressIsZeroAddress()
        external
        givenCallerIsAuthorizedBurner
        whenBurnerHasMintedEnoughToBurn
    {
        vm.startPrank(BURNER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        dusd.burn(address(0), BURN_AMOUNT);
        vm.stopPrank();
    }

    function test_RevertWhen_AmountExceedsBalance()
        external
        givenCallerIsAuthorizedBurner
        whenBurnerHasMintedEnoughToBurn
    {
        uint256 excessiveAmount = MINT_AMOUNT + 1;

        vm.startPrank(BURNER);
        vm.expectRevert(IDUSD.DUSDInvalidInput.selector);
        dusd.burn(USER, excessiveAmount);
        vm.stopPrank();
    }

    function test_WhenAmountIsZero()
        external
        givenCallerIsAuthorizedBurner
        whenBurnerHasMintedEnoughToBurn
        whenAmountIsZero
    {
        uint256 initialSupply = dusd.totalSupply();
        uint256 initialBalance = dusd.balanceOf(USER);
        (uint256 initialMinted,) = dusd.minterConfig(BURNER);

        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(USER, address(0), 0);

        vm.startPrank(BURNER);
        dusd.burn(USER, 0);
        vm.stopPrank();

        // it should burn zero tokens successfully
        assertEq(dusd.totalSupply(), initialSupply);
        assertEq(dusd.balanceOf(USER), initialBalance);

        // it should not decrease minter's minted amount
        (uint256 finalMinted,) = dusd.minterConfig(BURNER);
        assertEq(finalMinted, initialMinted);
    }

    function test_WhenAmountIsValidAndWithinBalance()
        external
        givenCallerIsAuthorizedBurner
        whenBurnerHasMintedEnoughToBurn
    {
        uint256 initialSupply = dusd.totalSupply();
        uint256 initialBalance = dusd.balanceOf(USER);
        (uint256 initialMinted,) = dusd.minterConfig(BURNER);

        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(USER, address(0), BURN_AMOUNT);

        vm.startPrank(BURNER);
        dusd.burn(USER, BURN_AMOUNT);
        vm.stopPrank();

        // it should burn the specified amount from the account
        assertEq(dusd.balanceOf(USER), initialBalance - BURN_AMOUNT);

        // it should decrease total supply by the amount
        assertEq(dusd.totalSupply(), initialSupply - BURN_AMOUNT);

        // it should decrease minter's minted amount by the amount
        (uint256 finalMinted,) = dusd.minterConfig(BURNER);
        assertEq(finalMinted, initialMinted - BURN_AMOUNT);
    }

    function test_WhenBurningEntireBalance() external givenCallerIsAuthorizedBurner whenBurnerHasMintedEnoughToBurn {
        uint256 initialSupply = dusd.totalSupply();
        uint256 userBalance = dusd.balanceOf(USER);
        (uint256 initialMinted,) = dusd.minterConfig(BURNER);

        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(USER, address(0), userBalance);

        vm.startPrank(BURNER);
        dusd.burn(USER, userBalance);
        vm.stopPrank();

        // it should burn all tokens and set balance to zero
        assertEq(dusd.balanceOf(USER), 0);
        assertEq(dusd.totalSupply(), initialSupply - userBalance);

        // it should decrease minter's minted amount by the amount
        (uint256 finalMinted,) = dusd.minterConfig(BURNER);
        assertEq(finalMinted, initialMinted - userBalance);
    }
}
