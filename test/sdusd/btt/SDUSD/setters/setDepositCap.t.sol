// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

import {ISDUSDVaultErrors, ISDUSDVaultEvents} from "@alto/sdusd/interfaces/ISDUSDVault.sol";
import {SDUSDCommon} from "../SDUSDCommon.t.sol";

contract SDUSD_SetDepositCap_Test is SDUSDCommon {
    function test_RevertWhen_CallerIsNotOwner() public {
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER));
        vault.setDepositCap(INITIAL_DEPOSIT_CAP + 1);
    }

    function test_RevertWhen_NewDepositCapEqualsCurrentCap() public {
        vm.prank(ADMIN);
        vm.expectRevert(ISDUSDVaultErrors.SDUSDNoStateChange.selector);
        vault.setDepositCap(INITIAL_DEPOSIT_CAP);
    }

    function test_OwnerUpdatesCapWithoutChangingUsageAndEmits() public {
        uint256 usageBefore = vault.depositCapUsage();
        uint256 newCap = INITIAL_DEPOSIT_CAP + 1;

        vm.expectEmit(false, false, false, true, address(vault));
        emit ISDUSDVaultEvents.DepositCapUpdated(INITIAL_DEPOSIT_CAP, newCap);
        _setDepositCap(newCap);

        assertEq(vault.depositCap(), newCap);
        assertEq(vault.depositCapUsage(), usageBefore);
        assertEq(vault.maxDeposit(USER), newCap - usageBefore);
    }

    function test_OwnerCanSetCapToZeroAndDisableDepositsAndMints() public {
        _setDepositCap(0);

        assertEq(vault.depositCap(), 0);
        assertEq(vault.maxDeposit(USER), 0);
        assertEq(vault.maxMint(USER), 0);

        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxDeposit.selector, USER, 1, 0));
        vault.deposit(1, USER);
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxMint.selector, USER, 1, 0));
        vault.mint(1, USER);
    }

    function test_CapBelowUsageDisablesDepositsAndMintsWithoutBlockingWithdrawalsOrRedemptions() public {
        uint256 usageBefore = vault.depositCapUsage();
        _setDepositCap(usageBefore - 1);

        assertEq(vault.maxDeposit(USER), 0);
        assertEq(vault.maxMint(USER), 0);

        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxDeposit.selector, USER, 1, 0));
        vault.deposit(1, USER);
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxMint.selector, USER, 1, 0));
        vault.mint(1, USER);

        uint256 sharesToRedeem = vault.balanceOf(USER) / 2;
        vm.prank(USER);
        vault.redeem(sharesToRedeem, USER, USER);
        assertLt(vault.depositCapUsage(), usageBefore);
        assertEq(vault.maxDeposit(USER), vault.depositCap() - vault.depositCapUsage());
        assertGt(vault.maxDeposit(USER), 0);

        uint256 assetsToWithdraw = vault.maxWithdraw(USER);
        vm.prank(USER);
        vault.withdraw(assetsToWithdraw, USER, USER);
        assertEq(vault.balanceOf(USER), 0);
        assertEq(vault.depositCapUsage(), 0);
        assertEq(vault.maxDeposit(USER), vault.depositCap());
    }

    function test_CapAboveUsageExposesDifferenceAsHeadroom() public {
        uint256 usage = vault.depositCapUsage();
        uint256 newCap = usage + 123 ether;
        _setDepositCap(newCap);

        assertEq(vault.maxDeposit(USER), 123 ether);
    }
}
