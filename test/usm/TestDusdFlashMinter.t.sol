// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./TestDusdBase.t.sol";
import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import {IERC3156FlashLender} from "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {DUSDFlashMinter} from "@alto/usm/DUSDFlashMinter.sol";
import {IDUSDFlashMinter, FlashFee} from "@alto/usm/interfaces/IDUSDFlashMinter.sol";
import {IStableTokenFacilitator} from "@alto/usm/interfaces/IStableTokenFacilitator.sol";
import {FixedPointMath, MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";

import {MockFlashBorrower} from "./mocks/MockFlashBorrower.sol";

contract TestDusdFlashMinter is TestDusdBase {
    using FixedPointMath for uint256;

    DUSDFlashMinter public flashMinter;
    MockFlashBorrower public flashBorrower;
    MockFlashBorrower public flashBorrowerNoApprove;

    address constant OWNER = address(0x12345);

    uint256 constant DEFAULT_BORROW_AMOUNT = 1000e18;
    uint128 constant DEFAULT_MIN_FLASH_FEE = 1e16; // 1%
    uint128 constant DEFAULT_MAX_FLASH_FEE = 2e16; // 2%

    function setUp() public override {
        super.setUp();

        FlashFee memory defaultFlashFee = _createFlashFee(DEFAULT_MIN_FLASH_FEE, DEFAULT_MAX_FLASH_FEE);
        flashMinter = new DUSDFlashMinter(address(DUSD_TOKEN), TREASURY, defaultFlashFee, OWNER);

        _setupDusdForFlashMinter();
        _setupFlashBorrowers();
    }

    function _createFlashFee(uint128 minFee, uint128 maxFee) internal pure returns (FlashFee memory) {
        return FlashFee({minFlashFee: minFee, maxFlashFee: maxFee});
    }

    function _setupDusdForFlashMinter() internal {
        vm.startPrank(address(this));
        DUSD_TOKEN.setMinterStatus(address(flashMinter), true);
        DUSD_TOKEN.setMinterCeiling(address(flashMinter), DEFAULT_CAPACITY);
        DUSD_TOKEN.setBurnerStatus(address(flashMinter), true);
        vm.stopPrank();
    }

    function _setupFlashBorrowers() internal {
        flashBorrower = new MockFlashBorrower(IERC3156FlashLender(address(flashMinter)));
        flashBorrowerNoApprove = new MockFlashBorrower(IERC3156FlashLender(address(flashMinter)));
        flashBorrowerNoApprove.setAllowRepayment(false);
    }

    function _calculateExpectedFlashFee(uint256 amount, uint128 minFee, uint128 maxFee)
        internal
        view
        returns (uint256)
    {
        (, uint256 flashMintCap) = DUSD_TOKEN.minterConfig(address(flashMinter));
        uint256 flashFeeToCharge;

        if (minFee == maxFee) {
            flashFeeToCharge = minFee;
        } else {
            bool increasing = maxFee > minFee;
            uint256 diff = increasing ? (maxFee - minFee) : (minFee - maxFee);
            uint256 step = FixedPointMath.divideWithRounding(amount, diff, flashMintCap, increasing);
            flashFeeToCharge = increasing ? (minFee + step) : (minFee - step);
        }

        return amount.multiplyWithPrecisionUp(flashFeeToCharge);
    }

    // Constructor Tests

    function testConstructor() public {
        FlashFee memory defaultFlashFee = _createFlashFee(DEFAULT_MIN_FLASH_FEE, DEFAULT_MAX_FLASH_FEE);

        vm.expectEmit(true, true, false, false);
        emit IStableTokenFacilitator.StableTokenFeeRecipientUpdated(address(0), TREASURY);
        vm.expectEmit(false, false, false, true);
        emit IDUSDFlashMinter.SetFlashMintFee(_createFlashFee(0, 0), defaultFlashFee);

        DUSDFlashMinter newFlashMinter = new DUSDFlashMinter(address(DUSD_TOKEN), TREASURY, defaultFlashFee, OWNER);

        assertEq(address(newFlashMinter.DUSD()), address(DUSD_TOKEN), "Wrong DUSD token address");
        FlashFee memory fee = newFlashMinter.getFlashMintFee();
        assertEq(fee.minFlashFee, DEFAULT_MIN_FLASH_FEE, "Wrong min flash fee");
        assertEq(fee.maxFlashFee, DEFAULT_MAX_FLASH_FEE, "Wrong max flash fee");
        assertEq(newFlashMinter.getFeeRecipient(), TREASURY, "Wrong fee recipient address");
    }

    function testRevertConstructorFeeOutOfRange_MinFlashFee() public {
        FlashFee memory invalidFlashFee = _createFlashFee(uint128(MATH_PRECISION + 1), DEFAULT_MAX_FLASH_FEE);

        vm.expectRevert("FlashMinter: Min flash fee exceeds MATH_PRECISION");
        new DUSDFlashMinter(address(DUSD_TOKEN), TREASURY, invalidFlashFee, OWNER);
    }

    function testRevertConstructorFeeOutOfRange_MaxFlashFee() public {
        FlashFee memory invalidFlashFee = _createFlashFee(DEFAULT_MIN_FLASH_FEE, uint128(MATH_PRECISION + 1));

        vm.expectRevert("FlashMinter: Max flash fee exceeds MATH_PRECISION");
        new DUSDFlashMinter(address(DUSD_TOKEN), TREASURY, invalidFlashFee, OWNER);
    }

    // Flash Loan Revert Tests

    function testRevertFlashloanNonRecipient() public {
        vm.expectRevert();
        flashMinter.flashLoan(IERC3156FlashBorrower(address(this)), address(DUSD_TOKEN), DEFAULT_BORROW_AMOUNT, "");
    }

    function testRevertFlashloanWrongToken() public {
        vm.expectRevert("FlashMinter: Unsupported currency");
        flashMinter.flashLoan(IERC3156FlashBorrower(address(flashBorrower)), address(0), DEFAULT_BORROW_AMOUNT, "");
    }

    function testRevertFlashloanMoreThanCapacity() public {
        vm.expectRevert("FlashMinter: Amount exceeds flash mint cap");
        flashMinter.flashLoan(
            IERC3156FlashBorrower(address(flashBorrower)), address(DUSD_TOKEN), DEFAULT_CAPACITY + 1, ""
        );
    }

    function testRevertFlashloanInsufficientReturned() public {
        uint256 fee = flashMinter.flashFee(address(DUSD_TOKEN), DEFAULT_BORROW_AMOUNT);
        uint256 needed = DEFAULT_BORROW_AMOUNT + fee;

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(flashMinter), 0, needed)
        );
        flashBorrowerNoApprove.flashBorrow(address(DUSD_TOKEN), DEFAULT_BORROW_AMOUNT);
    }

    function testRevertFlashloanWrongCallback() public {
        MockFlashBorrower wrongCallbackBorrower = new MockFlashBorrower(IERC3156FlashLender(address(flashMinter)));
        wrongCallbackBorrower.setAllowCallback(false);

        vm.expectRevert("FlashMinter: Callback failed");
        wrongCallbackBorrower.flashBorrow(address(DUSD_TOKEN), DEFAULT_BORROW_AMOUNT);
    }

    // Update Function Revert Tests

    function testRevertUpdateFeeNotOwner() public {
        address notOwner = address(0x1234);
        FlashFee memory newFlashFee = _createFlashFee(150, 250);

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        flashMinter.updateFlashMintFee(newFlashFee);
    }

    function testRevertUpdateFeeOutOfRange_MinFlashFee() public {
        FlashFee memory invalidFlashFee = _createFlashFee(uint128(MATH_PRECISION + 1), DEFAULT_MAX_FLASH_FEE);

        vm.expectRevert("FlashMinter: Min flash fee exceeds MATH_PRECISION");
        vm.prank(OWNER);
        flashMinter.updateFlashMintFee(invalidFlashFee);
    }

    function testRevertUpdateFeeOutOfRange_MaxFlashFee() public {
        FlashFee memory invalidFlashFee = _createFlashFee(DEFAULT_MIN_FLASH_FEE, uint128(MATH_PRECISION + 1));

        vm.expectRevert("FlashMinter: Max flash fee exceeds MATH_PRECISION");
        vm.prank(OWNER);
        flashMinter.updateFlashMintFee(invalidFlashFee);
    }

    function testRevertUpdateFeeWhenTreasuryNotSet_MinFlashFee() public {
        // First set fees to 0
        FlashFee memory zeroFee = _createFlashFee(0, 0);
        vm.prank(OWNER);
        flashMinter.updateFlashMintFee(zeroFee);

        // Then set fee recipient to address(0)
        vm.prank(OWNER);
        flashMinter.updateFeeRecipient(address(0));

        // Try to update fee with minFlashFee > 0
        FlashFee memory feeWithMin = _createFlashFee(1e16, 0);

        vm.expectRevert("FlashMinter: DUSD fee recipient must be set as fees are enabled");
        vm.prank(OWNER);
        flashMinter.updateFlashMintFee(feeWithMin);
    }

    function testRevertUpdateFeeWhenTreasuryNotSet_MaxFlashFee() public {
        // First set fees to 0
        FlashFee memory zeroFee = _createFlashFee(0, 0);
        vm.prank(OWNER);
        flashMinter.updateFlashMintFee(zeroFee);

        // Then set fee recipient to address(0)
        vm.prank(OWNER);
        flashMinter.updateFeeRecipient(address(0));

        // Try to update fee with maxFlashFee > 0
        FlashFee memory feeWithMax = _createFlashFee(0, 1e16);

        vm.expectRevert("FlashMinter: DUSD fee recipient must be set as fees are enabled");
        vm.prank(OWNER);
        flashMinter.updateFlashMintFee(feeWithMax);
    }

    function testRevertUpdateFeeRecipientToZeroWithFeesEnabled() public {
        // Flash minter is initialized with fees (DEFAULT_MIN_FLASH_FEE and DEFAULT_MAX_FLASH_FEE)
        // Try to set fee recipient to address(0) while fees are enabled - should revert
        vm.expectRevert("FlashMinter: Fees are enabled but fee recipient is not set");
        vm.prank(OWNER);
        flashMinter.updateFeeRecipient(address(0));
    }

    function testSetFeeRecipientToZeroWithZeroFees() public {
        // First set fees to 0
        FlashFee memory zeroFee = _createFlashFee(0, 0);
        vm.prank(OWNER);
        flashMinter.updateFlashMintFee(zeroFee);

        // Now setting fee recipient to 0 should succeed
        vm.expectEmit(true, true, false, false, address(flashMinter));
        emit IStableTokenFacilitator.StableTokenFeeRecipientUpdated(TREASURY, address(0));
        vm.prank(OWNER);
        flashMinter.updateFeeRecipient(address(0));

        assertEq(flashMinter.getFeeRecipient(), address(0), "Fee recipient should be zero");
    }

    function testRevertUpdateTreasuryNotOwner() public {
        address notOwner = address(0x1234);

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        flashMinter.updateFeeRecipient(address(0));
    }

    function testRevertFlashfeeNotDusd() public {
        vm.expectRevert("FlashMinter: Unsupported currency");
        flashMinter.flashFee(address(0), DEFAULT_BORROW_AMOUNT);
    }

    // Positive Tests

    function testFlashloan() public {
        uint256 feeAmount =
            _calculateExpectedFlashFee(DEFAULT_BORROW_AMOUNT, DEFAULT_MIN_FLASH_FEE, DEFAULT_MAX_FLASH_FEE);
        dusdFaucet(address(flashBorrower), feeAmount);

        vm.expectEmit(true, true, true, true, address(flashMinter));
        emit IDUSDFlashMinter.FlashMint(
            address(flashBorrower), address(flashBorrower), address(DUSD_TOKEN), DEFAULT_BORROW_AMOUNT, feeAmount
        );
        flashBorrower.flashBorrow(address(DUSD_TOKEN), DEFAULT_BORROW_AMOUNT);
    }

    function testDistributeFeesToTreasury() public {
        uint256 treasuryBalanceBefore = DUSD_TOKEN.balanceOf(TREASURY);
        uint256 feeAmount = 100e18;

        dusdFaucet(address(flashMinter), feeAmount);
        assertEq(DUSD_TOKEN.balanceOf(address(flashMinter)), feeAmount, "FlashMinter should have fees");

        vm.expectEmit(true, true, false, true, address(flashMinter));
        emit IStableTokenFacilitator.FeesDistributedToFeeRecipient(TREASURY, address(DUSD_TOKEN), feeAmount);
        flashMinter.distributeFeesToFeeRecipient();

        assertEq(DUSD_TOKEN.balanceOf(address(flashMinter)), 0, "FlashMinter should have no DUSD left");
        assertEq(DUSD_TOKEN.balanceOf(TREASURY), treasuryBalanceBefore + feeAmount, "Treasury should receive fees");
    }

    function testUpdateFee() public {
        FlashFee memory currentFee = flashMinter.getFlashMintFee();
        assertEq(currentFee.minFlashFee, DEFAULT_MIN_FLASH_FEE, "Flashminter non-default min fee");
        assertEq(currentFee.maxFlashFee, DEFAULT_MAX_FLASH_FEE, "Flashminter non-default max fee");

        FlashFee memory newFlashFee = _createFlashFee(1.5e16, 2.5e16);
        assertTrue(newFlashFee.minFlashFee != currentFee.minFlashFee);

        vm.expectEmit(false, false, false, true, address(flashMinter));
        emit IDUSDFlashMinter.SetFlashMintFee(currentFee, newFlashFee);
        vm.prank(OWNER);
        flashMinter.updateFlashMintFee(newFlashFee);

        FlashFee memory updatedFee = flashMinter.getFlashMintFee();
        assertEq(updatedFee.minFlashFee, 1.5e16, "Min fee should be updated");
        assertEq(updatedFee.maxFlashFee, 2.5e16, "Max fee should be updated");
    }

    function testUpdateFeeRecipient() public {
        assertEq(flashMinter.getFeeRecipient(), TREASURY, "Flashminter non-default fee recipient");
        address newFeeRecipient = address(0x9999);
        assertTrue(TREASURY != newFeeRecipient);

        vm.expectEmit(true, true, false, false, address(flashMinter));
        emit IStableTokenFacilitator.StableTokenFeeRecipientUpdated(TREASURY, newFeeRecipient);
        vm.prank(OWNER);
        flashMinter.updateFeeRecipient(newFeeRecipient);

        assertEq(flashMinter.getFeeRecipient(), newFeeRecipient, "Fee recipient should be updated");
    }

    function testMaxFlashloanNotDusd() public view {
        assertEq(flashMinter.maxFlashLoan(address(0)), 0, "Max flash loan should be 0 for non-DUSD token");
    }

    function testMaxFlashloanDusd() public view {
        assertEq(
            flashMinter.maxFlashLoan(address(DUSD_TOKEN)),
            DEFAULT_CAPACITY,
            "Max flash loan should be DEFAULT_CAPACITY for DUSD token"
        );
    }

    function testFlashFee() public view {
        uint256 fee = flashMinter.flashFee(address(DUSD_TOKEN), DEFAULT_BORROW_AMOUNT);
        uint256 expectedFeeMin = (DEFAULT_BORROW_AMOUNT * DEFAULT_MIN_FLASH_FEE) / MATH_PRECISION;
        uint256 expectedFeeMax = (DEFAULT_BORROW_AMOUNT * DEFAULT_MAX_FLASH_FEE) / MATH_PRECISION;

        assertTrue(fee >= expectedFeeMin, "Flash fee should be at least min fee");
        assertTrue(fee <= expectedFeeMax, "Flash fee should be at most max fee");
    }

    // Fuzzing

    function testFuzzFlashFee(uint128 minFee, uint128 maxFee, uint256 amount) public {
        minFee = uint128(bound(minFee, 0, MATH_PRECISION));
        maxFee = uint128(bound(maxFee, 0, MATH_PRECISION));
        amount = bound(amount, 0, DEFAULT_CAPACITY / 10);

        FlashFee memory flashFee = _createFlashFee(minFee, maxFee);
        vm.prank(OWNER);
        flashMinter.updateFlashMintFee(flashFee);

        uint256 fee = flashMinter.flashFee(address(DUSD_TOKEN), amount);

        if (amount == 0) {
            assertEq(fee, 0, "Flash fee should be 0 for 0 amount");
        } else if (minFee == 0 && maxFee == 0) {
            assertEq(fee, 0, "Flash fee should be 0 when both fees are zero");
        } else if (minFee == maxFee) {
            // Flat fee: fee should equal amount * minFee / MATH_PRECISION
            uint256 expectedFee = amount.multiplyWithPrecisionUp(minFee);
            assertEq(fee, expectedFee, "Flash fee should match flat fee calculation");
            assertGt(fee, 0, "Flash fee should be greater than 0");
            // [3, 3, 1] is a counter example when assertLt would fail
            assertLe(fee, amount, "Flash fee should be less than or equal to amount (in case of tiny amounts)");
        } else {
            // Interpolated fee: fee should be between min and max fee amounts
            uint256 minFeeAmount = amount.multiplyWithPrecisionUp(minFee);
            uint256 maxFeeAmount = amount.multiplyWithPrecisionUp(maxFee);
            uint256 expectedFee = _calculateExpectedFlashFee(amount, minFee, maxFee);

            // Fee should be between min and max (accounting for which is larger)
            // Use >= and <= to account for edge cases where fee equals min/max due to rounding
            if (maxFee > minFee) {
                assertGe(fee, minFeeAmount, "Flash fee should be at least min fee amount");
                assertLe(fee, maxFeeAmount, "Flash fee should be at most max fee amount");
            } else {
                assertGe(fee, maxFeeAmount, "Flash fee should be at least max fee amount (when min > max)");
                assertLe(fee, minFeeAmount, "Flash fee should be at most min fee amount (when min > max)");
            }

            // Fee should approximately match expected (within 1 wei tolerance for rounding)
            assertApproxEqAbs(fee, expectedFee, 1, "Flash fee should match expected interpolated fee");
            assertGt(fee, 0, "Flash fee should be greater than 0");
        }
    }

    function test_WhenMinEqualsMaxFlashFee_FeePercentageIsConstant() public {
        // Set min and max flash fees to the same value
        uint128 flatFee = 1.5e16; // 1.5%
        FlashFee memory equalFlashFee = _createFlashFee(flatFee, flatFee);
        vm.prank(OWNER);
        flashMinter.updateFlashMintFee(equalFlashFee);

        // Test with different amounts
        uint256[] memory amounts = new uint256[](5);
        amounts[0] = 100e18;
        amounts[1] = 1000e18;
        amounts[2] = 5000e18;
        amounts[3] = 10000e18;
        amounts[4] = DEFAULT_CAPACITY / 2;

        // Verify fee equals flatFee calculation for each amount
        for (uint256 i = 0; i < amounts.length; i++) {
            uint256 fee = flashMinter.flashFee(address(DUSD_TOKEN), amounts[i]);
            uint256 expectedFee = amounts[i].multiplyWithPrecisionUp(flatFee);
            assertEq(fee, expectedFee, "Fee should equal flatFee calculation");
        }
    }
}
