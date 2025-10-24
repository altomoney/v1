// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {DUSDCommon} from "./DUSDCommon.t.sol";
import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import {ERC3156FlashBorrowerMock} from "@openzeppelin/contracts/mocks/ERC3156FlashBorrowerMock.sol";
import {ERC20FlashMint} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20FlashMint.sol";
import {IPausable} from "@alto/utils/Pausable.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract FlashLoanTest is DUSDCommon {
    address constant INVALID_TOKEN = address(0x999);
    uint256 constant FLASH_LOAN_AMOUNT = 1000e18;
    uint256 constant MAX_FLASH_LOAN_AMOUNT = type(uint256).max - 1;

    ERC3156FlashBorrowerMock invalidReturnBorrower;
    ERC3156FlashBorrowerMock noApproveBorrower;
    MockInvalidBorrower invalidBorrower;

    function setUp() public override {
        super.setUp();

        vm.prank(OWNER);
        dusd.setMinterStatus(address(this), true);

        // Create different types of borrowers for testing
        invalidReturnBorrower = new ERC3156FlashBorrowerMock(false, true); // returns invalid hash
        noApproveBorrower = new ERC3156FlashBorrowerMock(true, false); // doesn't approve repayment
        invalidBorrower = new MockInvalidBorrower(); // not a valid borrower
    }

    // =====================
    // Given contract is paused
    // =====================

    function test_RevertWhen_ContractIsPaused() public {
        _pauseContract();

        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSE_TYPE));
        dusd.flashLoan(flashBorrower, address(dusd), FLASH_LOAN_AMOUNT, "");
    }

    // =====================
    // Given contract is not paused
    // =====================

    function test_RevertWhen_TokenIsNotThisContract() public {
        vm.expectRevert(abi.encodeWithSelector(ERC20FlashMint.ERC3156ExceededMaxLoan.selector, 0));
        dusd.flashLoan(flashBorrower, INVALID_TOKEN, FLASH_LOAN_AMOUNT, "");
    }

    function test_RevertWhen_ValueExceedsMaxFlashLoan() public {
        vm.startPrank(OWNER);
        dusd.setMinterStatus(MINTER, true);
        // dusd.setMinterCeiling(MINTER, 1000e18);
        vm.stopPrank();

        vm.prank(MINTER);
        dusd.mint(address(this), 1000e18);

        uint256 maxLoan = dusd.maxFlashLoan(address(dusd));
        uint256 exceedingAmount = maxLoan + 1;

        vm.expectRevert(abi.encodeWithSelector(ERC20FlashMint.ERC3156ExceededMaxLoan.selector, maxLoan));
        dusd.flashLoan(flashBorrower, address(dusd), exceedingAmount, "");
    }

    function test_RevertWhen_ReceiverIsNotValidFlashBorrower() public {
        vm.expectRevert(
            abi.encodeWithSelector(ERC20FlashMint.ERC3156InvalidReceiver.selector, address(invalidBorrower))
        );
        dusd.flashLoan(IERC3156FlashBorrower(address(invalidBorrower)), address(dusd), FLASH_LOAN_AMOUNT, "");
    }

    function test_RevertWhen_ReceiverReturnsInvalidHash() public {
        vm.expectRevert(
            abi.encodeWithSelector(ERC20FlashMint.ERC3156InvalidReceiver.selector, address(invalidReturnBorrower))
        );
        dusd.flashLoan(invalidReturnBorrower, address(dusd), FLASH_LOAN_AMOUNT, "");
    }

    function test_RevertWhen_ReceiverDoesNotApproveRepayment() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(dusd), 0, FLASH_LOAN_AMOUNT
            )
        );
        dusd.flashLoan(noApproveBorrower, address(dusd), FLASH_LOAN_AMOUNT, "");
    }

    function test_RevertWhen_ReceiverHasInsufficientBalanceForRepayment() public {
        // Create a borrower that approves but doesn't have enough balance
        MockInsufficientBalanceBorrower insufficientBorrower = new MockInsufficientBalanceBorrower();

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(insufficientBorrower), 0, FLASH_LOAN_AMOUNT
            )
        );
        dusd.flashLoan(insufficientBorrower, address(dusd), FLASH_LOAN_AMOUNT, "");
    }

    // =====================
    // When flash fee is zero or flashFeeReceiver is zero
    // =====================

    function test_FlashLoan_WhenFeeIsZeroAndReceiverIsZero() public {
        // Default state: flashFee = 0, flashFeeReceiver = address(0)

        uint256 initialSupply = dusd.totalSupply();
        uint256 initialBorrowerBalance = dusd.balanceOf(address(flashBorrower));
        uint256 initialReceiverBalance = dusd.balanceOf(address(FLASH_FEE_RECEIVER));
        vm.expectCall(address(flashBorrower), abi.encodeWithSelector(IERC3156FlashBorrower.onFlashLoan.selector));
        bool result = dusd.flashLoan(flashBorrower, address(dusd), FLASH_LOAN_AMOUNT, "");

        assertTrue(result);
        assertEq(dusd.totalSupply(), initialSupply);
        assertEq(dusd.balanceOf(address(flashBorrower)), initialBorrowerBalance);
        assertEq(dusd.balanceOf(address(FLASH_FEE_RECEIVER)), initialReceiverBalance);
    }

    function test_FlashLoan_WhenFeeIsNonZeroButReceiverIsZero() public {
        uint256 flashFee = 100;
        vm.startPrank(OWNER);
        dusd.setFlashFee(flashFee); // Set non-zero fee but keep receiver as zero
        // dusd.setMinterCeiling(address(this), flashFee);
        vm.stopPrank();

        dusd.mint(address(flashBorrower), flashFee);

        uint256 initialSupply = dusd.totalSupply();
        vm.expectCall(address(flashBorrower), abi.encodeWithSelector(IERC3156FlashBorrower.onFlashLoan.selector));
        bool result = dusd.flashLoan(flashBorrower, address(dusd), FLASH_LOAN_AMOUNT, "");

        assertTrue(result);
        assertEq(dusd.totalSupply(), initialSupply - flashFee); // Fee should be burned
    }

    // =====================
    // When flash fee is non-zero and flashFeeReceiver is set
    // =====================

    function test_FlashLoan_WhenFeeIsNonZeroAndReceiverIsSet() public {
        uint256 fee = 100;

        vm.startPrank(OWNER);
        dusd.setFlashFee(fee);
        dusd.setFlashFeeReceiver(FLASH_FEE_RECEIVER);
        // dusd.setMinterStatus(address(this), true);
        vm.stopPrank();

        dusd.mint(address(flashBorrower), fee);

        uint256 initialSupply = dusd.totalSupply();
        uint256 initialReceiverBalance = dusd.balanceOf(FLASH_FEE_RECEIVER);
        uint256 initialBorrowerBalance = dusd.balanceOf(address(flashBorrower));
        vm.expectCall(address(flashBorrower), abi.encodeWithSelector(IERC3156FlashBorrower.onFlashLoan.selector));
        bool result = dusd.flashLoan(flashBorrower, address(dusd), FLASH_LOAN_AMOUNT, "");

        assertTrue(result);
        assertEq(dusd.totalSupply(), initialSupply);
        assertEq(dusd.balanceOf(FLASH_FEE_RECEIVER), initialReceiverBalance + fee);
        assertEq(dusd.balanceOf(address(flashBorrower)), initialBorrowerBalance - fee);
    }

    // =====================
    // Edge cases
    // =====================

    function test_FlashLoan_WhenValueIsZero() public {
        uint256 initialSupply = dusd.totalSupply();
        vm.expectCall(address(flashBorrower), abi.encodeWithSelector(IERC3156FlashBorrower.onFlashLoan.selector));
        bool result = dusd.flashLoan(flashBorrower, address(dusd), 0, "");

        assertTrue(result);
        assertEq(dusd.totalSupply(), initialSupply);
    }

    function test_FlashLoan_WhenValueIsMaximumPossible() public {
        uint256 maxLoan = dusd.maxFlashLoan(address(dusd));
        uint256 initialSupply = dusd.totalSupply();
        vm.expectCall(address(flashBorrower), abi.encodeWithSelector(IERC3156FlashBorrower.onFlashLoan.selector));
        bool result = dusd.flashLoan(flashBorrower, address(dusd), maxLoan, "");

        assertTrue(result);
        assertEq(dusd.totalSupply(), initialSupply);
    }
}

// =====================
// Mock contracts for testing
// =====================

contract MockInvalidBorrower {
    // This contract doesn't implement IERC3156FlashBorrower
    function onFlashLoan(address, address, uint256, uint256, bytes calldata) external pure returns (bytes32) {
        return bytes32(0);
    }
}

contract MockInsufficientBalanceBorrower is IERC3156FlashBorrower {
    bytes32 private constant _RETURN_VALUE = keccak256("ERC3156FlashBorrower.onFlashLoan");

    function onFlashLoan(address, address token, uint256 amount, uint256 fee, bytes calldata)
        external
        returns (bytes32)
    {
        // Approve the repayment
        IERC20(token).approve(token, amount + fee);

        // Transfer away all tokens to simulate insufficient balance
        IERC20(token).transfer(address(0x1234), IERC20(token).balanceOf(address(this)));

        return _RETURN_VALUE;
    }
}
