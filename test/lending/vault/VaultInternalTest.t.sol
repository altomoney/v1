// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./helpers/BaseTest.sol";
import {AltoVaultMock} from "../../helpers/AltoVaultMock.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";
import {UtilsLib} from "@bundler3/lib/morpho-blue/src/libraries/UtilsLib.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract VaultInternalTest is BaseTest {
    using Math for uint256;
    using AltoBalancesLib for address;
    using AssetShareConversionMath for uint256;
    using UtilsLib for uint256;
    using FixedPointMath for uint256;

    AltoVaultMock internal vaultMock;

    function setUp() public virtual override {
        super.setUp();

        vaultMock = new AltoVaultMock(OWNER, 1 days, address(loanToken), "Alto Vault", "AV", address(marketRegistry));

        vm.startPrank(OWNER);
        vaultMock.setCurator(CURATOR);
        vaultMock.setIsAllocator(ALLOCATOR, true);
        vm.stopPrank();

        vm.startPrank(SUPPLIER);
        loanToken.approve(address(vaultMock), type(uint256).max);
        collateralToken.approve(address(vaultMock), type(uint256).max);
        vm.stopPrank();
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testSetCapMaxQueueLengthExcedeed() public {
        for (uint256 i; i < NB_MARKETS - 1; ++i) {
            vaultMock.mockSetCap(allMarkets[i], CAP);
        }

        vm.expectRevert(IAltoVaultErrors.MaxQueueLengthExceeded.selector);
        vaultMock.mockSetCap(allMarkets[NB_MARKETS - 1], CAP);
    }

    function testSimulateWithdraw(uint256 suppliedAmount, uint256 borrowedAmount, uint256 assets) public {
        suppliedAmount = bound(suppliedAmount, MIN_TEST_ASSETS, MAX_TEST_ASSETS);
        borrowedAmount = bound(borrowedAmount, MIN_TEST_ASSETS, suppliedAmount);

        vaultMock.mockSetCap(allMarkets[0], CAP);

        address[] memory supplyQueue = new address[](1);
        supplyQueue[0] = allMarkets[0];
        vaultMock.mockSetSupplyQueue(supplyQueue);

        loanToken.setBalance(SUPPLIER, suppliedAmount);
        vm.prank(SUPPLIER);
        vaultMock.deposit(suppliedAmount, SUPPLIER);

        uint256 collateral = suppliedAmount.divideWithPrecisionUp(allMarketsLltvs[0]);
        collateralToken.setBalance(BORROWER, collateral);

        vm.startPrank(BORROWER);
        IMarket(allMarkets[0]).addCollateral(collateral, BORROWER);
        IMarket(allMarkets[0]).borrow(borrowedAmount, 0, BORROWER, BORROWER, hex"");
        vm.stopPrank();

        uint256 remaining = vaultMock.mockSimulateWithdraw(assets);

        uint256 expectedWithdrawable = allMarkets[0].expectedSupplyAssets(address(vaultMock)) - borrowedAmount;
        uint256 expectedRemaining = assets.zeroFloorSub(expectedWithdrawable);

        assertEq(remaining, expectedRemaining, "remaining");
    }
}
