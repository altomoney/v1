// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AltoConvexCreditLineMarket} from "@alto/lending/credit-market/AltoConvexCreditLineMarket.sol";
import {IAltoConvexCreditLineMarketErrors} from "@alto/lending/interfaces/IAltoConvexCreditLineMarket.sol";

import {ConvexCreditLineCommon} from "./ConvexCreditLineCommon.t.sol";

contract AltoConvexCreditLineMarketInitializeV2Test is ConvexCreditLineCommon {
    function setUp() public override {
        super.setUp();
        irm = _newFixedRateIrm();
        market = _newUninitializedMarket();
        market.initialize(_validInitParams());
        vm.startPrank(OWNER);
        borrowToken.setMinterStatus(address(market), true);
        borrowToken.setMinterCeiling(address(market), type(uint256).max);
        borrowToken.setBurnerStatus(address(market), true);
        vm.stopPrank();
    }

    function test_OriginalInitializerDefaultsToZeroTreasuryShare() external view {
        assertEq(market.treasuryInterestBps(), 0);
        assertEq(market.PERCENTAGE_PRECISION(), 10_000);
    }

    function test_RevertWhenImplementationIsInitializedDirectly() external {
        AltoConvexCreditLineMarket implementation = new AltoConvexCreditLineMarket();
        vm.prank(OWNER);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initializeV2(TREASURY_INTEREST_BPS);
    }

    function test_NonOwnerCannotInitializeOrConsumeReinitializer() external {
        vm.prank(CREDIT_ACCOUNT);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, CREDIT_ACCOUNT));
        market.initializeV2(TREASURY_INTEREST_BPS);
        assertEq(market.treasuryInterestBps(), 0);

        vm.prank(OWNER);
        market.initializeV2(TREASURY_INTEREST_BPS);
        assertEq(market.treasuryInterestBps(), TREASURY_INTEREST_BPS);
    }

    function test_InvalidShareCanBeRetriedWithoutConsumingReinitializer() external {
        uint256[2] memory invalidShares = [market.PERCENTAGE_PRECISION() + 1, type(uint256).max];
        for (uint256 i; i < invalidShares.length; ++i) {
            vm.prank(OWNER);
            vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketInvalidInput.selector);
            market.initializeV2(invalidShares[i]);
            assertEq(market.treasuryInterestBps(), 0);
        }

        vm.prank(OWNER);
        market.initializeV2(TREASURY_INTEREST_BPS);
        assertEq(market.treasuryInterestBps(), TREASURY_INTEREST_BPS);
    }

    function test_InitializesValidShareAndEmits() external {
        uint256 bps = TREASURY_INTEREST_BPS;
        vm.expectEmit(address(market));
        emit SetTreasuryInterestBps(0, bps);
        vm.expectEmit(address(market));
        emit Initializable.Initialized(2);
        vm.prank(OWNER);
        market.initializeV2(bps);
        assertEq(market.treasuryInterestBps(), bps);
    }

    function test_ZeroTreasuryShareInitializesOnce() external {
        _assertBoundaryShareInitializesOnce(0);
    }

    function test_FullTreasuryShareInitializesOnce() external {
        _assertBoundaryShareInitializesOnce(10_000);
    }

    function _assertBoundaryShareInitializesOnce(uint256 bps) private {
        vm.expectEmit(address(market));
        emit SetTreasuryInterestBps(0, bps);
        vm.expectEmit(address(market));
        emit Initializable.Initialized(2);
        vm.prank(OWNER);
        market.initializeV2(bps);
        assertEq(market.treasuryInterestBps(), bps);

        vm.prank(OWNER);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        market.initializeV2(TREASURY_INTEREST_BPS);
        assertEq(market.treasuryInterestBps(), bps);
    }

    function test_InitializesSplitForExistingFeesWithoutAccruingOrClaiming() external {
        _setOpeningFee(0.1 ether);
        _openPosition(1_000 ether, 100 ether);
        AccountingState memory beforeState = _state();
        uint256 supplyBefore = borrowToken.totalSupply();
        _mockIrmUpdateRevert();
        vm.mockCallRevert(address(borrowToken), borrowToken.mint.selector, "MUST_NOT_MINT");

        vm.prank(OWNER);
        market.initializeV2(TREASURY_INTEREST_BPS);

        _assertUnchanged(beforeState);
        assertEq(borrowToken.totalSupply(), supplyBefore);
        assertEq(borrowToken.balanceOf(FEE_RECIPIENT), 0);
        assertEq(borrowToken.balanceOf(REWARD_RECIPIENT), 0);
        vm.clearMockedCalls();

        assertEq(market.claimInterest(0), 10 ether);
        assertEq(borrowToken.balanceOf(FEE_RECIPIENT), 7 ether);
        assertEq(borrowToken.balanceOf(REWARD_RECIPIENT), 3 ether);
    }
}
