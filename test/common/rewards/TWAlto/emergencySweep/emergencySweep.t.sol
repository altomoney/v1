// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TWAltoBaseTest} from "../TWAltoBaseTest.sol";
import {TWAltoErrorsLib} from "@alto/rewards/libraries/TWAltoErrorsLib.sol";

contract MockERC20 {
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract TWAlto_emergencySweep is TWAltoBaseTest {
    MockERC20 public mockToken;
    uint256 constant TOKEN_AMOUNT = 1000e18;

    function setUp() public override {
        super.setUp();
        mockToken = new MockERC20();
        // Give the contract some tokens to sweep
        mockToken.mint(address(twAlto), TOKEN_AMOUNT);
    }

    // ====================================
    //           MODIFIERS
    // ====================================

    modifier givenCallerIsNotOwner() {
        // Will use alice (not owner) in tests
        _;
    }

    modifier givenCallerIsOwner() {
        // Will use admin (owner) in tests
        _;
    }

    modifier givenLastEmergencySweepIsZero() {
        // Default state - no emergency sweep activated
        _;
    }

    modifier givenCooldownPeriodHasNotPassed() {
        // Activate emergency sweep but don't wait for cooldown
        vm.prank(admin);
        twAlto.activateEmergencySweep();
        _;
    }

    modifier givenCooldownPeriodHasPassed() {
        // Activate emergency sweep and wait for cooldown
        vm.prank(admin);
        twAlto.activateEmergencySweep();
        skip(twAlto.emergencySweepCooldown() + 1);
        _;
    }

    modifier whenSweepingToken() {
        // Will be used in success test
        _;
    }

    // ====================================
    //           TESTS
    // ====================================

    function test_RevertWhen_CallerIsNotOwner() public givenCallerIsNotOwner {
        // It should revert with OwnableUnauthorizedAccount
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        twAlto.emergencySweep(address(mockToken));
    }

    function test_RevertWhen_LastEmergencySweepIsZero() public givenCallerIsOwner givenLastEmergencySweepIsZero {
        // It should revert with EmergencySweepCooldownNotReached
        vm.expectRevert(TWAltoErrorsLib.EmergencySweepCooldownNotReached.selector);
        vm.prank(admin);
        twAlto.emergencySweep(address(mockToken));
    }

    function test_RevertWhen_CooldownPeriodHasNotPassed() public givenCallerIsOwner givenCooldownPeriodHasNotPassed {
        // It should revert with EmergencySweepCooldownNotReached
        vm.expectRevert(TWAltoErrorsLib.EmergencySweepCooldownNotReached.selector);
        vm.prank(admin);
        twAlto.emergencySweep(address(mockToken));
    }

    function test_Success_WhenCooldownPeriodHasPassed()
        public
        givenCallerIsOwner
        givenCooldownPeriodHasPassed
        whenSweepingToken
    {
        uint256 ownerBalanceBefore = mockToken.balanceOf(admin);
        uint256 contractBalanceBefore = mockToken.balanceOf(address(twAlto));

        vm.prank(admin);
        twAlto.emergencySweep(address(mockToken));

        // It should transfer all token balance to owner
        assertEq(mockToken.balanceOf(admin), ownerBalanceBefore + contractBalanceBefore);
        assertEq(mockToken.balanceOf(address(twAlto)), 0);
    }

    function test_EmergencySweep_WithAltoToken() public givenCallerIsOwner givenCooldownPeriodHasPassed {
        // Setup: Give contract some alto tokens
        alto.mint(address(twAlto), TOKEN_AMOUNT);

        uint256 ownerBalanceBefore = IERC20(address(alto)).balanceOf(admin);
        uint256 contractBalanceBefore = IERC20(address(alto)).balanceOf(address(twAlto));

        vm.prank(admin);
        twAlto.emergencySweep(address(alto));

        // Should transfer all alto tokens to owner
        assertEq(IERC20(address(alto)).balanceOf(admin), ownerBalanceBefore + contractBalanceBefore);
        assertEq(IERC20(address(alto)).balanceOf(address(twAlto)), 0);
    }

    function test_EmergencySweep_WithZeroBalance() public givenCallerIsOwner givenCooldownPeriodHasPassed {
        // Setup: Empty the contract's token balance
        mockToken = new MockERC20(); // New token with zero balance in contract

        uint256 ownerBalanceBefore = mockToken.balanceOf(admin);

        vm.prank(admin);
        twAlto.emergencySweep(address(mockToken));

        // Should not change balances (transfer 0)
        assertEq(mockToken.balanceOf(admin), ownerBalanceBefore);
        assertEq(mockToken.balanceOf(address(twAlto)), 0);
    }

    function test_EmergencySweep_ExactCooldownTime() public givenCallerIsOwner {
        // Activate emergency sweep
        vm.prank(admin);
        twAlto.activateEmergencySweep();

        // Skip exactly the cooldown period (not +1)
        skip(twAlto.emergencySweepCooldown());

        // Should succeed at exactly cooldown time
        vm.prank(admin);
        twAlto.emergencySweep(address(mockToken));

        assertEq(mockToken.balanceOf(address(twAlto)), 0);
    }

    function test_EmergencySweep_OneLessThanCooldown() public givenCallerIsOwner {
        // Activate emergency sweep
        vm.prank(admin);
        twAlto.activateEmergencySweep();

        // Skip one second less than cooldown
        skip(twAlto.emergencySweepCooldown() - 1);

        // Should revert
        vm.expectRevert(TWAltoErrorsLib.EmergencySweepCooldownNotReached.selector);
        vm.prank(admin);
        twAlto.emergencySweep(address(mockToken));
    }

    // ====================================
    //         FUZZ TESTS
    // ====================================

    function testFuzz_RevertWhen_CallerIsNotOwner(address _caller) public givenCallerIsNotOwner {
        vm.assume(_caller != admin);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, _caller));
        vm.prank(_caller);
        twAlto.emergencySweep(address(mockToken));
    }

    function testFuzz_EmergencySweep_AfterCooldown(uint256 _additionalTime)
        public
        givenCallerIsOwner
        givenCooldownPeriodHasPassed
    {
        // Bound additional time to reasonable range
        _additionalTime = bound(_additionalTime, 0, 365 days);

        // Skip additional time beyond cooldown
        skip(_additionalTime);

        uint256 contractBalanceBefore = mockToken.balanceOf(address(twAlto));

        vm.prank(admin);
        twAlto.emergencySweep(address(mockToken));

        // Should still work regardless of how much time passed
        assertEq(mockToken.balanceOf(address(twAlto)), 0);
        assertEq(mockToken.balanceOf(admin), contractBalanceBefore);
    }
}
