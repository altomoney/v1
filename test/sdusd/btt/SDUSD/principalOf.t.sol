// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SDUSDCommon} from "./SDUSDCommon.t.sol";

contract PrincipalSharePool {
    using SafeERC20 for IERC20;

    IERC20 internal immutable shares;
    mapping(address => uint256) public balanceOf;

    constructor(IERC20 shares_) {
        shares = shares_;
    }

    function deposit(uint256 amount) external {
        balanceOf[msg.sender] += amount;
        shares.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint256 amount) external {
        balanceOf[msg.sender] -= amount;
        shares.safeTransfer(msg.sender, amount);
    }
}

contract SDUSD_PrincipalOf_Test is SDUSDCommon {
    function test_SeedHasZeroPrincipalAndOrdinaryDepositsBelongToReceiver() public {
        assertEq(vault.principalOf(SEED_LOCK), 0);
        assertEq(vault.principalOf(USER), 1 ether);
        dusd.mint(address(this), 5 ether);
        dusd.approve(address(vault), 5 ether);

        vault.deposit(2 ether, RECEIVER);
        vault.mint(3 ether, RECEIVER);

        assertEq(vault.principalOf(address(this)), 0);
        assertEq(vault.principalOf(RECEIVER), 5 ether);
        assertEq(vault.principalOf(USER), 1 ether);
        assertEq(vault.depositCapUsage(), 6 ether);
    }

    function test_MintRecordsActualAssetsPaidAtHigherSharePrice() public {
        _notifyRewards(REWARD_AMOUNT);
        _finishRewardPeriod();
        uint256 assets = _mintFor(RECEIVER, 1 ether);

        assertGt(assets, 1 ether);
        assertEq(vault.principalOf(RECEIVER), assets);
        assertEq(vault.depositCapUsage(), 1 ether + assets);
    }

    function test_OrdinaryPreSeedDepositorCanExitAndReleasesAllPrincipal() public {
        _useEmptyVault();
        uint256 shares = _depositFor(USER, SEED_SHARES);
        assertEq(vault.principalOf(USER), SEED_SHARES);
        assertEq(vault.depositCapUsage(), SEED_SHARES);

        vm.prank(USER);
        vault.redeem(shares, USER, USER);

        assertEq(vault.principalOf(USER), 0);
        assertEq(vault.depositCapUsage(), 0);
        assertEq(vault.totalSupply(), 0);
    }

    function test_NonstandardFirstDepositToLockCountsPrincipal() public {
        _useEmptyVault();
        uint256 assets = SEED_SHARES + 1;
        dusd.mint(address(this), assets);
        dusd.approve(address(vault), assets);
        vault.deposit(assets, SEED_LOCK);

        assertEq(vault.principalOf(SEED_LOCK), assets);
        assertEq(vault.depositCapUsage(), assets);
    }

    function test_AdditionalDepositsAndTransfersToLockKeepConsumingCapacity() public {
        dusd.mint(address(this), 2 ether);
        dusd.approve(address(vault), 2 ether);
        vault.deposit(2 ether, SEED_LOCK);
        vm.prank(USER);
        vault.transfer(SEED_LOCK, 0.5 ether);

        assertEq(vault.principalOf(SEED_LOCK), 2.5 ether);
        assertEq(vault.principalOf(USER), 0.5 ether);
        assertEq(vault.depositCapUsage(), 3 ether);
    }

    function test_RewardsNeverIncreaseHolderPrincipal() public {
        _depositFor(RECEIVER, 100 ether);
        _notifyRewards(REWARD_AMOUNT);
        for (uint256 i; i < 3; ++i) {
            vm.warp(vault.periodStart() + REWARD_DURATION * i / 2);
            assertEq(vault.principalOf(USER), 1 ether);
            assertEq(vault.principalOf(RECEIVER), 100 ether);
            assertEq(vault.depositCapUsage(), 101 ether);
        }
    }

    function test_TransferMergesDifferentEntryBasesAndRecipientExitLeavesSenderBasis() public {
        _notifyRewards(REWARD_AMOUNT);
        _finishRewardPeriod();
        _depositFor(RECEIVER, 100 ether);
        vm.prank(USER);
        vault.transfer(RECEIVER, 0.5 ether);

        assertEq(vault.principalOf(USER), 0.5 ether);
        assertEq(vault.principalOf(RECEIVER), 100.5 ether);
        assertEq(vault.depositCapUsage(), 101 ether);
        uint256 receiverShares = vault.balanceOf(RECEIVER);
        vm.prank(RECEIVER);
        vault.redeem(receiverShares, RECEIVER, RECEIVER);

        assertEq(vault.principalOf(RECEIVER), 0);
        assertEq(vault.principalOf(USER), 0.5 ether);
        assertEq(vault.depositCapUsage(), 0.5 ether);
    }

    function test_TransferFromAndDelegatedWithdrawUseShareOwnerBasis() public {
        _notifyRewards(REWARD_AMOUNT);
        _finishRewardPeriod();
        uint256 shares = _depositFor(RECEIVER, 100 ether);
        vm.prank(RECEIVER);
        vault.approve(SPENDER, shares);
        vm.prank(SPENDER);
        vault.transferFrom(RECEIVER, USER, shares);

        assertEq(vault.principalOf(RECEIVER), 0);
        assertEq(vault.principalOf(USER), 101 ether);
        assertEq(vault.depositCapUsage(), 101 ether);
        vm.prank(USER);
        vault.approve(SPENDER, type(uint256).max);
        uint256 assets = vault.maxWithdraw(USER);
        vm.prank(SPENDER);
        vault.withdraw(assets, RECEIVER, USER);

        assertEq(vault.balanceOf(USER), 0);
        assertEq(vault.principalOf(USER), 0);
        assertEq(vault.principalOf(SPENDER), 0);
        assertEq(vault.depositCapUsage(), 0);
    }

    function test_PartialTransferAndBurnLeaveRoundingRemainderUntilFullExit() public {
        // The virtualized exchange rate becomes exactly three DUSD per share.
        _notifyRewards(2 * (vault.totalSupply() + 1));
        _finishRewardPeriod();
        assertEq(_depositFor(RECEIVER, 10), 3);
        vm.prank(RECEIVER);
        vault.transfer(SPENDER, 1);
        assertEq(vault.principalOf(RECEIVER), 7);
        assertEq(vault.principalOf(SPENDER), 3);
        assertEq(vault.depositCapUsage(), 1 ether + 10);

        vm.prank(RECEIVER);
        vault.redeem(1, RECEIVER, RECEIVER);
        assertEq(vault.principalOf(RECEIVER), 4);
        assertEq(vault.depositCapUsage(), 1 ether + 7);
        vm.prank(RECEIVER);
        vault.redeem(1, RECEIVER, RECEIVER);
        vm.prank(SPENDER);
        vault.redeem(1, SPENDER, SPENDER);

        assertEq(vault.principalOf(RECEIVER), 0);
        assertEq(vault.principalOf(SPENDER), 0);
        assertEq(vault.depositCapUsage(), 1 ether);
    }

    function test_SelfAndZeroTransfersLeaveAllPrincipalUnchanged() public {
        vm.startPrank(USER);
        vault.transfer(USER, 0.5 ether);
        vault.transfer(RECEIVER, 0);
        vault.approve(SPENDER, 0.5 ether);
        vm.stopPrank();
        vm.prank(SPENDER);
        vault.transferFrom(USER, USER, 0.5 ether);
        vm.prank(RECEIVER);
        vault.transfer(USER, 0);

        assertEq(vault.principalOf(USER), 1 ether);
        assertEq(vault.principalOf(RECEIVER), 0);
        assertEq(vault.depositCapUsage(), 1 ether);
    }

    function test_FailedTransferPreservesPrincipalAndTokenError() public {
        uint256 shares = vault.balanceOf(USER);
        vm.prank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, USER, shares, shares + 1)
        );
        vault.transfer(RECEIVER, shares + 1);

        assertEq(vault.principalOf(USER), 1 ether);
        assertEq(vault.principalOf(RECEIVER), 0);
        assertEq(vault.depositCapUsage(), 1 ether);
    }

    function test_MixedDepositsUseHolderAverageBasisOnPartialExit() public {
        // The exchange rate becomes exactly two. New shares blend only this holder's own basis.
        _notifyRewards(vault.totalSupply() + 1);
        _finishRewardPeriod();
        assertEq(_depositFor(USER, 2 ether), 1 ether);
        assertEq(vault.principalOf(USER), 3 ether);
        vm.prank(USER);
        vault.redeem(1 ether, USER, USER);

        assertEq(vault.balanceOf(USER), 1 ether);
        assertEq(vault.principalOf(USER), 1.5 ether);
        assertEq(vault.depositCapUsage(), 1.5 ether);
    }

    function test_RepeatedNewPositionRoundTripsCannotConsumeHeadroom() public {
        _depositFor(USER, 449 ether);
        _setDepositCap(500 ether);
        _notifyRewards(100 ether);
        _finishRewardPeriod();
        uint256 supplyBefore = vault.totalSupply();
        dusd.mint(RECEIVER, 51 ether);
        vm.startPrank(RECEIVER);
        dusd.approve(address(vault), type(uint256).max);
        for (uint256 i; i < 128; ++i) {
            uint256 shares = vault.deposit(50 ether, RECEIVER);
            vault.redeem(shares, RECEIVER, RECEIVER);
            assertEq(vault.depositCapUsage(), 450 ether);
            assertEq(vault.maxDeposit(RECEIVER), 50 ether);
        }
        vm.stopPrank();

        assertEq(vault.totalSupply(), supplyBefore);
        assertEq(vault.principalOf(RECEIVER), 0);
        assertEq(vault.principalOf(USER), 450 ether);
    }

    function test_CustodialPoolingCanReassignOtherHoldersBasis() public {
        PrincipalSharePool pool = new PrincipalSharePool(IERC20(address(vault)));
        _notifyRewards(vault.totalSupply() + 1);
        _finishRewardPeriod();
        vm.startPrank(USER);
        vault.approve(address(pool), 1 ether);
        pool.deposit(1 ether);
        vm.stopPrank();
        assertEq(vault.principalOf(address(pool)), 1 ether);

        uint256 shares = _depositFor(RECEIVER, 2 ether);
        assertEq(shares, 1 ether);
        vm.startPrank(RECEIVER);
        vault.approve(address(pool), shares);
        pool.deposit(shares);
        pool.withdraw(shares);
        uint256 assets = vault.redeem(shares, RECEIVER, RECEIVER);
        vm.stopPrank();

        // Average basis is tracked per address, so a custodian merges its depositors' bases.
        assertEq(assets, 2 ether);
        assertEq(vault.balanceOf(RECEIVER), 0);
        assertEq(pool.balanceOf(RECEIVER), 0);
        assertEq(vault.principalOf(RECEIVER), 0);
        assertEq(pool.balanceOf(USER), 1 ether);
        assertEq(vault.balanceOf(address(pool)), 1 ether);
        assertEq(vault.principalOf(address(pool)), 1.5 ether);
        assertEq(vault.depositCapUsage(), 1.5 ether);
    }

    function testFuzz_NewPositionRoundTripRestoresHeadroom(uint256 reward, uint256 assets) public {
        reward = bound(reward, 1, 1_000 ether);
        _notifyRewards(reward);
        _finishRewardPeriod();
        assets = bound(assets, vault.previewMint(1), 1_000 ether);
        uint256 headroomBefore = vault.maxDeposit(RECEIVER);
        uint256 principalBefore = vault.depositCapUsage();
        uint256 shares = _depositFor(RECEIVER, assets);
        vm.prank(RECEIVER);
        vault.redeem(shares, RECEIVER, RECEIVER);

        assertEq(vault.principalOf(RECEIVER), 0);
        assertEq(vault.principalOf(USER), principalBefore);
        assertEq(vault.depositCapUsage(), principalBefore);
        assertEq(vault.maxDeposit(RECEIVER), headroomBefore);
    }

    function testFuzz_PrincipalConservedAcrossMixedOperations(uint256 entropy) public {
        address[3] memory holders = [USER, RECEIVER, SPENDER];
        for (uint256 i; i < 32; ++i) {
            entropy = uint256(keccak256(abi.encode(entropy, i)));
            address holder = holders[entropy % 3];
            uint256 action = (entropy >> 8) % 4;
            uint256 shares = vault.balanceOf(holder);
            if (action == 0) {
                _depositFor(holder, 1 ether + ((entropy >> 16) % (100 ether)));
            } else if (action == 1) {
                address receiver = holders[(entropy >> 16) % 3];
                uint256 usageBefore = vault.depositCapUsage();
                vm.prank(holder);
                vault.transfer(receiver, (entropy >> 32) % (shares + 1));
                assertEq(vault.depositCapUsage(), usageBefore);
            } else if (action == 2) {
                vm.prank(holder);
                vault.redeem((entropy >> 16) % (shares + 1), holder, holder);
            } else if (vault.totalSupply() > vault.balanceOf(SEED_LOCK)) {
                uint256 usageBefore = vault.depositCapUsage();
                _notifyRewards(1 ether + ((entropy >> 16) % (10 ether)));
                _finishRewardPeriod();
                assertEq(vault.depositCapUsage(), usageBefore);
            }

            uint256 sum;
            for (uint256 j; j < holders.length; ++j) {
                sum += vault.principalOf(holders[j]);
                if (vault.balanceOf(holders[j]) == 0) assertEq(vault.principalOf(holders[j]), 0);
            }
            assertEq(vault.depositCapUsage(), sum);
            assertEq(vault.principalOf(SEED_LOCK), 0);
        }

        for (uint256 i; i < holders.length; ++i) {
            address holder = holders[i];
            uint256 shares = vault.balanceOf(holder);
            vm.prank(holder);
            vault.redeem(shares, holder, holder);
            assertEq(vault.principalOf(holder), 0);
        }
        assertEq(vault.depositCapUsage(), 0);
    }
}
