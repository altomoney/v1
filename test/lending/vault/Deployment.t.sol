// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./helpers/IntegrationTest.sol";

contract DeploymentTest is IntegrationTest {
    function testSetName(string memory name) public {
        vm.prank(OWNER);
        AltoVault(address(vault)).setName(name);

        assertEq(AltoVault(address(vault)).name(), name);
    }

    function testSetNameEvent(string memory name) public {
        vm.expectEmit();
        emit IAltoVaultEvents.SetName(name);
        vm.prank(OWNER);
        AltoVault(address(vault)).setName(name);
    }

    function testSetNameNotOwner(string memory name) public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        AltoVault(address(vault)).setName(name);
    }

    function testSetSymbol(string memory symbol) public {
        vm.prank(OWNER);
        AltoVault(address(vault)).setSymbol(symbol);

        assertEq(AltoVault(address(vault)).symbol(), symbol);
    }

    function testSetSymbolEvent(string memory symbol) public {
        vm.expectEmit();
        emit IAltoVaultEvents.SetSymbol(symbol);
        vm.prank(OWNER);
        vault.setSymbol(symbol);
    }

    function testSetSymbolNotOwner(string memory name) public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        AltoVault(address(vault)).setSymbol(name);
    }

    function testDeployAltoVaultNotToken(address notToken) public {
        vm.assume(address(notToken) != address(loanToken));
        vm.assume(address(notToken) != address(collateralToken));
        vm.assume(address(notToken) != address(vault));

        vm.expectRevert();
        new AltoVault(OWNER, 1 days, notToken, "Alto Vault", "AV", address(marketRegistry));
    }

    function testDeployAltoVault(address owner, uint256 initialTimelock, string memory name, string memory symbol)
        public
    {
        assumeNotZeroAddress(owner);
        initialTimelock = _boundInitialTimelock(initialTimelock);

        AltoVault newVault =
            new AltoVault(owner, initialTimelock, address(loanToken), name, symbol, address(marketRegistry));

        assertEq(newVault.owner(), owner, "owner");
        assertEq(newVault.timelock(), initialTimelock, "timelock");
        assertEq(newVault.asset(), address(loanToken), "asset");
        assertEq(newVault.name(), name, "name");
        assertEq(newVault.symbol(), symbol, "symbol");
    }
}
