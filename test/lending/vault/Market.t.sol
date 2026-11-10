// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {stdError} from "forge-std/StdError.sol";

import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import "./helpers/IntegrationTest.sol";

contract MarketTest is IntegrationTest {
    using FixedPointMath for uint256;
    IERC4626 public erc4626Vault;

    function setUp() public override {
        super.setUp();

        erc4626Vault = IERC4626(address(vault));

        _setCap(allMarkets[0], CAP);
        _setCap(allMarkets[1], CAP);
        _setCap(allMarkets[2], CAP);
    }

    function testMintAllCapsReached() public {
        vm.prank(ALLOCATOR);
        vault.setSupplyQueue(new address[](0));

        loanToken.setBalance(SUPPLIER, 1);

        vm.prank(SUPPLIER);
        loanToken.approve(address(vault), type(uint256).max);

        vm.expectRevert(IAltoVaultErrors.AllCapsReached.selector);
        vm.prank(SUPPLIER);
        erc4626Vault.mint(1, RECEIVER);
    }

    function testDepositAllCapsReached() public {
        vm.prank(ALLOCATOR);
        vault.setSupplyQueue(new address[](0));

        loanToken.setBalance(SUPPLIER, 1);

        vm.prank(SUPPLIER);
        loanToken.approve(address(vault), type(uint256).max);

        vm.expectRevert(IAltoVaultErrors.AllCapsReached.selector);
        vm.prank(SUPPLIER);
        erc4626Vault.deposit(1, RECEIVER);
    }

    function testSubmitCapOverflow(uint256 seed, uint256 cap) public {
        address market = _randomMarket(seed);
        cap = bound(cap, uint256(type(uint184).max) + 1, type(uint256).max);

        vm.prank(CURATOR);
        vm.expectRevert(abi.encodeWithSelector(SafeCast.SafeCastOverflowedUintDowncast.selector, uint8(184), cap));
        vault.submitCap(market, cap);
    }

    function testSubmitCapInconsistentAsset(
        ERC20MockMintable collateralToken,
        ERC20MockMintable loanToken,
        uint256 lltv
    ) public {
        vm.assume(erc4626Vault.asset() != address(loanToken));
        vm.assume(address(collateralToken) != address(0));
        vm.assume(address(loanToken) != address(0));
        lltv = bound(lltv, 0.5 ether, 0.8 ether);

        address market = _deployMarket(address(collateralToken), address(loanToken), lltv, address(0), address(0));
        _registerMarketInRegistry(market);

        vm.prank(CURATOR);
        vm.expectRevert(abi.encodeWithSelector(IAltoVaultErrors.InconsistentAsset.selector, market));
        vault.submitCap(market, 0);
    }

    function testSubmitCapAlreadySet() public {
        vm.prank(CURATOR);
        vm.expectRevert(IAltoVaultErrors.AlreadySet.selector);
        vault.submitCap(allMarkets[0], CAP);
    }

    function testSubmitCapAlreadyPending() public {
        vm.prank(CURATOR);
        vault.submitCap(allMarkets[0], CAP + 1);

        vm.prank(CURATOR);
        vm.expectRevert(IAltoVaultErrors.AlreadyPending.selector);
        vault.submitCap(allMarkets[0], CAP + 1);
    }

    function testSubmitCapPendingRemoval() public {
        vm.startPrank(CURATOR);
        vault.submitCap(allMarkets[2], 0);
        vault.submitMarketRemoval(allMarkets[2]);

        vm.expectRevert(IAltoVaultErrors.PendingRemoval.selector);
        vault.submitCap(allMarkets[2], CAP + 1);
    }

    function testSetSupplyQueue() public {
        address[] memory supplyQueue = new address[](2);
        supplyQueue[0] = allMarkets[1];
        supplyQueue[1] = allMarkets[2];

        vm.expectEmit();
        emit IAltoVaultEvents.SetSupplyQueue(ALLOCATOR, supplyQueue);
        vm.prank(ALLOCATOR);
        vault.setSupplyQueue(supplyQueue);

        assertEq(vault.supplyQueue(0), allMarkets[1]);
        assertEq(vault.supplyQueue(1), allMarkets[2]);
    }

    function testSetSupplyQueueMaxQueueLengthExceeded() public {
        address[] memory supplyQueue = new address[](ConstantsLib.MAX_QUEUE_LENGTH + 1);

        vm.prank(ALLOCATOR);
        vm.expectRevert(IAltoVaultErrors.MaxQueueLengthExceeded.selector);
        vault.setSupplyQueue(supplyQueue);
    }

    function testAcceptCapMaxQueueLengthExceeded() public {
        for (uint256 i = 3; i < ConstantsLib.MAX_QUEUE_LENGTH - 1; ++i) {
            _setCap(allMarkets[i], CAP);
        }

        _setTimelock(1 weeks);

        address market = allMarkets[ConstantsLib.MAX_QUEUE_LENGTH];

        vm.prank(CURATOR);
        vault.submitCap(market, CAP);

        vm.warp(block.timestamp + 1 weeks);

        vm.expectRevert(IAltoVaultErrors.MaxQueueLengthExceeded.selector);
        vault.acceptCap(market);
    }

    function testSetSupplyQueueUnauthorizedMarket() public {
        address[] memory supplyQueue = new address[](1);
        supplyQueue[0] = allMarkets[3];

        vm.prank(ALLOCATOR);
        vm.expectRevert(abi.encodeWithSelector(IAltoVaultErrors.UnauthorizedMarket.selector, supplyQueue[0]));
        vault.setSupplyQueue(supplyQueue);
    }

    function testUpdateWithdrawQueue() public {
        uint256[] memory indexes = new uint256[](4);
        indexes[0] = 1;
        indexes[1] = 2;
        indexes[2] = 3;
        indexes[3] = 0;

        address[] memory expectedWithdrawQueue = new address[](4);
        expectedWithdrawQueue[0] = allMarkets[0];
        expectedWithdrawQueue[1] = allMarkets[1];
        expectedWithdrawQueue[2] = allMarkets[2];
        expectedWithdrawQueue[3] = idleMarket;

        vm.expectEmit(address(erc4626Vault));
        emit IAltoVaultEvents.SetWithdrawQueue(ALLOCATOR, expectedWithdrawQueue);
        vm.prank(ALLOCATOR);
        vault.updateWithdrawQueue(indexes);

        assertEq(vault.withdrawQueue(0), expectedWithdrawQueue[0]);
        assertEq(vault.withdrawQueue(1), expectedWithdrawQueue[1]);
        assertEq(vault.withdrawQueue(2), expectedWithdrawQueue[2]);
        assertEq(vault.withdrawQueue(3), expectedWithdrawQueue[3]);
    }

    function testUpdateWithdrawQueueRemovingDisabledMarket() public {
        _setCap(allMarkets[2], 0);

        vm.prank(CURATOR);
        vault.submitMarketRemoval(allMarkets[2]);

        vm.warp(block.timestamp + TIMELOCK);

        uint256[] memory indexes = new uint256[](3);
        indexes[0] = 0;
        indexes[1] = 2;
        indexes[2] = 1;

        address[] memory expectedWithdrawQueue = new address[](3);
        expectedWithdrawQueue[0] = idleMarket;
        expectedWithdrawQueue[1] = allMarkets[1];
        expectedWithdrawQueue[2] = allMarkets[0];

        vm.expectEmit();
        emit IAltoVaultEvents.SetWithdrawQueue(ALLOCATOR, expectedWithdrawQueue);
        vm.prank(ALLOCATOR);
        vault.updateWithdrawQueue(indexes);

        assertEq(vault.withdrawQueue(0), expectedWithdrawQueue[0]);
        assertEq(vault.withdrawQueue(1), expectedWithdrawQueue[1]);
        assertEq(vault.withdrawQueue(2), expectedWithdrawQueue[2]);
        assertFalse(vault.config(allMarkets[2]).enabled);
        assertEq(vault.pendingCap(allMarkets[2]).value, 0, "pendingCap.value");
        assertEq(vault.pendingCap(allMarkets[2]).validAt, 0, "pendingCap.validAt");
    }

    function testSubmitMarketRemoval() public {
        vm.startPrank(CURATOR);
        vault.submitCap(allMarkets[2], 0);
        vm.expectEmit();
        emit IAltoVaultEvents.SubmitMarketRemoval(CURATOR, allMarkets[2]);
        vault.submitMarketRemoval(allMarkets[2]);
        vm.stopPrank();

        assertEq(vault.config(allMarkets[2]).cap, 0);
        assertEq(vault.config(allMarkets[2]).removableAt, block.timestamp + TIMELOCK);
    }

    function testSubmitMarketRemovalPendingCap() public {
        vm.startPrank(CURATOR);
        vault.submitCap(allMarkets[2], 0);
        vault.submitCap(allMarkets[2], vault.config(allMarkets[2]).cap + 1);
        vm.expectRevert(abi.encodeWithSelector(IAltoVaultErrors.PendingCap.selector, allMarkets[2]));
        vault.submitMarketRemoval(allMarkets[2]);
        vm.stopPrank();
    }

    function testSubmitMarketRemovalNonZeroCap() public {
        vm.startPrank(CURATOR);
        vm.expectRevert(IAltoVaultErrors.NonZeroCap.selector);
        vault.submitMarketRemoval(allMarkets[2]);
        vm.stopPrank();
    }

    function testSubmitMarketRemovalAlreadyPending() public {
        vm.startPrank(CURATOR);
        vault.submitCap(allMarkets[2], 0);
        vault.submitMarketRemoval(allMarkets[2]);
        vm.expectRevert(IAltoVaultErrors.AlreadyPending.selector);
        vault.submitMarketRemoval(allMarkets[2]);
        vm.stopPrank();
    }

    function testUpdateWithdrawQueueInvalidIndex() public {
        uint256[] memory indexes = new uint256[](4);
        indexes[0] = 1;
        indexes[1] = 2;
        indexes[2] = 3;
        indexes[3] = 4;

        vm.prank(ALLOCATOR);
        vm.expectRevert(stdError.indexOOBError);
        vault.updateWithdrawQueue(indexes);
    }

    function testUpdateWithdrawQueueDuplicateMarket() public {
        uint256[] memory indexes = new uint256[](4);
        indexes[0] = 1;
        indexes[1] = 2;
        indexes[2] = 1;
        indexes[3] = 3;

        vm.prank(ALLOCATOR);
        vm.expectRevert(abi.encodeWithSelector(IAltoVaultErrors.DuplicateMarket.selector, allMarkets[0]));
        vault.updateWithdrawQueue(indexes);
    }

    function testUpdateWithdrawQueueInvalidMarketRemovalNonZeroSupply() public {
        loanToken.setBalance(SUPPLIER, 1);

        vm.prank(SUPPLIER);
        erc4626Vault.deposit(1, RECEIVER);

        uint256[] memory indexes = new uint256[](3);
        indexes[0] = 1;
        indexes[1] = 2;
        indexes[2] = 3;

        _setCap(idleMarket, 0);

        vm.prank(ALLOCATOR);
        vm.expectRevert(abi.encodeWithSelector(IAltoVaultErrors.InvalidMarketRemovalNonZeroSupply.selector, idleMarket));
        vault.updateWithdrawQueue(indexes);
    }

    function testUpdateWithdrawQueueInvalidMarketRemovalNonZeroCap() public {
        uint256[] memory indexes = new uint256[](3);
        indexes[0] = 1;
        indexes[1] = 2;
        indexes[2] = 3;

        vm.expectRevert(abi.encodeWithSelector(IAltoVaultErrors.InvalidMarketRemovalNonZeroCap.selector, idleMarket));

        vm.prank(ALLOCATOR);
        vault.updateWithdrawQueue(indexes);
    }

    function testUpdateWithdrawQueueInvalidMarketRemovalTimelockNotElapsed(uint256 elapsed) public {
        elapsed = bound(elapsed, 0, TIMELOCK - 1);

        loanToken.setBalance(SUPPLIER, 1);

        vm.prank(SUPPLIER);
        erc4626Vault.deposit(1, RECEIVER);

        _setCap(idleMarket, 0);

        vm.prank(CURATOR);
        vault.submitMarketRemoval(idleMarket);

        vm.warp(block.timestamp + elapsed);

        uint256[] memory indexes = new uint256[](3);
        indexes[0] = 1;
        indexes[1] = 2;
        indexes[2] = 3;

        vm.prank(ALLOCATOR);
        vm.expectRevert(
            abi.encodeWithSelector(IAltoVaultErrors.InvalidMarketRemovalTimelockNotElapsed.selector, idleMarket)
        );
        vault.updateWithdrawQueue(indexes);
    }

    function testUpdateWithdrawQueueInvalidMarketRemovalPendingCap(uint256 cap) public {
        cap = bound(cap, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        _setCap(allMarkets[2], 0);
        vm.prank(CURATOR);
        vault.submitCap(allMarkets[2], cap);

        uint256[] memory indexes = new uint256[](3);
        indexes[0] = 0;
        indexes[1] = 2;
        indexes[2] = 1;

        vm.prank(ALLOCATOR);
        vm.expectRevert(abi.encodeWithSelector(IAltoVaultErrors.PendingCap.selector, allMarkets[2]));
        vault.updateWithdrawQueue(indexes);
    }

    function testEnableMarketWithLiquidity(uint256 deposited, uint256 additionalSupply, uint256 blocks) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);
        additionalSupply = bound(additionalSupply, MIN_TEST_ASSETS, MAX_TEST_ASSETS);
        blocks = _boundBlocks(blocks);

        address[] memory supplyQueue = new address[](1);
        supplyQueue[0] = allMarkets[0];

        _setCap(allMarkets[0], deposited);

        vm.prank(ALLOCATOR);
        vault.setSupplyQueue(supplyQueue);

        loanToken.setBalance(SUPPLIER, deposited + additionalSupply);

        vm.startPrank(SUPPLIER);
        erc4626Vault.deposit(deposited, ONBEHALF);
        IMarket(allMarkets[3]).addSupply(additionalSupply, 0, address(vault));
        vm.stopPrank();

        uint256 collateral = uint256(MAX_TEST_ASSETS).divideWithPrecisionUp(allMarketsLltvs[0]);
        collateralToken.setBalance(BORROWER, collateral);

        vm.startPrank(BORROWER);
        IMarket(allMarkets[0]).addCollateral(collateral, BORROWER);
        IMarket(allMarkets[0]).borrow(deposited, 0, BORROWER, BORROWER, hex"");
        vm.stopPrank();

        _forward(blocks);

        _setCap(allMarkets[3], CAP);

        assertEq(vault.lastTotalAssets(), deposited + additionalSupply);
    }

    function testRevokeNoRevert() public {
        vm.startPrank(OWNER);
        vault.revokePendingTimelock();
        vault.revokePendingGuardian();
        vault.revokePendingCap(address(0));
        vault.revokePendingMarketRemoval(address(0));
        vm.stopPrank();
    }
}
