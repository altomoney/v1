// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {IAltoVaultErrors} from "@alto/lending/interfaces/IAltoVault.sol";
import {AltoVault} from "@alto/lending/vault/AltoVault.sol";

/// @dev Tests that `maxDeposit` and `deposit` account for the underlying markets' supply caps.
contract VaultCapacityForkTest is Test {
    uint256 internal constant FORK_BLOCK = 26_017_288;

    address internal constant VAULT = 0x6954785783c6EE90400fA715E591fBbA0D0Bd749;
    address internal constant DUSD = 0x63d74d22E689C715a04F2C13962b1f77F443d35b;
    address internal constant MARKET_REGISTRY = 0xBd45d50611c38E35dD1D1119077De1E988eD2257;

    IERC4626 internal constant vault = IERC4626(VAULT);
    IERC20 internal constant dusd = IERC20(DUSD);

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("ethereum"), FORK_BLOCK);

        // Preserve the deployed vault's storage while testing the locally compiled fix.
        AltoVault fixedVault = new AltoVault(address(this), 0, DUSD, "Alto Vault", "AV", MARKET_REGISTRY);
        vm.etch(VAULT, address(fixedVault).code);

        assertEq(vault.asset(), DUSD, "unexpected vault asset");
    }

    /// @dev Before the fix, depositing the quoted maximum reverted with AllCapsReached(). It now succeeds.
    function testFork_DepositMaxDepositSucceedsAfterMarketSupplyCapFix() external {
        uint256 quotedMax = vault.maxDeposit(address(this));

        assertGt(quotedMax, 0, "zero maxDeposit quote");

        deal(DUSD, address(this), quotedMax + 1);
        assertTrue(dusd.approve(VAULT, quotedMax + 1), "approve failed");
        uint256 balanceBefore = dusd.balanceOf(address(this));

        vm.expectRevert(IAltoVaultErrors.AllCapsReached.selector);
        vault.deposit(quotedMax + 1, address(this));

        uint256 previewedShares = vault.previewDeposit(quotedMax);
        uint256 shares = vault.deposit(quotedMax, address(this));

        assertEq(shares, previewedShares, "received shares differ from previewDeposit");
        assertEq(dusd.balanceOf(address(this)), balanceBefore - quotedMax, "DUSD balance not reduced by quoted maximum");
    }
}
