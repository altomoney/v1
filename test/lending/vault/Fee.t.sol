pragma solidity ^0.8.0;

import "./helpers/IntegrationTest.sol";

uint256 constant FEE = 0.2 ether; // 20%

contract FeeTest is IntegrationTest {
    using Math for uint256;
    using FixedPointMath for uint256;

    IERC4626 internal erc4626Vault;

    function setUp() public override {
        super.setUp();

        _setFee(FEE);

        erc4626Vault = IERC4626(address(vault));

        for (uint256 i; i < NB_MARKETS; ++i) {
            // Create some debt on the market to accrue interest.

            loanToken.setBalance(SUPPLIER, MAX_TEST_ASSETS);

            vm.prank(SUPPLIER);
            IMarket(allMarkets[i]).addSupply(MAX_TEST_ASSETS, 0, ONBEHALF);

            uint256 collateral = uint256(MAX_TEST_ASSETS).divideWithPrecisionUp(allMarketsLltvs[i]);
            collateralToken.setBalance(BORROWER, collateral);

            vm.startPrank(BORROWER);
            IMarket(allMarkets[i]).addCollateral(collateral, BORROWER);
            IMarket(allMarkets[i]).borrow(MAX_TEST_ASSETS, 0, BORROWER, BORROWER, hex"");
            vm.stopPrank();
        }

        _setCap(allMarkets[0], CAP);
        _sortSupplyQueueIdleLast();
    }

    function testSetFee(uint256 fee) public {
        fee = bound(fee, 0, ConstantsLib.MAX_FEE);
        vm.assume(fee != vault.fee());

        vm.expectEmit(address(vault));
        emit IAltoVaultEvents.SetFee(OWNER, fee);
        vm.prank(OWNER);
        vault.setFee(fee);

        assertEq(vault.fee(), fee, "fee");
    }

    function _feeShares() internal view returns (uint256) {
        uint256 totalAssetsAfter = erc4626Vault.totalAssets();
        uint256 interest = totalAssetsAfter - vault.lastTotalAssets();
        uint256 feeAssets = interest.mulDiv(FEE, MATH_PRECISION);

        return feeAssets.divideWithRounding(erc4626Vault.totalSupply() + 1, totalAssetsAfter - feeAssets + 1, false);
    }

    function testAccrueFeeWithinABlock(uint256 deposited, uint256 withdrawn) public {
        deposited = bound(deposited, MIN_TEST_ASSETS + 1, MAX_TEST_ASSETS);
        // The deposited amount is rounded down on AltoVault and thus cannot be withdrawn in a block in most cases.
        withdrawn = bound(withdrawn, MIN_TEST_ASSETS, deposited - 1);

        loanToken.setBalance(SUPPLIER, deposited);

        vm.prank(SUPPLIER);
        erc4626Vault.deposit(deposited, ONBEHALF);

        assertApproxEqAbs(vault.lastTotalAssets(), erc4626Vault.totalAssets(), 1, "lastTotalAssets1");

        vm.prank(ONBEHALF);
        erc4626Vault.withdraw(withdrawn, RECEIVER, ONBEHALF);

        assertApproxEqAbs(vault.lastTotalAssets(), erc4626Vault.totalAssets(), 1, "lastTotalAssets2");
        assertApproxEqAbs(erc4626Vault.balanceOf(FEE_RECIPIENT), 0, 1, "erc4626Vault.balanceOf(FEE_RECIPIENT)");
    }

    function testDepositAccrueFee(uint256 deposited, uint256 newDeposit, uint256 blocks) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);
        newDeposit = bound(newDeposit, MIN_TEST_ASSETS, MAX_TEST_ASSETS);
        blocks = _boundBlocks(blocks);

        loanToken.setBalance(SUPPLIER, deposited);

        vm.prank(SUPPLIER);
        erc4626Vault.deposit(deposited, ONBEHALF);

        assertApproxEqAbs(vault.lastTotalAssets(), erc4626Vault.totalAssets(), 1, "lastTotalAssets1");

        _forward(blocks);

        uint256 feeShares = _feeShares();
        vm.assume(feeShares != 0);

        loanToken.setBalance(SUPPLIER, newDeposit);

        vm.expectEmit(address(erc4626Vault));
        emit IAltoVaultEvents.AccrueInterest(erc4626Vault.totalAssets(), feeShares);

        vm.prank(SUPPLIER);
        erc4626Vault.deposit(newDeposit, ONBEHALF);

        assertApproxEqAbs(vault.lastTotalAssets(), erc4626Vault.totalAssets(), 1, "lastTotalAssets2");
        assertEq(erc4626Vault.balanceOf(FEE_RECIPIENT), feeShares, "erc4626Vault.balanceOf(FEE_RECIPIENT)");
    }

    function testMintAccrueFee(uint256 deposited, uint256 newDeposit, uint256 blocks) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);
        newDeposit = bound(newDeposit, MIN_TEST_ASSETS, MAX_TEST_ASSETS);
        blocks = _boundBlocks(blocks);

        loanToken.setBalance(SUPPLIER, deposited);

        vm.prank(SUPPLIER);
        erc4626Vault.deposit(deposited, ONBEHALF);

        assertApproxEqAbs(vault.lastTotalAssets(), erc4626Vault.totalAssets(), 1, "lastTotalAssets1");

        _forward(blocks);

        uint256 feeShares = _feeShares();
        vm.assume(feeShares != 0);

        uint256 shares = erc4626Vault.convertToShares(newDeposit);

        loanToken.setBalance(SUPPLIER, newDeposit);

        vm.expectEmit(address(erc4626Vault));
        emit IAltoVaultEvents.AccrueInterest(erc4626Vault.totalAssets(), feeShares);

        vm.prank(SUPPLIER);
        erc4626Vault.mint(shares, ONBEHALF);

        assertApproxEqAbs(vault.lastTotalAssets(), erc4626Vault.totalAssets(), 1, "lastTotalAssets2");
        assertEq(erc4626Vault.balanceOf(FEE_RECIPIENT), feeShares, "erc4626Vault.balanceOf(FEE_RECIPIENT)");
    }

    function testRedeemAccrueFee(uint256 deposited, uint256 withdrawn, uint256 blocks) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);
        withdrawn = bound(withdrawn, MIN_TEST_ASSETS, deposited);
        blocks = _boundBlocks(blocks);

        loanToken.setBalance(SUPPLIER, deposited);

        vm.prank(SUPPLIER);
        erc4626Vault.deposit(deposited, ONBEHALF);

        assertApproxEqAbs(vault.lastTotalAssets(), erc4626Vault.totalAssets(), 1, "lastTotalAssets1");

        _forward(blocks);

        uint256 feeShares = _feeShares();
        vm.assume(feeShares != 0);

        uint256 shares = erc4626Vault.convertToShares(withdrawn);

        vm.expectEmit(address(erc4626Vault));
        emit IAltoVaultEvents.AccrueInterest(erc4626Vault.totalAssets(), feeShares);

        vm.prank(ONBEHALF);
        erc4626Vault.redeem(shares, RECEIVER, ONBEHALF);

        assertApproxEqAbs(vault.lastTotalAssets(), erc4626Vault.totalAssets(), 1, "lastTotalAssets2");
        assertEq(erc4626Vault.balanceOf(FEE_RECIPIENT), feeShares, "erc4626Vault.balanceOf(FEE_RECIPIENT)");
    }

    function testWithdrawAccrueFee(uint256 deposited, uint256 withdrawn, uint256 blocks) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);
        withdrawn = bound(withdrawn, MIN_TEST_ASSETS, deposited);
        blocks = _boundBlocks(blocks);

        loanToken.setBalance(SUPPLIER, deposited);

        vm.prank(SUPPLIER);
        erc4626Vault.deposit(deposited, ONBEHALF);

        assertApproxEqAbs(vault.lastTotalAssets(), erc4626Vault.totalAssets(), 1, "lastTotalAssets1");

        _forward(blocks);

        uint256 feeShares = _feeShares();
        vm.assume(feeShares != 0);

        vm.expectEmit(address(erc4626Vault));
        emit IAltoVaultEvents.AccrueInterest(erc4626Vault.totalAssets(), feeShares);

        vm.prank(ONBEHALF);
        erc4626Vault.withdraw(withdrawn, RECEIVER, ONBEHALF);

        assertApproxEqAbs(vault.lastTotalAssets(), erc4626Vault.totalAssets(), 1, "lastTotalAssets2");
        assertEq(erc4626Vault.balanceOf(FEE_RECIPIENT), feeShares, "erc4626Vault.balanceOf(FEE_RECIPIENT)");
    }

    function testSetFeeAccrueFee(uint256 deposited, uint256 fee, uint256 blocks) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);
        fee = bound(fee, 0, FEE - 1);
        blocks = _boundBlocks(blocks);

        loanToken.setBalance(SUPPLIER, deposited);

        vm.prank(SUPPLIER);
        erc4626Vault.deposit(deposited, ONBEHALF);

        assertApproxEqAbs(vault.lastTotalAssets(), erc4626Vault.totalAssets(), 1, "lastTotalAssets1");

        _forward(blocks);

        uint256 feeShares = _feeShares();
        vm.assume(feeShares != 0);

        vm.expectEmit(address(erc4626Vault));
        emit IAltoVaultEvents.AccrueInterest(erc4626Vault.totalAssets(), feeShares);

        _setFee(fee);

        assertApproxEqAbs(vault.lastTotalAssets(), erc4626Vault.totalAssets(), 1, "lastTotalAssets2");
        assertEq(erc4626Vault.balanceOf(FEE_RECIPIENT), feeShares, "erc4626Vault.balanceOf(FEE_RECIPIENT)");
    }

    function testSetFeeRecipientAccrueFee(uint256 deposited, uint256 blocks) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);
        blocks = _boundBlocks(blocks);

        loanToken.setBalance(SUPPLIER, deposited);

        vm.prank(SUPPLIER);
        erc4626Vault.deposit(deposited, ONBEHALF);

        assertApproxEqAbs(vault.lastTotalAssets(), erc4626Vault.totalAssets(), 1, "lastTotalAssets1");

        _forward(blocks);

        uint256 feeShares = _feeShares();
        vm.assume(feeShares != 0);

        vm.expectEmit(address(erc4626Vault));
        emit IAltoVaultEvents.AccrueInterest(erc4626Vault.totalAssets(), feeShares);
        emit IAltoVaultEvents.UpdateLastTotalAssets(erc4626Vault.totalAssets());
        emit IAltoVaultEvents.SetFeeRecipient(address(1));

        vm.prank(OWNER);
        vault.setFeeRecipient(address(1));

        assertApproxEqAbs(vault.lastTotalAssets(), erc4626Vault.totalAssets(), 1, "lastTotalAssets2");
        assertEq(erc4626Vault.balanceOf(FEE_RECIPIENT), feeShares, "erc4626Vault.balanceOf(FEE_RECIPIENT)");
        assertEq(erc4626Vault.balanceOf(address(1)), 0, "erc4626Vault.balanceOf(address(1))");
    }

    function testSetFeeNotOwner(uint256 fee) public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        vault.setFee(fee);
    }

    function testSetFeeMaxFeeExceeded(uint256 fee) public {
        fee = bound(fee, ConstantsLib.MAX_FEE + 1, type(uint256).max);

        vm.prank(OWNER);
        vm.expectRevert(IAltoVaultErrors.MaxFeeExceeded.selector);
        vault.setFee(fee);
    }

    function testSetFeeAlreadySet() public {
        vm.prank(OWNER);
        vm.expectRevert(IAltoVaultErrors.AlreadySet.selector);
        vault.setFee(FEE);
    }

    function testSetFeeZeroFeeRecipient(uint256 fee) public {
        fee = bound(fee, 1, ConstantsLib.MAX_FEE);

        vm.startPrank(OWNER);

        vault.setFee(0);
        vault.setFeeRecipient(address(0));

        vm.expectRevert(IAltoVaultErrors.ZeroFeeRecipient.selector);
        vault.setFee(fee);

        vm.stopPrank();
    }

    function testSetFeeRecipientAlreadySet() public {
        vm.prank(OWNER);
        vm.expectRevert(IAltoVaultErrors.AlreadySet.selector);
        vault.setFeeRecipient(FEE_RECIPIENT);
    }

    function testSetZeroFeeRecipientWithFee() public {
        vm.prank(OWNER);
        vm.expectRevert(IAltoVaultErrors.ZeroFeeRecipient.selector);
        vault.setFeeRecipient(address(0));
    }

    function testConvertToAssetsWithFeeAndInterest(uint256 deposited, uint256 assets, uint256 blocks) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);
        assets = bound(assets, 1, MAX_TEST_ASSETS);
        blocks = _boundBlocks(blocks);

        loanToken.setBalance(SUPPLIER, deposited);

        vm.prank(SUPPLIER);
        erc4626Vault.deposit(deposited, ONBEHALF);

        uint256 sharesBefore = erc4626Vault.convertToShares(assets);

        _forward(blocks);

        uint256 feeShares = _feeShares();
        uint256 expectedShares = assets.mulDiv(
            erc4626Vault.totalSupply() + feeShares + 1, erc4626Vault.totalAssets() + 1, Math.Rounding.Floor
        );
        uint256 shares = erc4626Vault.convertToShares(assets);

        assertEq(shares, expectedShares, "shares");
        assertLt(shares, sharesBefore, "shares decreased");
    }

    function testConvertToSharesWithFeeAndInterest(uint256 deposited, uint256 shares, uint256 blocks) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);
        shares = bound(shares, 1, MAX_TEST_ASSETS);
        blocks = _boundBlocks(blocks);

        loanToken.setBalance(SUPPLIER, deposited);

        vm.prank(SUPPLIER);
        erc4626Vault.deposit(deposited, ONBEHALF);

        uint256 assetsBefore = erc4626Vault.convertToAssets(shares);

        _forward(blocks);

        uint256 feeShares = _feeShares();
        uint256 expectedAssets = shares.mulDiv(
            erc4626Vault.totalAssets() + 1, erc4626Vault.totalSupply() + feeShares + 1, Math.Rounding.Floor
        );
        uint256 assets = erc4626Vault.convertToAssets(shares);

        assertEq(assets, expectedAssets, "assets");
        assertGe(assets, assetsBefore, "assets increased");
    }
}
