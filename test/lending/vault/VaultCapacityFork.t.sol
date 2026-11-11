// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Fork} from "@alto-test/helpers/Fork.sol";

import {Test} from "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {IAltoVaultErrors} from "@alto/lending/interfaces/IAltoVault.sol";
import {AltoVault} from "@alto/lending/vault/AltoVault.sol";

/// @dev Tests against mainnet state that `maxDeposit` and `maxMint` account for the underlying markets' supply caps.
/// @dev At both pinned blocks the two queued markets had a supply cap with less room than the vault's own caps.
contract VaultCapacityForkTest is Test {
    uint256 internal constant FORK_BLOCK = 26_017_288;
    uint256 internal constant EARLIER_FORK_BLOCK = 26_004_578;

    address internal constant VAULT = 0x6954785783c6EE90400fA715E591fBbA0D0Bd749;
    address internal constant DUSD = 0x63d74d22E689C715a04F2C13962b1f77F443d35b;
    address internal constant MARKET_REGISTRY = 0xBd45d50611c38E35dD1D1119077De1E988eD2257;

    IERC4626 internal constant vault = IERC4626(VAULT);
    IERC20 internal constant dusd = IERC20(DUSD);

    /// @dev The vault deployed at the pinned block quoted more than it accepted.
    function testFork_DeployedVaultQuotedMoreThanItAccepted() external {
        Fork.selectEthereum(FORK_BLOCK);

        uint256 quotedMax = vault.maxDeposit(address(this));

        deal(DUSD, address(this), quotedMax);
        dusd.approve(VAULT, quotedMax);

        vm.expectRevert(IAltoVaultErrors.AllCapsReached.selector);
        vault.deposit(quotedMax, address(this));
    }

    function testFork_DepositMaxDeposit() external {
        _testDepositMaxDeposit(FORK_BLOCK);
    }

    function testFork_DepositMaxDepositAtEarlierBlock() external {
        _testDepositMaxDeposit(EARLIER_FORK_BLOCK);
    }

    function testFork_MintMaxMint() external {
        _selectForkWithLocalVaultCode(FORK_BLOCK);

        uint256 quotedMaxShares = vault.maxMint(address(this));

        assertGt(quotedMaxShares, 0, "zero maxMint quote");

        deal(DUSD, address(this), vault.previewMint(quotedMaxShares + 1));
        dusd.approve(VAULT, type(uint256).max);
        uint256 balanceBefore = dusd.balanceOf(address(this));

        vm.expectRevert(IAltoVaultErrors.AllCapsReached.selector);
        vault.mint(quotedMaxShares + 1, address(this));

        uint256 previewedAssets = vault.previewMint(quotedMaxShares);
        uint256 assets = vault.mint(quotedMaxShares, address(this));

        assertEq(assets, previewedAssets, "paid assets differ from previewMint");
        assertEq(dusd.balanceOf(address(this)), balanceBefore - assets, "DUSD balance not reduced by paid assets");
        assertEq(vault.maxMint(address(this)), 0, "supply capacity remains");
    }

    function _testDepositMaxDeposit(uint256 blockNumber) internal {
        uint256 deployedQuote = _selectForkWithLocalVaultCode(blockNumber);

        uint256 quotedMax = vault.maxDeposit(address(this));

        assertGt(quotedMax, 0, "zero maxDeposit quote");
        assertLt(quotedMax, deployedQuote, "quote not reduced by the market supply caps");

        deal(DUSD, address(this), quotedMax + 1);
        dusd.approve(VAULT, quotedMax + 1);
        uint256 balanceBefore = dusd.balanceOf(address(this));

        vm.expectRevert(IAltoVaultErrors.AllCapsReached.selector);
        vault.deposit(quotedMax + 1, address(this));

        uint256 previewedShares = vault.previewDeposit(quotedMax);
        uint256 shares = vault.deposit(quotedMax, address(this));

        assertEq(shares, previewedShares, "received shares differ from previewDeposit");
        assertEq(dusd.balanceOf(address(this)), balanceBefore - quotedMax, "DUSD balance not reduced by quoted maximum");
        assertEq(vault.maxDeposit(address(this)), 0, "supply capacity remains");
    }

    /// @dev Replaces the deployed vault's code with the locally compiled one while preserving its storage.
    /// @return deployedQuote The `maxDeposit` quote of the deployed code at `blockNumber`.
    function _selectForkWithLocalVaultCode(uint256 blockNumber) internal returns (uint256 deployedQuote) {
        Fork.selectEthereum(blockNumber);

        deployedQuote = vault.maxDeposit(address(this));

        AltoVault localVault = new AltoVault(address(this), 0, DUSD, "Alto Vault", "AV", MARKET_REGISTRY);
        vm.etch(VAULT, address(localVault).code);

        assertEq(vault.asset(), DUSD, "unexpected vault asset");
    }
}
