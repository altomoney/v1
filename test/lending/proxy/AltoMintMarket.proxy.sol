// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "@alto-test/helpers/ERC20Mock.sol";
import {ERC20MockMintable} from "@alto-test/helpers/ERC20MockMintable.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {OracleMock} from "@alto/oracles/mocks/OracleMock.sol";
import {LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {MarketDeployer} from "@alto-test/helpers/MarketDeployer.sol";
import {MintMarketInitParams, BaseMarketInitParams, Balance, Position} from "@alto/lending/interfaces/IMarket.sol";
import {
    IDcfDlbPriorityLiquidationEngine,
    LiquidationConfiguration
} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {PAUSE_TYPE, FROZEN_TYPE} from "@alto/utils/Constants.sol";
import {IMarket} from "@alto/lending/interfaces/IMarket.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {DlbDcfPriorityLiquidationEngine} from "@alto/lending/liquidation/DlbDcfPriorityLiquidationEngine.sol";
import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";

contract AltoMintMarketProxyTest is Test {
    IMarket public market;
    ERC20MockMintable public borrowToken;
    ERC20Mock public collateralToken;

    address internal immutable USER = makeAddr("User");
    address internal immutable USER2 = makeAddr("User2");
    address internal immutable OWNER = makeAddr("Owner");
    address internal immutable FEE_RECIPIENT = makeAddr("FeeRecipient");

    function setUp() public {
        borrowToken = new ERC20MockMintable("Borrow Token", "BTKN");
        collateralToken = new ERC20Mock("Collateral Token", "CTKN");

        address irm = address(new FixedRateIrm(0.04 ether / uint256(365 days), OWNER));
        address oracle = address(new OracleMock());
        OracleMock(oracle).setPrice(LENDING_ORACLE_PRICE_PRECISION);

        LiquidationConfiguration memory liquidationConfig = LiquidationConfiguration({
            maxLiquidationLtv: 0.8 ether,
            dynamicBonusFeeStart: 0.03 ether,
            ltvForCompleteLiquidation: 0.9 ether,
            dynamicBonusFeeDecaySteepness: 5 ether,
            liquidationBaseFee: 0.05 ether,
            minPenaltyPercentage: 0.01 ether,
            protocolFeePercentage: 0.075 ether,
            isEnabledPriorityLiquidation: true,
            disablePriorityLiquidationAbovePositionLtv: type(uint256).max,
            priorityLiquidationGracePeriod: 5 minutes,
            taggerLiquidationGracePeriod: 2 minutes,
            liquidationWindowTag: 3 days
        });

        address liquidationEngine = address(new DlbDcfPriorityLiquidationEngine(OWNER));

        BaseMarketInitParams memory baseMarketInitParams = BaseMarketInitParams({
            borrowToken: address(borrowToken),
            collateralToken: address(collateralToken),
            irm: address(irm),
            owner: OWNER,
            oracle: address(oracle),
            maxLtv: 0.75 ether,
            feeRecipient: FEE_RECIPIENT,
            liquidationEngine: liquidationEngine
        });

        MintMarketInitParams memory mintMarketInitParams = MintMarketInitParams({
            baseMarketInitParams: baseMarketInitParams,
            initialBorrowOpeningFee: 0,
            debtCeiling: 1000 ether
        });

        market = IMarket(MarketDeployer.deployMintMarket(mintMarketInitParams));

        vm.startPrank(OWNER);
        IDcfDlbPriorityLiquidationEngine(liquidationEngine).setLiquidationConfiguration(liquidationConfig);
        market.setPauser(OWNER, PAUSE_TYPE, true);
        market.setPauser(OWNER, FROZEN_TYPE, true);
        vm.stopPrank();

        // ERC20MockMintable has open mint/burn - no role granting needed

        deal(address(collateralToken), address(this), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);

        vm.prank(USER);
        market.setAuthorization(address(this), true);

        vm.prank(USER2);
        market.setAuthorization(address(this), true);

        market.addCollateral(10 ether, USER);
        market.borrow(1 ether, 0, USER, USER, hex"");
    }

    struct MintMarketData {
        address borrowToken;
        address collateralToken;
        Balance totalSupply;
        Balance totalBorrowed;
        Position position;
        address irm;
        address owner;
        address oracle;
        uint256 maxLtv;
        uint256 borrowOpeningFee;
        address feeRecipient;
        uint128 claimableFeesAssets;
    }

    function _getAllMarketData() internal view returns (MintMarketData memory) {
        return MintMarketData({
            borrowToken: market.borrowToken(),
            collateralToken: market.collateralToken(),
            totalSupply: market.totalSupply(),
            totalBorrowed: market.totalBorrowed(),
            position: market.position(USER),
            irm: market.irm(),
            owner: Ownable(address(market)).owner(),
            oracle: market.oracle(),
            maxLtv: market.maxLtv(),
            borrowOpeningFee: market.borrowOpeningFee(),
            feeRecipient: market.feeRecipient(),
            claimableFeesAssets: AltoMintMarket(address(market)).claimableFeesAssets()
        });
    }

    function test_upgradeWithInitializeV2() public {
        vm.warp(block.timestamp + 1 days);
        market.accrueInterest();

        MintMarketData memory dataBefore = _getAllMarketData();

        assertNotEq(dataBefore.totalSupply.assets, 0);
        assertNotEq(dataBefore.totalBorrowed.assets, 0);
        assertNotEq(dataBefore.totalBorrowed.shares, 0);
        assertNotEq(dataBefore.position.borrowShares, 0);
        assertNotEq(dataBefore.position.collateralAssets, 0);

        uint128 badDebtValue = 42 ether;

        vm.startPrank(OWNER);
        UnsafeUpgrades.upgradeProxy(
            address(market),
            address(new AltoMintMarket()),
            abi.encodeCall(AltoMintMarket.initializeV2, (badDebtValue))
        );
        vm.stopPrank();

        MintMarketData memory dataAfter = _getAllMarketData();

        assertEq(dataBefore.borrowToken, dataAfter.borrowToken);
        assertEq(dataBefore.collateralToken, dataAfter.collateralToken);
        assertEq(dataBefore.totalSupply.assets, dataAfter.totalSupply.assets);
        assertEq(dataBefore.totalSupply.shares, dataAfter.totalSupply.shares);
        assertEq(dataBefore.totalBorrowed.assets, dataAfter.totalBorrowed.assets);
        assertEq(dataBefore.totalBorrowed.shares, dataAfter.totalBorrowed.shares);
        assertEq(dataBefore.position.supplyShares, dataAfter.position.supplyShares);
        assertEq(dataBefore.position.borrowShares, dataAfter.position.borrowShares);
        assertEq(dataBefore.position.collateralAssets, dataAfter.position.collateralAssets);
        assertEq(dataBefore.irm, dataAfter.irm);
        assertEq(dataBefore.owner, dataAfter.owner);
        assertEq(dataBefore.oracle, dataAfter.oracle);
        assertEq(dataBefore.maxLtv, dataAfter.maxLtv);
        assertEq(dataBefore.borrowOpeningFee, dataAfter.borrowOpeningFee);
        assertEq(dataBefore.feeRecipient, dataAfter.feeRecipient);
        assertEq(dataBefore.claimableFeesAssets, dataAfter.claimableFeesAssets);

        assertEq(AltoMintMarket(address(market)).badDebtAssets(), badDebtValue);
    }

    function test_upgradeWithZeroBadDebt() public {
        vm.startPrank(OWNER);
        UnsafeUpgrades.upgradeProxy(
            address(market), address(new AltoMintMarket()), abi.encodeCall(AltoMintMarket.initializeV2, (0))
        );
        vm.stopPrank();

        assertEq(AltoMintMarket(address(market)).badDebtAssets(), 0);
    }

    function test_postUpgrade_claimInterestPermissionless() public {
        vm.warp(block.timestamp + 1 days);
        market.accrueInterest();

        vm.startPrank(OWNER);
        UnsafeUpgrades.upgradeProxy(
            address(market), address(new AltoMintMarket()), abi.encodeCall(AltoMintMarket.initializeV2, (0))
        );
        vm.stopPrank();

        uint128 claimable = AltoMintMarket(address(market)).claimableFeesAssets();
        assertGt(claimable, 0, "should have claimable fees");

        address randomUser = makeAddr("random");
        vm.prank(randomUser);
        uint256 claimed = AltoMintMarket(address(market)).claimInterest(0);
        assertEq(claimed, claimable);
    }

    function test_postUpgrade_borrowRespectsBadDebt() public {
        vm.startPrank(OWNER);
        UnsafeUpgrades.upgradeProxy(
            address(market),
            address(new AltoMintMarket()),
            abi.encodeCall(AltoMintMarket.initializeV2, (uint128(999 ether)))
        );
        vm.stopPrank();

        market.addCollateral(100 ether, USER2);

        vm.expectRevert();
        market.borrow(1 ether, 0, USER2, USER2, hex"");
    }

    function test_postUpgrade_operationsStillWork() public {
        vm.startPrank(OWNER);
        UnsafeUpgrades.upgradeProxy(
            address(market), address(new AltoMintMarket()), abi.encodeCall(AltoMintMarket.initializeV2, (0))
        );
        vm.stopPrank();

        // borrow
        market.addCollateral(10 ether, USER2);
        market.borrow(1 ether, 0, USER2, USER2, hex"");

        // warp and accrue
        vm.warp(block.timestamp + 1 days);
        market.accrueInterest();

        // repay (should auto-claim interest)
        borrowToken.mint(address(this), 2 ether);
        borrowToken.approve(address(market), 2 ether);
        market.repay(0, 1, USER2);
    }

    function test_upgradeRevertWhenNotOwner() public {
        address newImpl = address(new AltoMintMarket());
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        AltoMintMarket(address(market)).upgradeToAndCall(
            newImpl, abi.encodeCall(AltoMintMarket.initializeV2, (0))
        );
    }

    function test_initializeV2CannotBeCalledTwice() public {
        vm.startPrank(OWNER);
        UnsafeUpgrades.upgradeProxy(
            address(market), address(new AltoMintMarket()), abi.encodeCall(AltoMintMarket.initializeV2, (100))
        );
        vm.stopPrank();

        vm.prank(OWNER);
        vm.expectRevert();
        AltoMintMarket(address(market)).initializeV2(200);
    }
}
