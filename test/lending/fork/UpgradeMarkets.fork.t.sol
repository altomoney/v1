// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";
import {AltoBorrowMarket} from "@alto/lending/AltoBorrowMarket.sol";
import {IMarket, Balance, Position} from "@alto/lending/interfaces/IMarket.sol";
import {IMintableERC20} from "@alto/lending/interfaces/IMintableERC20.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract UpgradeMarketsForkTest is Test {
    address constant TIMELOCK = 0xfAe841679dc1A93D225ECc827E4BbF3e8d703F86;
    address constant FEE_RECIPIENT_MINT = 0x5F80c18b6B73B1C4F06fa5233De32778eC90FA96;

    // Mint markets
    address constant WETH_MARKET = 0x8DED9e2B8Bc5128B862dD534b97c8a32991959ff;
    address constant WSTETH_MARKET = 0xfd8c25047f4397dC5461B919999585a2a3EaC2eF;
    address constant RETH_MARKET = 0xc0E2DdB06bB034c1F980531EC5CAd944D71AfFbf;
    address constant METH_MARKET = 0xF897188DCd300Fa80a2f7f0f0290F9eF64F2D47b;
    address constant TBTC_MARKET = 0xE17F10f8535336143d4F2FE304f3Dcf7B23671e1;

    // Borrow markets
    address constant WBTC_BORROW = 0xefd78a5970a43e25b30426C3952065217c55e5E4;
    address constant CBBTC_BORROW = 0xaE4f2B998783e2041E87E08Da73985e4E0420159;
    address constant SUSDE_BORROW = 0x133cf03d2A7a87B9239b1a3a8Dd62f3f27c46788;
    address constant SYRUPUSDC_BORROW = 0x33B24510233281350bF8679A7c427d04db0ed208;
    address constant PAXG_BORROW = 0x99f538Ec7c840197DcAf30A25B635482ba9e8817;

    uint128 constant PLACEHOLDER_BAD_DEBT = 1e18;

    address[] mintMarkets;
    address[] borrowMarkets;

    address newMintImpl;
    address newBorrowImpl;

    struct MarketSnapshot {
        address borrowToken;
        address collateralToken;
        Balance totalSupply;
        Balance totalBorrowed;
        address irm;
        address oracle;
        uint256 maxLtv;
        uint256 borrowOpeningFee;
        address feeRecipient;
        address liquidationEngine;
    }

    function setUp() public {
        string memory rpcUrl = vm.rpcUrl("ethereum");
        vm.createSelectFork(rpcUrl);

        mintMarkets.push(WETH_MARKET);
        mintMarkets.push(WSTETH_MARKET);
        mintMarkets.push(RETH_MARKET);
        mintMarkets.push(METH_MARKET);
        mintMarkets.push(TBTC_MARKET);

        borrowMarkets.push(WBTC_BORROW);
        borrowMarkets.push(CBBTC_BORROW);
        borrowMarkets.push(SUSDE_BORROW);
        borrowMarkets.push(SYRUPUSDC_BORROW);
        borrowMarkets.push(PAXG_BORROW);

        newMintImpl = address(new AltoMintMarket());
        newBorrowImpl = address(new AltoBorrowMarket());
    }

    function _snapshotMarket(address market) internal view returns (MarketSnapshot memory) {
        IMarket m = IMarket(market);
        return MarketSnapshot({
            borrowToken: m.borrowToken(),
            collateralToken: m.collateralToken(),
            totalSupply: m.totalSupply(),
            totalBorrowed: m.totalBorrowed(),
            irm: m.irm(),
            oracle: m.oracle(),
            maxLtv: m.maxLtv(),
            borrowOpeningFee: m.borrowOpeningFee(),
            feeRecipient: m.feeRecipient(),
            liquidationEngine: m.liquidationEngine()
        });
    }

    function _assertSnapshotsEqual(MarketSnapshot memory before, MarketSnapshot memory after_) internal pure {
        assertEq(before.borrowToken, after_.borrowToken, "borrowToken changed");
        assertEq(before.collateralToken, after_.collateralToken, "collateralToken changed");
        assertEq(before.totalSupply.assets, after_.totalSupply.assets, "totalSupply.assets changed");
        assertEq(before.totalSupply.shares, after_.totalSupply.shares, "totalSupply.shares changed");
        assertEq(before.totalBorrowed.assets, after_.totalBorrowed.assets, "totalBorrowed.assets changed");
        assertEq(before.totalBorrowed.shares, after_.totalBorrowed.shares, "totalBorrowed.shares changed");
        assertEq(before.irm, after_.irm, "irm changed");
        assertEq(before.oracle, after_.oracle, "oracle changed");
        assertEq(before.maxLtv, after_.maxLtv, "maxLtv changed");
        assertEq(before.borrowOpeningFee, after_.borrowOpeningFee, "borrowOpeningFee changed");
        assertEq(before.feeRecipient, after_.feeRecipient, "feeRecipient changed");
        assertEq(before.liquidationEngine, after_.liquidationEngine, "liquidationEngine changed");
    }

    // ─── Phase 1: Upgrade verification ───

    function test_upgradeMintMarkets_preservesState() public {
        MarketSnapshot[] memory snapshots = new MarketSnapshot[](mintMarkets.length);
        uint128[] memory claimableBefore = new uint128[](mintMarkets.length);

        for (uint256 i = 0; i < mintMarkets.length; i++) {
            snapshots[i] = _snapshotMarket(mintMarkets[i]);
            claimableBefore[i] = AltoMintMarket(mintMarkets[i]).claimableFeesAssets();
        }

        vm.startPrank(TIMELOCK);
        for (uint256 i = 0; i < mintMarkets.length; i++) {
            UnsafeUpgrades.upgradeProxy(
                mintMarkets[i],
                newMintImpl,
                abi.encodeCall(AltoMintMarket.initializeV2, (PLACEHOLDER_BAD_DEBT))
            );
        }
        vm.stopPrank();

        for (uint256 i = 0; i < mintMarkets.length; i++) {
            _assertSnapshotsEqual(snapshots[i], _snapshotMarket(mintMarkets[i]));
            assertEq(
                AltoMintMarket(mintMarkets[i]).claimableFeesAssets(),
                claimableBefore[i],
                "claimableFeesAssets changed"
            );
            assertEq(
                AltoMintMarket(mintMarkets[i]).badDebtAssets(), PLACEHOLDER_BAD_DEBT, "badDebtAssets not initialized"
            );
        }
    }

    function test_upgradeBorrowMarkets_preservesState() public {
        MarketSnapshot[] memory snapshots = new MarketSnapshot[](borrowMarkets.length);
        uint128[] memory supplyCapBefore = new uint128[](borrowMarkets.length);
        uint256[] memory interestFeeBefore = new uint256[](borrowMarkets.length);

        for (uint256 i = 0; i < borrowMarkets.length; i++) {
            snapshots[i] = _snapshotMarket(borrowMarkets[i]);
            supplyCapBefore[i] = AltoBorrowMarket(borrowMarkets[i]).supplyCapAssets();
            interestFeeBefore[i] = AltoBorrowMarket(borrowMarkets[i]).interestFee();
        }

        vm.startPrank(TIMELOCK);
        for (uint256 i = 0; i < borrowMarkets.length; i++) {
            UnsafeUpgrades.upgradeProxy(borrowMarkets[i], newBorrowImpl, "");
        }
        vm.stopPrank();

        for (uint256 i = 0; i < borrowMarkets.length; i++) {
            _assertSnapshotsEqual(snapshots[i], _snapshotMarket(borrowMarkets[i]));
            assertEq(
                AltoBorrowMarket(borrowMarkets[i]).supplyCapAssets(),
                supplyCapBefore[i],
                "supplyCapAssets changed"
            );
            assertEq(
                AltoBorrowMarket(borrowMarkets[i]).interestFee(), interestFeeBefore[i], "interestFee changed"
            );
        }
    }

    function test_upgradeRevertWhenNotOwner() public {
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        AltoMintMarket(WETH_MARKET).upgradeToAndCall(
            newMintImpl, abi.encodeCall(AltoMintMarket.initializeV2, (PLACEHOLDER_BAD_DEBT))
        );
    }

    // ─── Phase 2: Post-upgrade operations on MintMarket ───

    function test_mintMarket_postUpgrade_claimInterestPermissionless() public {
        _upgradeAllMarkets();

        AltoMintMarket market = AltoMintMarket(WETH_MARKET);
        uint128 claimable = market.claimableFeesAssets();

        if (claimable > 0) {
            address randomUser = makeAddr("randomClaimer");
            vm.prank(randomUser);
            uint256 claimed = market.claimInterest(0);
            assertEq(claimed, claimable, "should claim all");
            assertEq(market.claimableFeesAssets(), 0, "claimable should be 0 after claim");
        }
    }

    function test_mintMarket_postUpgrade_repayAutoClaimsInterest() public {
        _upgradeAllMarkets();

        AltoMintMarket market = AltoMintMarket(WETH_MARKET);
        address borrowToken = market.borrowToken();
        address collateralToken = market.collateralToken();
        address feeRecipient = market.feeRecipient();

        address borrower = makeAddr("repayBorrower");

        // Set up a position: add collateral and borrow
        deal(collateralToken, borrower, 100 ether);
        vm.startPrank(borrower);
        IERC20(collateralToken).approve(address(market), type(uint256).max);
        market.addCollateral(100 ether, borrower);
        market.borrow(1 ether, 0, borrower, borrower, hex"");
        vm.stopPrank();

        // Accumulate interest
        vm.warp(block.timestamp + 1 days);
        market.accrueInterest();

        uint128 claimableBefore = market.claimableFeesAssets();
        assertGt(claimableBefore, 0, "should have claimable fees after interest accrual");

        uint256 feeRecipientBalBefore = IERC20(borrowToken).balanceOf(feeRecipient);

        // Repay triggers _claimInterest internally
        vm.startPrank(borrower);
        market.repay(0, 1, borrower);
        vm.stopPrank();

        assertEq(market.claimableFeesAssets(), 0, "claimable should be 0 after repay auto-claimed");
        assertGt(
            IERC20(borrowToken).balanceOf(feeRecipient),
            feeRecipientBalBefore,
            "fee recipient should have received claimed interest"
        );
    }

    function test_mintMarket_postUpgrade_governanceLiquidateNewSignature() public {
        _upgradeAllMarkets();

        address borrower = makeAddr("noBorrower");

        // governanceLiquidate with new (address, bool) signature should be callable
        // A borrower with no position returns (0, 0) without reverting
        vm.prank(TIMELOCK);
        (uint256 collateral, uint256 badDebt) = IMarket(WETH_MARKET).governanceLiquidate(borrower, false);
        assertEq(collateral, 0);
        assertEq(badDebt, 0);
    }

    // ─── Phase 2: Post-upgrade operations on BorrowMarket ───

    function test_borrowMarket_postUpgrade_setInterestFeeNewSignature() public {
        _upgradeAllMarkets();

        AltoBorrowMarket market = AltoBorrowMarket(WBTC_BORROW);
        uint256 currentFee = market.interestFee();

        vm.prank(TIMELOCK);
        market.setInterestFee(currentFee, false);

        assertEq(market.interestFee(), currentFee, "interestFee should remain the same");
    }

    function test_borrowMarket_postUpgrade_setFeeRecipient() public {
        _upgradeAllMarkets();

        AltoBorrowMarket market = AltoBorrowMarket(WBTC_BORROW);
        address currentRecipient = market.feeRecipient();

        vm.prank(TIMELOCK);
        market.setFeeRecipient(currentRecipient);

        assertEq(market.feeRecipient(), currentRecipient, "feeRecipient should remain the same");
    }

    function test_borrowMarket_postUpgrade_accrueInterest() public {
        _upgradeAllMarkets();

        vm.warp(block.timestamp + 1 days);

        for (uint256 i = 0; i < borrowMarkets.length; i++) {
            IMarket(borrowMarkets[i]).accrueInterest();
        }
    }

    function test_mintMarket_postUpgrade_accrueInterest() public {
        _upgradeAllMarkets();

        vm.warp(block.timestamp + 1 days);

        for (uint256 i = 0; i < mintMarkets.length; i++) {
            IMarket(mintMarkets[i]).accrueInterest();
        }
    }

    // ─── Helpers ───

    function _upgradeAllMarkets() internal {
        vm.startPrank(TIMELOCK);

        for (uint256 i = 0; i < mintMarkets.length; i++) {
            UnsafeUpgrades.upgradeProxy(
                mintMarkets[i],
                newMintImpl,
                abi.encodeCall(AltoMintMarket.initializeV2, (PLACEHOLDER_BAD_DEBT))
            );
        }

        for (uint256 i = 0; i < borrowMarkets.length; i++) {
            UnsafeUpgrades.upgradeProxy(borrowMarkets[i], newBorrowImpl, "");
        }

        vm.stopPrank();
    }
}
