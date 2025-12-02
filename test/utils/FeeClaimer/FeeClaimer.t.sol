// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {FeeClaimer} from "@alto/utils/FeeClaimer.sol";
import {IFeeClaimer, MarketType, TokenBalance} from "@alto/utils/interfaces/IFeeClaimer.sol";
import {LiquidationConfiguration} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {ERC20MockMintable} from "@alto-test/helpers/ERC20MockMintable.sol";
import {MockMarket, MockMarketDeployer} from "@alto-test/helpers/MockMarket.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OracleMock} from "@alto/oracles/mocks/OracleMock.sol";
import {LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {MockMintMarket} from "@alto-test/helpers/MockMintMarket.sol";
import {MockMintMarketDeployer} from "@alto-test/helpers/MockMintMarket.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import {DUSD} from "@alto/tokens/DUSD.sol";
import {BaseMarketInitParams} from "@alto/lending/interfaces/IMarket.sol";

contract FeeClaimerTest is Test, TestHelperOz5 {
    FeeClaimer public feeClaimer;
    DUSD dusd;
    ERC20MockMintable public borrowToken;
    ERC20MockMintable public collateralToken1;
    ERC20MockMintable public collateralToken2;
    MockMintMarket public mintMarket1;
    MockMintMarket public mintMarket2;
    MockMarket public borrowMarket1;
    MockMarket public borrowMarket2;
    LiquidationConfiguration public liquidationConfig;
    address public liquidationEngine;

    address public OWNER = makeAddr("owner");
    address public FEE_RECIPIENT = makeAddr("feeRecipient");
    address public FEE_CLAIMER = makeAddr("feeClaimer");

    uint256 public constant INITIAL_BALANCE = 1000000 ether;
    uint256 public constant CLAIMABLE_FEES = 1000 ether;
    uint256 public constant MINTED_AMOUNT = 500 ether;
    uint256 public constant CEILING_AMOUNT = 1000000 ether;

    function setUp() public override {
        super.setUp();
        setUpEndpoints(1, LibraryType.UltraLightNode);

        dusd = new DUSD(address(endpoints[1]), OWNER);
        borrowToken = ERC20MockMintable(address(dusd));
        collateralToken1 = new ERC20MockMintable("Collateral Token 1", "COLL1");
        collateralToken2 = new ERC20MockMintable("Collateral Token 2", "COLL2");

        // Deploy oracle and IRM
        address irm1 = address(new FixedRateIrm(0.04 ether / uint256(365 days), address(this)));
        address irm2 = address(new FixedRateIrm(0.04 ether / uint256(365 days), address(this)));
        address irm3 = address(new FixedRateIrm(0.04 ether / uint256(365 days), address(this)));
        address irm4 = address(new FixedRateIrm(0.04 ether / uint256(365 days), address(this)));
        address oracle = address(new OracleMock());
        OracleMock(oracle).setPrice(LENDING_ORACLE_PRICE_PRECISION);

        liquidationConfig = LiquidationConfiguration({
            maxLiquidationLtv: 0.8 ether,
            dynamicBonusFeeStart: 0.03 ether,
            ltvForCompleteLiquidation: 0.9 ether,
            dynamicBonusFeeDecaySteepness: 5 ether,
            liquidationBaseFee: 0.05 ether,
            minPenaltyPercentage: 0.01 ether,
            protocolFeePercentage: 0.075 ether,
            isEnabledPriorityLiquidation: true,
            disablePriorityLiquidationAbovePositionLtv: 0.95 ether,
            priorityLiquidationGracePeriod: 5 minutes,
            taggerLiquidationGracePeriod: 2 minutes,
            liquidationWindowTag: 3 days
        });

        // Deploy borrow markets using MockMarketDeployer
        borrowMarket1 = MockMarketDeployer.deployMarket(
            address(borrowToken),
            address(collateralToken1),
            address(irm1),
            OWNER,
            address(oracle),
            0.8 ether,
            0.01 ether,
            FEE_RECIPIENT,
            liquidationConfig
        );

        borrowMarket2 = MockMarketDeployer.deployMarket(
            address(borrowToken),
            address(collateralToken2),
            address(irm2),
            OWNER,
            address(oracle),
            0.8 ether,
            0.01 ether,
            FEE_RECIPIENT,
            liquidationConfig
        );

        mintMarket1 = MockMintMarketDeployer.deployMarket(
            address(borrowToken),
            address(collateralToken1),
            address(irm3),
            OWNER,
            address(oracle),
            0.8 ether,
            0.01 ether,
            FEE_RECIPIENT,
            liquidationConfig
        );
        mintMarket2 = MockMintMarketDeployer.deployMarket(
            address(borrowToken),
            address(collateralToken2),
            address(irm4),
            OWNER,
            address(oracle),
            0.8 ether,
            0.01 ether,
            FEE_RECIPIENT,
            liquidationConfig
        );

        // Deploy FeeClaimer
        feeClaimer = new FeeClaimer(OWNER, address(dusd), FEE_RECIPIENT);

        vm.startPrank(address(this));
        borrowToken.approve(address(mintMarket1), type(uint256).max);
        borrowToken.approve(address(mintMarket2), type(uint256).max);
        borrowToken.approve(address(borrowMarket1), type(uint256).max);
        borrowToken.approve(address(borrowMarket2), type(uint256).max);
        collateralToken1.approve(address(mintMarket1), type(uint256).max);
        collateralToken2.approve(address(mintMarket2), type(uint256).max);
        collateralToken1.approve(address(borrowMarket1), type(uint256).max);
        collateralToken2.approve(address(borrowMarket2), type(uint256).max);
        vm.stopPrank();

        // Add markets to fee claimer
        vm.startPrank(OWNER);

        dusd.setMinterStatus(address(mintMarket1), true);
        dusd.setMinterStatus(OWNER, true);
        dusd.setMinterCeiling(address(mintMarket1), CEILING_AMOUNT);
        dusd.setMinterCeiling(OWNER, type(uint256).max);

        borrowToken.mint(address(this), INITIAL_BALANCE);
        collateralToken1.mint(address(this), INITIAL_BALANCE);

        mintMarket1.setFeeRecipient(address(feeClaimer));
        borrowMarket1.setFeeRecipient(address(feeClaimer));

        feeClaimer.updateMarkets(MarketType.MINT, address(mintMarket1), true);
        feeClaimer.updateMarkets(MarketType.BORROW, address(borrowMarket1), true);
        feeClaimer.setFeeClaimer(FEE_CLAIMER, true);
        vm.stopPrank();
    }

    function test_Deployment_Valid() public {
        assertEq(feeClaimer.owner(), OWNER);
        assertEq(feeClaimer.dusd(), address(dusd));
        assertEq(feeClaimer.feeRecipient(), FEE_RECIPIENT);
        assertTrue(feeClaimer.feeClaimer(FEE_CLAIMER));
    }

    function test_RevertWhen_Deployed_WithInvalidInput() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new FeeClaimer(address(0), address(dusd), FEE_RECIPIENT);

        vm.expectRevert(IFeeClaimer.FeeClaimerInvalidInput.selector);
        new FeeClaimer(OWNER, address(0), FEE_RECIPIENT);

        vm.expectRevert(IFeeClaimer.FeeClaimerInvalidInput.selector);
        new FeeClaimer(OWNER, address(dusd), address(0));
    }

    function test_ClaimFees_OnlyOwnerOrFeeClaimer() public {
        address unauthorized = makeAddr("unauthorized");

        vm.prank(unauthorized);
        vm.expectRevert(IFeeClaimer.FeeClaimerUnauthorized.selector);
        feeClaimer.claimFees();

        vm.prank(OWNER);
        feeClaimer.claimFees();

        vm.prank(FEE_CLAIMER);
        feeClaimer.claimFees();

        _assertNothingClaimable(feeClaimer);
    }

    function test_ClaimBorrowTokenForBorrowMarket() public returns (TokenBalance[] memory) {
        uint256 withdrawableAmount = 200 ether;

        // add claimable borrow tokens for fee claimer contract
        borrowMarket1.addSupply(withdrawableAmount, 0, address(feeClaimer));

        uint256 borrowTokenBalanceBefore = borrowToken.balanceOf(address(feeClaimer));
        uint256 collateral1BalanceBefore = collateralToken1.balanceOf(address(feeClaimer));
        uint256 collateral2BalanceBefore = collateralToken2.balanceOf(address(feeClaimer));

        TokenBalance[] memory claimableTokenBalances = feeClaimer.claimableFees();

        for (uint256 i = 0; i < claimableTokenBalances.length; i++) {
            if (claimableTokenBalances[i].token == address(borrowToken)) {
                assertEq(claimableTokenBalances[i].balance, withdrawableAmount);
            } else {
                assertEq(claimableTokenBalances[i].balance, 0);
            }
        }

        vm.prank(OWNER);
        feeClaimer.claimFees();

        uint256 borrowTokenBalanceAfter = borrowToken.balanceOf(address(feeClaimer));
        uint256 collateral1BalanceAfter = collateralToken1.balanceOf(address(feeClaimer));
        uint256 collateral2BalanceAfter = collateralToken2.balanceOf(address(feeClaimer));

        assertEq(borrowTokenBalanceAfter - borrowTokenBalanceBefore, withdrawableAmount);
        assertEq(collateral1BalanceAfter, collateral1BalanceBefore);
        assertEq(collateral2BalanceAfter, collateral2BalanceBefore);

        _assertNothingClaimable(feeClaimer);

        return claimableTokenBalances;
    }

    function test_ClaimBorrowTokenForBorrowMarket_HigherUtilization() public returns (TokenBalance[] memory) {
        uint256 withdrawableAmount = 1000 ether;
        uint256 marketBalance = 100 ether; // Less than withdrawable

        borrowMarket1.addSupply(withdrawableAmount, 0, address(feeClaimer));
        borrowMarket1.addCollateral(100 * withdrawableAmount, address(this));
        borrowMarket1.borrow(withdrawableAmount - marketBalance, 0, address(this), address(this), "");

        uint256 borrowTokenBalanceBefore = borrowToken.balanceOf(address(feeClaimer));
        uint256 collateral1BalanceBefore = collateralToken1.balanceOf(address(feeClaimer));
        uint256 collateral2BalanceBefore = collateralToken2.balanceOf(address(feeClaimer));

        TokenBalance[] memory claimableTokenBalances = feeClaimer.claimableFees();

        for (uint256 i = 0; i < claimableTokenBalances.length; i++) {
            if (claimableTokenBalances[i].token == address(borrowToken)) {
                assertEq(claimableTokenBalances[i].balance, marketBalance);
            } else {
                assertEq(claimableTokenBalances[i].balance, 0);
            }
        }

        vm.prank(OWNER);
        feeClaimer.claimFees();

        uint256 borrowTokenBalanceAfter = borrowToken.balanceOf(address(feeClaimer));
        uint256 collateral1BalanceAfter = collateralToken1.balanceOf(address(feeClaimer));
        uint256 collateral2BalanceAfter = collateralToken2.balanceOf(address(feeClaimer));

        // Should claim only the market balance (100 ether)
        assertEq(borrowTokenBalanceAfter - borrowTokenBalanceBefore, marketBalance);
        assertEq(collateral1BalanceAfter, collateral1BalanceBefore);
        assertEq(collateral2BalanceAfter, collateral2BalanceBefore);

        _assertNothingClaimable(feeClaimer);

        return claimableTokenBalances;
    }

    function test_ClaimBorrowTokenForBorrowMarket_ZeroWithdrawable() public returns (TokenBalance[] memory) {
        uint256 borrowTokenBalanceBefore = borrowToken.balanceOf(address(feeClaimer));
        uint256 collateral1BalanceBefore = collateralToken1.balanceOf(address(feeClaimer));
        uint256 collateral2BalanceBefore = collateralToken2.balanceOf(address(feeClaimer));

        TokenBalance[] memory claimableTokenBalances = feeClaimer.claimableFees();

        for (uint256 i = 0; i < claimableTokenBalances.length; i++) {
            assertEq(claimableTokenBalances[i].balance, 0);
        }

        vm.prank(OWNER);
        feeClaimer.claimFees();

        uint256 borrowTokenBalanceAfter = borrowToken.balanceOf(address(feeClaimer));
        uint256 collateral1BalanceAfter = collateralToken1.balanceOf(address(feeClaimer));
        uint256 collateral2BalanceAfter = collateralToken2.balanceOf(address(feeClaimer));

        assertEq(borrowTokenBalanceAfter, borrowTokenBalanceBefore);
        assertEq(collateral1BalanceAfter, collateral1BalanceBefore);
        assertEq(collateral2BalanceAfter, collateral2BalanceBefore);

        _assertNothingClaimable(feeClaimer);

        return claimableTokenBalances;
    }

    function test_TransferFees_WorksCorrectly_For_ClaimBorrowTokenForBorrowMarket() public {
        uint256 initialSnapshotId = vm.snapshot();
        {
            TokenBalance[] memory claimableTokenBalances = test_ClaimBorrowTokenForBorrowMarket();

            uint256[] memory initialBalances = new uint256[](claimableTokenBalances.length);
            for (uint256 i = 0; i < claimableTokenBalances.length; i++) {
                initialBalances[i] = IERC20(claimableTokenBalances[i].token).balanceOf(FEE_RECIPIENT);
            }

            vm.prank(OWNER);
            feeClaimer.transferFees();

            for (uint256 i = 0; i < claimableTokenBalances.length; i++) {
                assertEq(
                    IERC20(claimableTokenBalances[i].token).balanceOf(FEE_RECIPIENT) - initialBalances[i],
                    claimableTokenBalances[i].balance
                );
            }

            _assertNothingClaimable(feeClaimer);
        }

        vm.revertTo(initialSnapshotId);

        {
            TokenBalance[] memory claimableTokenBalances = test_ClaimBorrowTokenForBorrowMarket_HigherUtilization();

            uint256[] memory initialBalances = new uint256[](claimableTokenBalances.length);
            for (uint256 i = 0; i < claimableTokenBalances.length; i++) {
                initialBalances[i] = IERC20(claimableTokenBalances[i].token).balanceOf(FEE_RECIPIENT);
            }

            vm.prank(OWNER);
            feeClaimer.transferFees();

            for (uint256 i = 0; i < claimableTokenBalances.length; i++) {
                assertEq(
                    IERC20(claimableTokenBalances[i].token).balanceOf(FEE_RECIPIENT) - initialBalances[i],
                    claimableTokenBalances[i].balance
                );
            }

            _assertNothingClaimable(feeClaimer);
        }

        vm.revertTo(initialSnapshotId);

        {
            TokenBalance[] memory claimableTokenBalances = test_ClaimBorrowTokenForBorrowMarket_ZeroWithdrawable();

            uint256[] memory initialBalances = new uint256[](claimableTokenBalances.length);
            for (uint256 i = 0; i < claimableTokenBalances.length; i++) {
                initialBalances[i] = IERC20(claimableTokenBalances[i].token).balanceOf(FEE_RECIPIENT);
            }

            vm.prank(OWNER);
            feeClaimer.transferFees();

            for (uint256 i = 0; i < claimableTokenBalances.length; i++) {
                assertEq(
                    IERC20(claimableTokenBalances[i].token).balanceOf(FEE_RECIPIENT) - initialBalances[i],
                    claimableTokenBalances[i].balance
                );
            }

            _assertNothingClaimable(feeClaimer);
        }
    }

    function test_ClaimBorrowTokenForMintMarket() public returns (TokenBalance[] memory) {
        uint256 withdrawableAmount = 200 ether;
        uint256 mintedAmount = 300 ether;
        uint256 ceilingAmount = 1000 ether;

        mintMarket1.addClaimableFeesAssets(withdrawableAmount);

        // mintable amount is ceilingAmount - mintedAmount i.e. 700 ether
        // so, feeClaimer can claim full withdrawable amount i.e. 200 ether

        vm.prank(OWNER);
        dusd.setMinterCeiling(address(mintMarket1), ceilingAmount);

        uint256 borrowTokenBalanceBefore = borrowToken.balanceOf(address(feeClaimer));
        uint256 collateral1BalanceBefore = collateralToken1.balanceOf(address(feeClaimer));
        uint256 collateral2BalanceBefore = collateralToken2.balanceOf(address(feeClaimer));

        TokenBalance[] memory claimableTokenBalances = feeClaimer.claimableFees();

        for (uint256 i = 0; i < claimableTokenBalances.length; i++) {
            if (claimableTokenBalances[i].token == address(borrowToken)) {
                assertEq(claimableTokenBalances[i].balance, withdrawableAmount);
            } else {
                assertEq(claimableTokenBalances[i].balance, 0);
            }
        }

        vm.prank(OWNER);
        feeClaimer.claimFees();

        uint256 borrowTokenBalanceAfter = borrowToken.balanceOf(address(feeClaimer));
        uint256 collateral1BalanceAfter = collateralToken1.balanceOf(address(feeClaimer));
        uint256 collateral2BalanceAfter = collateralToken2.balanceOf(address(feeClaimer));

        assertEq(borrowTokenBalanceAfter - borrowTokenBalanceBefore, withdrawableAmount);
        assertEq(collateral1BalanceAfter, collateral1BalanceBefore);
        assertEq(collateral2BalanceAfter, collateral2BalanceBefore);

        _assertNothingClaimable(feeClaimer);

        return claimableTokenBalances;
    }

    function test_ClaimBorrowTokenForMintMarket_WithdrawableLessThanMintable() public returns (TokenBalance[] memory) {
        // Set withdrawable greater than mintable
        uint256 withdrawableAmount = 1000 ether;
        uint256 mintedAmount = 800 ether;
        uint256 ceilingAmount = 1000 ether;
        uint256 mintableAmount = ceilingAmount - mintedAmount; // 200 ether

        // due to ceiling for minting in DUSD, feeClaimer can claim only mintableAmount i.e. 200 ether
        mintMarket1.addClaimableFeesAssets(withdrawableAmount);
        vm.prank(OWNER);
        dusd.setMinterCeiling(address(mintMarket1), ceilingAmount - mintedAmount);

        uint256 borrowTokenBalanceBefore = borrowToken.balanceOf(address(feeClaimer));
        uint256 collateral1BalanceBefore = collateralToken1.balanceOf(address(feeClaimer));
        uint256 collateral2BalanceBefore = collateralToken2.balanceOf(address(feeClaimer));

        TokenBalance[] memory claimableTokenBalances = feeClaimer.claimableFees();

        for (uint256 i = 0; i < claimableTokenBalances.length; i++) {
            if (claimableTokenBalances[i].token == address(borrowToken)) {
                assertEq(claimableTokenBalances[i].balance, mintableAmount);
            } else {
                assertEq(claimableTokenBalances[i].balance, 0);
            }
        }

        vm.prank(OWNER);
        feeClaimer.claimFees();

        uint256 borrowTokenBalanceAfter = borrowToken.balanceOf(address(feeClaimer));
        uint256 collateral1BalanceAfter = collateralToken1.balanceOf(address(feeClaimer));
        uint256 collateral2BalanceAfter = collateralToken2.balanceOf(address(feeClaimer));

        // Should claim only the mintable amount (200 ether)
        assertEq(borrowTokenBalanceAfter - borrowTokenBalanceBefore, mintableAmount);
        assertEq(collateral1BalanceAfter, collateral1BalanceBefore);
        assertEq(collateral2BalanceAfter, collateral2BalanceBefore);

        _assertNothingClaimable(feeClaimer);

        return claimableTokenBalances;
    }

    function test_ClaimBorrowTokenForMintMarket_ZeroMintable() public returns (TokenBalance[] memory) {
        // Set minted equal to ceiling (zero mintable)
        uint256 withdrawableAmount = 100 ether;
        uint256 mintedAmount = 1000 ether;
        uint256 ceilingAmount = 1000 ether;

        mintMarket1.addClaimableFeesAssets(withdrawableAmount);
        vm.prank(OWNER);
        dusd.setMinterCeiling(address(mintMarket1), 0);

        uint256 borrowTokenBalanceBefore = borrowToken.balanceOf(address(feeClaimer));
        uint256 collateral1BalanceBefore = collateralToken1.balanceOf(address(feeClaimer));
        uint256 collateral2BalanceBefore = collateralToken2.balanceOf(address(feeClaimer));

        TokenBalance[] memory claimableTokenBalances = feeClaimer.claimableFees();

        for (uint256 i = 0; i < claimableTokenBalances.length; i++) {
            assertEq(claimableTokenBalances[i].balance, 0);
        }

        vm.prank(OWNER);
        feeClaimer.claimFees();

        uint256 borrowTokenBalanceAfter = borrowToken.balanceOf(address(feeClaimer));
        uint256 collateral1BalanceAfter = collateralToken1.balanceOf(address(feeClaimer));
        uint256 collateral2BalanceAfter = collateralToken2.balanceOf(address(feeClaimer));

        // Should claim nothing
        assertEq(borrowTokenBalanceAfter, borrowTokenBalanceBefore);
        assertEq(collateral1BalanceAfter, collateral1BalanceBefore);
        assertEq(collateral2BalanceAfter, collateral2BalanceBefore);

        _assertNothingClaimable(feeClaimer);

        return claimableTokenBalances;
    }

    function test_TransferFees_WorksCorrectly_For_ClaimBorrowTokenForMintMarket() public {
        uint256 initialSnapshotId = vm.snapshot();
        {
            TokenBalance[] memory claimableTokenBalances = test_ClaimBorrowTokenForMintMarket();

            uint256[] memory initialBalances = new uint256[](claimableTokenBalances.length);
            for (uint256 i = 0; i < claimableTokenBalances.length; i++) {
                initialBalances[i] = IERC20(claimableTokenBalances[i].token).balanceOf(FEE_RECIPIENT);
            }

            vm.prank(OWNER);
            feeClaimer.transferFees();

            for (uint256 i = 0; i < claimableTokenBalances.length; i++) {
                assertEq(
                    IERC20(claimableTokenBalances[i].token).balanceOf(FEE_RECIPIENT) - initialBalances[i],
                    claimableTokenBalances[i].balance
                );
            }
        }
        vm.revertTo(initialSnapshotId);

        {
            TokenBalance[] memory claimableTokenBalances =
                test_ClaimBorrowTokenForMintMarket_WithdrawableLessThanMintable();

            uint256[] memory initialBalances = new uint256[](claimableTokenBalances.length);
            for (uint256 i = 0; i < claimableTokenBalances.length; i++) {
                initialBalances[i] = IERC20(claimableTokenBalances[i].token).balanceOf(FEE_RECIPIENT);
            }

            vm.prank(OWNER);
            feeClaimer.transferFees();

            for (uint256 i = 0; i < claimableTokenBalances.length; i++) {
                assertEq(
                    IERC20(claimableTokenBalances[i].token).balanceOf(FEE_RECIPIENT) - initialBalances[i],
                    claimableTokenBalances[i].balance
                );
            }
        }
        vm.revertTo(initialSnapshotId);

        {
            TokenBalance[] memory claimableTokenBalances = test_ClaimBorrowTokenForMintMarket_ZeroMintable();

            uint256[] memory initialBalances = new uint256[](claimableTokenBalances.length);
            for (uint256 i = 0; i < claimableTokenBalances.length; i++) {
                initialBalances[i] = IERC20(claimableTokenBalances[i].token).balanceOf(FEE_RECIPIENT);
            }

            vm.prank(OWNER);
            feeClaimer.transferFees();

            for (uint256 i = 0; i < claimableTokenBalances.length; i++) {
                assertEq(
                    IERC20(claimableTokenBalances[i].token).balanceOf(FEE_RECIPIENT) - initialBalances[i],
                    claimableTokenBalances[i].balance
                );
            }
        }
    }

    function test_ClaimCollateral_AllMarkets() public returns (TokenBalance[] memory) {
        uint256 collateralAmount = 1000 ether;
        mintMarket1.addCollateral(collateralAmount, address(feeClaimer));
        borrowMarket1.addCollateral(collateralAmount, address(feeClaimer));

        TokenBalance[] memory claimableTokenBalances = feeClaimer.claimableFees();

        for (uint256 i = 0; i < claimableTokenBalances.length; i++) {
            if (claimableTokenBalances[i].token == address(collateralToken1)) {
                assertEq(claimableTokenBalances[i].balance, 2 * collateralAmount);
            } else {
                assertEq(claimableTokenBalances[i].balance, 0);
            }
        }

        uint256 borrowTokenBalanceBefore = borrowToken.balanceOf(address(feeClaimer));
        uint256 collateral1BalanceBefore = collateralToken1.balanceOf(address(feeClaimer));
        uint256 collateral2BalanceBefore = collateralToken2.balanceOf(address(feeClaimer));

        vm.prank(OWNER);
        feeClaimer.claimFees();

        uint256 borrowTokenBalanceAfter = borrowToken.balanceOf(address(feeClaimer));
        uint256 collateral1BalanceAfter = collateralToken1.balanceOf(address(feeClaimer));
        uint256 collateral2BalanceAfter = collateralToken2.balanceOf(address(feeClaimer));

        assertEq(borrowTokenBalanceAfter, borrowTokenBalanceBefore);
        assertEq(collateral1BalanceAfter - collateral1BalanceBefore, 2 * collateralAmount);
        assertEq(collateral2BalanceAfter, collateral2BalanceBefore);

        _assertNothingClaimable(feeClaimer);

        return claimableTokenBalances;
    }

    function test_ClaimCollateral_NothingToClaim() public returns (TokenBalance[] memory) {
        uint256 borrowTokenBalanceBefore = borrowToken.balanceOf(address(feeClaimer));
        uint256 collateral1BalanceBefore = collateralToken1.balanceOf(address(feeClaimer));
        uint256 collateral2BalanceBefore = collateralToken2.balanceOf(address(feeClaimer));

        TokenBalance[] memory claimableTokenBalances = feeClaimer.claimableFees();

        for (uint256 i = 0; i < claimableTokenBalances.length; i++) {
            assertEq(claimableTokenBalances[i].balance, 0);
        }

        vm.prank(OWNER);
        feeClaimer.claimFees();

        // Should claim nothing
        uint256 borrowTokenBalanceAfter = borrowToken.balanceOf(address(feeClaimer));
        uint256 collateral1BalanceAfter = collateralToken1.balanceOf(address(feeClaimer));
        uint256 collateral2BalanceAfter = collateralToken2.balanceOf(address(feeClaimer));

        assertEq(borrowTokenBalanceAfter, borrowTokenBalanceBefore);
        assertEq(collateral1BalanceAfter, collateral1BalanceBefore);
        assertEq(collateral2BalanceAfter, collateral2BalanceBefore);

        _assertNothingClaimable(feeClaimer);

        return claimableTokenBalances;
    }

    function test_TransferFees_WorksCorrectly_For_ClaimCollateral() public {
        uint256 initialSnapshotId = vm.snapshot();
        {
            TokenBalance[] memory claimableTokenBalances = test_ClaimCollateral_AllMarkets();

            uint256[] memory initialBalances = new uint256[](claimableTokenBalances.length);
            for (uint256 i = 0; i < claimableTokenBalances.length; i++) {
                initialBalances[i] = IERC20(claimableTokenBalances[i].token).balanceOf(FEE_RECIPIENT);
            }

            vm.prank(OWNER);
            feeClaimer.transferFees();

            for (uint256 i = 0; i < claimableTokenBalances.length; i++) {
                assertEq(
                    IERC20(claimableTokenBalances[i].token).balanceOf(FEE_RECIPIENT) - initialBalances[i],
                    claimableTokenBalances[i].balance
                );
            }
        }
        vm.revertTo(initialSnapshotId);

        {
            TokenBalance[] memory claimableTokenBalances = test_ClaimCollateral_NothingToClaim();

            uint256[] memory initialBalances = new uint256[](claimableTokenBalances.length);
            for (uint256 i = 0; i < claimableTokenBalances.length; i++) {
                initialBalances[i] = IERC20(claimableTokenBalances[i].token).balanceOf(FEE_RECIPIENT);
            }

            vm.prank(OWNER);
            feeClaimer.transferFees();

            for (uint256 i = 0; i < claimableTokenBalances.length; i++) {
                assertEq(
                    IERC20(claimableTokenBalances[i].token).balanceOf(FEE_RECIPIENT) - initialBalances[i],
                    claimableTokenBalances[i].balance
                );
            }
        }
    }

    function test_UpdateMarkets_AddMintMarket() public {
        // only 1 mint market is active
        vm.expectRevert();
        feeClaimer.activeMintMarkets(1);

        vm.startPrank(FEE_RECIPIENT);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, FEE_RECIPIENT));
        feeClaimer.updateMarkets(MarketType.MINT, address(mintMarket2), true);
        vm.stopPrank();

        vm.expectEmit(true, true, true, true);
        emit IFeeClaimer.UpdateMarkets(address(mintMarket2), MarketType.MINT, true);

        vm.prank(OWNER);
        feeClaimer.updateMarkets(MarketType.MINT, address(mintMarket2), true);

        assertEq(feeClaimer.activeMintMarkets(1), address(mintMarket2));
    }

    function test_UpdateMarkets_AddBorrowMarket() public {
        vm.expectRevert();
        feeClaimer.activeBorrowMarkets(1);

        vm.startPrank(FEE_RECIPIENT);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, FEE_RECIPIENT));
        feeClaimer.updateMarkets(MarketType.BORROW, address(borrowMarket2), true);
        vm.stopPrank();

        vm.expectEmit(true, true, true, true);
        emit IFeeClaimer.UpdateMarkets(address(borrowMarket2), MarketType.BORROW, true);

        vm.prank(OWNER);
        feeClaimer.updateMarkets(MarketType.BORROW, address(borrowMarket2), true);

        assertEq(feeClaimer.activeBorrowMarkets(1), address(borrowMarket2));
    }

    function test_UpdateMarkets_RemoveMintMarket() public {
        vm.startPrank(FEE_RECIPIENT);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, FEE_RECIPIENT));
        feeClaimer.updateMarkets(MarketType.MINT, address(mintMarket1), false);
        vm.stopPrank();

        assertEq(feeClaimer.activeMintMarkets(0), address(mintMarket1));

        vm.prank(OWNER);
        feeClaimer.updateMarkets(MarketType.MINT, address(mintMarket1), false);

        // should not have any active mint markets
        vm.expectRevert();
        feeClaimer.activeMintMarkets(0);
    }

    function test_UpdateMarkets_RemoveBorrowMarket() public {
        vm.startPrank(FEE_RECIPIENT);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, FEE_RECIPIENT));
        feeClaimer.updateMarkets(MarketType.BORROW, address(borrowMarket1), false);
        vm.stopPrank();

        assertEq(feeClaimer.activeBorrowMarkets(0), address(borrowMarket1));

        vm.prank(OWNER);
        feeClaimer.updateMarkets(MarketType.BORROW, address(borrowMarket1), false);

        // should not have any active borrow markets
        vm.expectRevert();
        feeClaimer.activeBorrowMarkets(0);
    }

    function test_UpdateMarkets_AddDuplicateMarket() public {
        vm.startPrank(OWNER);
        vm.expectRevert(IFeeClaimer.FeeClaimerInvalidInput.selector);
        feeClaimer.updateMarkets(MarketType.MINT, address(mintMarket1), true);

        vm.expectRevert(IFeeClaimer.FeeClaimerInvalidInput.selector);
        feeClaimer.updateMarkets(MarketType.BORROW, address(borrowMarket1), true);

        vm.stopPrank();
    }

    function test_UpdateMarkets_RemoveNonExistentMarket() public {
        address nonExistentMarket = makeAddr("nonExistentMarket");
        vm.startPrank(OWNER);
        vm.expectRevert(IFeeClaimer.FeeClaimerInvalidInput.selector);
        feeClaimer.updateMarkets(MarketType.MINT, address(nonExistentMarket), false);

        vm.expectRevert(IFeeClaimer.FeeClaimerInvalidInput.selector);
        feeClaimer.updateMarkets(MarketType.BORROW, address(nonExistentMarket), false);

        vm.stopPrank();
    }

    function test_TransferFees_OnlyOwnerOrFeeClaimer() public {
        address unauthorized = makeAddr("unauthorized");
        vm.prank(unauthorized);
        vm.expectRevert(IFeeClaimer.FeeClaimerUnauthorized.selector);
        feeClaimer.transferFees();
        vm.stopPrank();

        vm.prank(OWNER);
        feeClaimer.transferFees();

        vm.prank(FEE_CLAIMER);
        feeClaimer.transferFees();
    }

    function test_SetFeeClaimer_OnlyOwner() public {
        address newClaimer = makeAddr("newClaimer");

        vm.prank(newClaimer);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, newClaimer));
        feeClaimer.setFeeClaimer(newClaimer, true);

        vm.prank(FEE_RECIPIENT);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, FEE_RECIPIENT));
        feeClaimer.setFeeClaimer(newClaimer, true);

        vm.prank(OWNER);
        feeClaimer.setFeeClaimer(newClaimer, true);

        assertTrue(feeClaimer.feeClaimer(newClaimer));
    }

    function test_SetFeeRecipient_OnlyOwner() public {
        address newRecipient = makeAddr("newRecipient");

        vm.prank(newRecipient);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, newRecipient));
        feeClaimer.setFeeRecipient(newRecipient);

        vm.prank(FEE_RECIPIENT);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, FEE_RECIPIENT));
        feeClaimer.setFeeRecipient(newRecipient);

        vm.prank(OWNER);
        feeClaimer.setFeeRecipient(newRecipient);

        assertEq(feeClaimer.feeRecipient(), newRecipient);
    }

    function test_SetFeeRecipient_InvalidAddress() public {
        vm.prank(OWNER);
        vm.expectRevert(IFeeClaimer.FeeClaimerInvalidInput.selector);
        feeClaimer.setFeeRecipient(address(0));
    }

    function test_SetDusd_OnlyOwner() public {
        DUSD newDusd = new DUSD(address(endpoints[1]), OWNER);

        address unauthorized = makeAddr("unauthorized");

        vm.prank(unauthorized);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, unauthorized));
        feeClaimer.setDusd(address(newDusd));

        vm.prank(FEE_RECIPIENT);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, FEE_RECIPIENT));
        feeClaimer.setDusd(address(newDusd));

        vm.prank(OWNER);
        feeClaimer.setDusd(address(newDusd));

        assertEq(feeClaimer.dusd(), address(newDusd));
    }

    function test_SetDusd_InvalidAddress() public {
        vm.prank(OWNER);
        vm.expectRevert(IFeeClaimer.FeeClaimerInvalidInput.selector);
        feeClaimer.setDusd(address(0));
    }

    function test_ClaimFees_ManyMarkets() public {
        for (uint256 i = 0; i < 10; i++) {
            address irm = address(new FixedRateIrm(0.04 ether / uint256(365 days), address(this)));
            address oracle = address(new OracleMock());
            MockMintMarket newMarket = MockMintMarketDeployer.deployMarket(
                address(borrowToken),
                address(collateralToken1),
                address(irm),
                OWNER,
                address(oracle),
                0.8 ether,
                0.01 ether,
                FEE_RECIPIENT,
                liquidationConfig
            );
            OracleMock(oracle).setPrice(LENDING_ORACLE_PRICE_PRECISION);

            newMarket.addClaimableFeesAssets(CLAIMABLE_FEES);
            vm.startPrank(OWNER);
            dusd.setMinterStatus(address(newMarket), true);
            dusd.setMinterCeiling(address(newMarket), CLAIMABLE_FEES);
            vm.stopPrank();

            borrowToken.approve(address(newMarket), type(uint256).max);
            deal(address(borrowToken), address(this), CLAIMABLE_FEES);
            newMarket.addSupply(CLAIMABLE_FEES, 0, address(feeClaimer));

            vm.startPrank(OWNER);
            feeClaimer.updateMarkets(MarketType.MINT, address(newMarket), true);
            newMarket.setFeeRecipient(address(feeClaimer));
            vm.stopPrank();
        }

        for (uint256 i = 0; i < 10; i++) {
            address irm = address(new FixedRateIrm(0.04 ether / uint256(365 days), address(this)));
            address oracle = address(new OracleMock());
            OracleMock(oracle).setPrice(LENDING_ORACLE_PRICE_PRECISION);
            MockMarket newBorrowMarket = MockMarketDeployer.deployMarket(
                address(borrowToken),
                address(collateralToken1),
                irm,
                OWNER,
                oracle,
                0.8 ether,
                0.01 ether,
                FEE_RECIPIENT,
                liquidationConfig
            );

            borrowToken.approve(address(newBorrowMarket), type(uint256).max);
            deal(address(borrowToken), address(this), CLAIMABLE_FEES);
            newBorrowMarket.addSupply(CLAIMABLE_FEES, 0, address(feeClaimer));

            vm.startPrank(OWNER);
            feeClaimer.updateMarkets(MarketType.BORROW, address(newBorrowMarket), true);
            newBorrowMarket.setFeeRecipient(address(feeClaimer));
            vm.stopPrank();
        }

        uint256 borrowTokenBalanceBefore = borrowToken.balanceOf(address(feeClaimer));
        uint256 collateral1BalanceBefore = collateralToken1.balanceOf(address(feeClaimer));

        TokenBalance[] memory claimableTokenBalances = feeClaimer.claimableFees();
        for (uint256 i = 0; i < claimableTokenBalances.length; i++) {
            if (claimableTokenBalances[i].token == address(borrowToken)) {
                assertEq(claimableTokenBalances[i].balance, 20 * CLAIMABLE_FEES);
            } else {
                assertEq(claimableTokenBalances[i].balance, 0);
            }
        }

        vm.prank(OWNER);
        feeClaimer.claimFees();

        uint256 borrowTokenBalanceAfter = borrowToken.balanceOf(address(feeClaimer));
        uint256 collateral1BalanceAfter = collateralToken1.balanceOf(address(feeClaimer));
        assertEq(borrowTokenBalanceAfter - borrowTokenBalanceBefore, 20 * CLAIMABLE_FEES);
        assertEq(collateral1BalanceAfter - collateral1BalanceBefore, 0);

        _assertNothingClaimable(feeClaimer);
    }

    function _assertNothingClaimable(FeeClaimer feeClaimer) internal {
        TokenBalance[] memory claimableTokenBalances = feeClaimer.claimableFees();
        for (uint256 i = 0; i < claimableTokenBalances.length; i++) {
            assertEq(claimableTokenBalances[i].balance, 0);
        }
    }
}
