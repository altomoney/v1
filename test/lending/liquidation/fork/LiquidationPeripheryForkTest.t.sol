// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {LiquidationPeriphery} from "@alto/lending/liquidation/LiquidationPeriphery.sol";
import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";
import {Liquidator} from "./Liquidator.sol";
import {IMarket} from "@alto/lending/interfaces/IMarket.sol";
import {DirectionAccess} from "@alto/usm/interfaces/IAdvancedPermissionsUsm.sol";
import {DUSDAdvancedPermissionsUsm} from "@alto/usm/DUSDAdvancedPermissionsUsm.sol";
import {FixedPriceStrategy} from "@alto/usm/FixedPriceStrategy.sol";
import {AdvancedPermissionsFeeStrategy} from "@alto/usm/AdvancedPermissionsFeeStrategy.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";
import {ILendingOracle, LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {ILiquidationPeripheryEvents} from "@alto/lending/liquidation/interfaces/ILiquidationPeriphery.sol";
import {USDC_MAINNET, WETH_MAINNET} from "@alto/deployments/ethereum-mainnet/Constants.sol";
import {UsmRegistry} from "@alto/utils/UsmRegistry.sol";

/// @dev Mainnet-fork liquidation on WETH mint market: EOA calls `Liquidator.liquidateMarket` (swaps from WETH -> USDC -> DUSD).
/// @dev Paraswap quote written at `test/lending/liquidation/fork/swapData/paraswap/`.
contract LiquidationPeripheryForkTest is Test {
    string internal constant PARASWAP_PRICE_JSON =
        "test/lending/liquidation/fork/swapData/paraswap/weth_to_usdc_price_response.json";
    string internal constant PARASWAP_TX_JSON =
        "test/lending/liquidation/fork/swapData/paraswap/weth_to_usdc_tx_response.json";

    uint256 internal constant ONE_TO_ONE_PRICE_RATIO = 1e18;
    uint128 internal constant USM_EXPOSURE_CAP = uint128(500_000 * 1e6);
    uint128 internal constant USM_MINT_CEILING = uint128(500_000 * 1e18);

    address internal constant DUSD_MAINNET = 0x63d74d22E689C715a04F2C13962b1f77F443d35b;
    address internal constant WETH_MINT_MARKET = 0x8DED9e2B8Bc5128B862dD534b97c8a32991959ff;

    address internal liquidatorEoa = makeAddr("LiquidatorEoa");
    address internal borrower = makeAddr("Borrower");
    address internal stableTreasury = makeAddr("StableTreasury");
    address internal peripheryTreasury = makeAddr("PeripheryTreasury");

    LiquidationPeriphery internal periphery;
    DUSDAdvancedPermissionsUsm internal usm;
    Liquidator internal liquidatorContract;

    address internal paraswapAugustus;
    address internal tokenTransferProxy;
    bytes internal swapCalldata;

    struct LiquidatorBalances {
        uint256 dusd;
        uint256 usdc;
        uint256 weth;
    }

    function setUp() public {
        string memory priceJson = vm.readFile(PARASWAP_PRICE_JSON);
        string memory txJson = vm.readFile(PARASWAP_TX_JSON);

        uint256 forkBlock = vm.parseJsonUint(priceJson, ".priceRoute.blockNumber");
        tokenTransferProxy = vm.parseJsonAddress(priceJson, ".priceRoute.tokenTransferProxy");
        paraswapAugustus = vm.parseJsonAddress(txJson, ".to");
        swapCalldata = vm.parseJsonBytes(txJson, ".data");

        assertEq(paraswapAugustus, vm.parseJsonAddress(priceJson, ".priceRoute.contractAddress"), "augustus mismatch");

        vm.createSelectFork(vm.rpcUrl("ethereum"), forkBlock);

        UsmRegistry usmRegistry = new UsmRegistry(address(this));
        usm = _deployForkUsm();
        usmRegistry.addUsm(address(usm));
        periphery = new LiquidationPeriphery(address(this), DUSD_MAINNET, address(usmRegistry), peripheryTreasury);
        liquidatorContract = new Liquidator(address(periphery), address(usm), paraswapAugustus);

        periphery.setSupportedMarket(WETH_MINT_MARKET, true);
        _upgradeForkMarketAndAuthorizePeriphery();
    }

    /// @dev Mainnet mint market impl predates `authorizedLiquidationPeriphery`; upgrade on fork then whitelist periphery.
    function _upgradeForkMarketAndAuthorizePeriphery() internal {
        address marketOwner = Ownable(WETH_MINT_MARKET).owner();
        address upgradedImpl = address(new AltoMintMarket());

        vm.startPrank(marketOwner);
        UnsafeUpgrades.upgradeProxy(WETH_MINT_MARKET, upgradedImpl, "");
        IMarket(WETH_MINT_MARKET).setAuthorizedLiquidationPeriphery(address(periphery), true);
        vm.stopPrank();
    }

    // test liquidation where liquidator contract has no prefunded balance
    // this tests with expected stable refund being non-zero and hence liquidator contract will receive stable tokens
    function test_Fork_Liquidate_viaEoa_noPrefundedLiquidatorBalances() public {
        _setupInsolventMintPosition();

        bytes memory peripheryCallbackData = abi.encode(WETH_MINT_MARKET, tokenTransferProxy, swapCalldata);

        _assertZeroErc20Balances(liquidatorEoa);
        _assertZeroErc20Balances(address(liquidatorContract));

        // all three balances are 0
        LiquidatorBalances memory before = _liquidatorBalances(address(liquidatorContract));

        vm.expectEmit(true, true, true, false);
        emit ILiquidationPeripheryEvents.Liquidation(WETH_MINT_MARKET, address(liquidatorContract), borrower, 0, 0, 0);

        vm.prank(liquidatorEoa);
        (uint256 seizedCollateral, uint256 repaidBorrow,) =
            liquidatorContract.liquidateMarket(WETH_MINT_MARKET, borrower, address(usm), "", peripheryCallbackData);

        uint256 expectedStableRefund = _expectedStableRefund(repaidBorrow);

        assertGt(expectedStableRefund, 0);
        assertLe(expectedStableRefund, 1e15, "no meaningful stable refund to liquidator");

        assertEq(IERC20(DUSD_MAINNET).balanceOf(address(liquidatorContract)) - before.dusd, expectedStableRefund);

        _assertLiquidationSucceeded(seizedCollateral, repaidBorrow);
        _assertSwapLiquidationOutcome(before);
    }

    // test liquidation where stable bought equals borrow repaid at 1:1 with zero USM sell fees
    // liquidator contract receives no stable token refund, only USDC swap surplus
    function test_Fork_Liquidate_viaEoa_noStableRefundToLiquidator() public {
        _setupInsolventMintPosition();
        _configureZeroUsmFees();

        bytes memory peripheryCallbackData = abi.encode(WETH_MINT_MARKET, tokenTransferProxy, swapCalldata);

        _assertZeroErc20Balances(liquidatorEoa);
        _assertZeroErc20Balances(address(liquidatorContract));

        LiquidatorBalances memory before = _liquidatorBalances(address(liquidatorContract));

        vm.expectEmit(true, true, true, false);
        emit ILiquidationPeripheryEvents.Liquidation(WETH_MINT_MARKET, address(liquidatorContract), borrower, 0, 0, 0);

        vm.prank(liquidatorEoa);
        (uint256 seizedCollateral, uint256 repaidBorrow,) =
            liquidatorContract.liquidateMarket(WETH_MINT_MARKET, borrower, address(usm), "", peripheryCallbackData);

        uint256 expectedStableRefund = _expectedStableRefund(repaidBorrow);

        assertEq(expectedStableRefund, 0, "expected stable refund");
        assertEq(
            IERC20(DUSD_MAINNET).balanceOf(address(liquidatorContract)), before.dusd, "no stable refund to liquidator"
        );

        _assertLiquidationSucceeded(seizedCollateral, repaidBorrow);
        _assertSwapLiquidationOutcome(before);
    }

    function _configureZeroUsmFees() internal {
        AdvancedPermissionsFeeStrategy feeStrategy = new AdvancedPermissionsFeeStrategy(0, 0, address(this));
        usm.updateFeeStrategy(address(feeStrategy));
    }

    function _deployForkUsm() internal returns (DUSDAdvancedPermissionsUsm deployed) {
        FixedPriceStrategy priceStrategy = new FixedPriceStrategy(ONE_TO_ONE_PRICE_RATIO, USDC_MAINNET, address(this));

        address impl = address(new DUSDAdvancedPermissionsUsm(DUSD_MAINNET, USDC_MAINNET));
        address proxy = UnsafeUpgrades.deployUUPSProxy(
            impl,
            abi.encodeCall(
                DUSDAdvancedPermissionsUsm.initialize,
                (
                    address(this),
                    stableTreasury,
                    USM_EXPOSURE_CAP,
                    address(priceStrategy),
                    DirectionAccess.PERMISSIONLESS,
                    DirectionAccess.PERMISSIONLESS
                )
            )
        );
        deployed = DUSDAdvancedPermissionsUsm(proxy);

        AdvancedPermissionsFeeStrategy feeStrategy = new AdvancedPermissionsFeeStrategy(5, 5, address(this));
        deployed.updateFeeRecipient(stableTreasury);
        deployed.updateFeeStrategy(address(feeStrategy));

        address dusdOwner = Ownable(DUSD_MAINNET).owner();
        vm.startPrank(dusdOwner);
        IDUSD(DUSD_MAINNET).setMinterStatus(address(deployed), true);
        IDUSD(DUSD_MAINNET).setMinterCeiling(address(deployed), USM_MINT_CEILING);
        IDUSD(DUSD_MAINNET).setBurnerStatus(address(deployed), true);
        vm.stopPrank();
    }

    function _setupInsolventMintPosition() internal {
        IMarket market = IMarket(WETH_MINT_MARKET);

        deal(WETH_MAINNET, borrower, 10 ether);

        vm.startPrank(borrower);
        IERC20(WETH_MAINNET).approve(WETH_MINT_MARKET, type(uint256).max);
        market.setAuthorization(address(this), true);
        market.addCollateral(2 ether, borrower);
        market.borrow(3200 ether, 0, borrower, borrower, "");
        vm.stopPrank();

        market.accrueInterest();

        address oracle = market.oracle();
        vm.mockCall(
            oracle,
            abi.encodeWithSelector(ILendingOracle.getPrice.selector),
            abi.encode(1000 * LENDING_ORACLE_PRICE_PRECISION)
        );
    }

    function _liquidatorBalances(address account) internal view returns (LiquidatorBalances memory balances) {
        balances.dusd = IERC20(DUSD_MAINNET).balanceOf(account);
        balances.usdc = IERC20(USDC_MAINNET).balanceOf(account);
        balances.weth = IERC20(WETH_MAINNET).balanceOf(account);
    }

    function _assertLiquidationSucceeded(uint256 seizedCollateral, uint256 repaidBorrow) internal pure {
        assertGt(seizedCollateral, 0, "seized collateral");
        assertGt(repaidBorrow, 0, "repaid borrow");
    }

    function _assertSwapLiquidationOutcome(LiquidatorBalances memory before) internal view {
        address liquidator = address(liquidatorContract);

        assertEq(IERC20(WETH_MAINNET).balanceOf(liquidator), 0, "liquidator WETH dust remains");
        assertGt(IERC20(USDC_MAINNET).balanceOf(liquidator), before.usdc, "liquidator profits in USDC");

        _assertPeripheryClean();
    }

    function _expectedStableRefund(uint256 repaidBorrow) internal view returns (uint256) {
        (, uint256 stableBought,,) = usm.getAssetAmountForSellAsset(repaidBorrow, address(periphery));
        return stableBought > repaidBorrow ? stableBought - repaidBorrow : 0;
    }

    function _assertPeripheryClean() internal view {
        assertEq(IERC20(DUSD_MAINNET).balanceOf(address(periphery)), 0, "periphery DUSD dust");
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(periphery)), 0, "periphery USDC dust");
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(periphery)), 0, "periphery WETH dust");
        assertEq(IERC20(DUSD_MAINNET).allowance(address(periphery), WETH_MINT_MARKET), 0, "periphery borrow approval");
        _assertZeroApproval(address(periphery), USDC_MAINNET, address(usm));
        _assertZeroApproval(address(periphery), USDC_MAINNET, WETH_MINT_MARKET);
        _assertZeroApproval(address(periphery), DUSD_MAINNET, address(usm));
        _assertZeroApproval(address(periphery), DUSD_MAINNET, WETH_MINT_MARKET);
    }

    function _assertZeroApproval(address owner, address token, address spender) internal view {
        assertEq(IERC20(token).allowance(owner, spender), 0);
    }

    function _assertZeroErc20Balances(address account) internal view {
        assertEq(IERC20(DUSD_MAINNET).balanceOf(account), 0);
        assertEq(IERC20(USDC_MAINNET).balanceOf(account), 0);
        assertEq(IERC20(WETH_MAINNET).balanceOf(account), 0);
    }
}
