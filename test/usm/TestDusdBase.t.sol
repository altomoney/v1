// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

// helpers
import {Constants} from "./helpers/Constants.sol";
import {DUSD} from "@alto/tokens/DUSD.sol";
import {ERC20MockMintableDecimals} from "@alto-test/helpers/ERC20MockMintableDecimals.sol";
import {TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import {FixedPriceStrategy} from "@alto/usm/FixedPriceStrategy.sol";
import {FixedFeeStrategy} from "@alto/usm/FixedFeeStrategy.sol";
import {SampleLiquidator} from "@alto-test/usm/mocks/SampleLiquidator.sol";
import {SampleSwapFreezer} from "@alto-test/usm/mocks/SampleSwapFreezer.sol";
import {DUSDUsm} from "@alto/usm/DUSDUsm.sol";
import {PercentageMath} from "./PercentageMath.sol";
import {IUsm, AccessMode} from "@alto/usm/interfaces/IUsm.sol";
import {Usm} from "@alto/usm/Usm.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {UsmDeployer, DusdUsmInitParams} from "@alto-test/helpers/UsmDeployer.sol";

contract TestDusdBase is Test, TestHelperOz5, Constants {
    using PercentageMath for uint256;

    DUSD DUSD_TOKEN;
    ERC20MockMintableDecimals USDC_TOKEN;
    ERC20MockMintableDecimals WETH;
    Usm DUSD_USM;
    Usm PERMISSIONED_DUSD_USM;
    FixedPriceStrategy DUSD_USM_FIXED_PRICE_STRATEGY;
    FixedFeeStrategy DUSD_USM_FIXED_FEE_STRATEGY;
    SampleLiquidator DUSD_USM_LAST_RESORT_LIQUIDATOR;
    SampleSwapFreezer DUSD_USM_SWAP_FREEZER;
    address multisigTreasury = makeAddr("MultisigTreasury");

    constructor() {
        setupDusd();
    }

    function setUp() public virtual override {
        // we setup TestHelperOz5 in constructor - no need to do it here
    }

    function setupDusd() public {
        super.setUp();
        setUpEndpoints(1, LibraryType.UltraLightNode);

        DUSD_TOKEN = new DUSD(address(endpoints[1]), address(this));
        USDC_TOKEN = new ERC20MockMintableDecimals("USDC Coin", "USDC", 6);
        WETH = new ERC20MockMintableDecimals("Wrapped Ether", "WETH", 18);

        DUSD_USM_FIXED_PRICE_STRATEGY = new FixedPriceStrategy(DEFAULT_FIXED_PRICE, address(USDC_TOKEN), address(this));
        DUSD_USM_LAST_RESORT_LIQUIDATOR = new SampleLiquidator();
        DUSD_USM_SWAP_FREEZER = new SampleSwapFreezer();
        DUSDUsm usm = new DUSDUsm(address(DUSD_TOKEN), address(USDC_TOKEN));
        DUSDUsm permissionedUsm = new DUSDUsm(address(DUSD_TOKEN), address(USDC_TOKEN));
        address usmProxy = UnsafeUpgrades.deployUUPSProxy(
            address(usm),
            abi.encodeCall(
                DUSDUsm.initialize,
                (
                    address(this),
                    TREASURY,
                    DEFAULT_USM_USDC_EXPOSURE,
                    address(DUSD_USM_FIXED_PRICE_STRATEGY),
                    AccessMode.PERMISSIONLESS
                )
            )
        );
        DUSDUsm(usmProxy).updateFeeRecipient(FEE_RECIPIENT);
        DUSD_USM = Usm(usmProxy);

        address permissionedUsmProxy = UnsafeUpgrades.deployUUPSProxy(
            address(permissionedUsm),
            abi.encodeCall(
                DUSDUsm.initialize,
                (
                    address(this),
                    TREASURY,
                    DEFAULT_USM_USDC_EXPOSURE,
                    address(DUSD_USM_FIXED_PRICE_STRATEGY),
                    AccessMode.PERMISSIONED
                )
            )
        );
        PERMISSIONED_DUSD_USM = Usm(permissionedUsmProxy);

        DUSD_USM_FIXED_FEE_STRATEGY = new FixedFeeStrategy(DEFAULT_USM_BUY_FEE, DEFAULT_USM_SELL_FEE, address(this));
        DUSD_USM.updateFeeRecipient(FEE_RECIPIENT);
        DUSD_USM.updateFeeStrategy(address(DUSD_USM_FIXED_FEE_STRATEGY));

        DUSD_USM.grantRole(USM_LIQUIDATOR_ROLE, address(DUSD_USM_LAST_RESORT_LIQUIDATOR));
        DUSD_USM.grantRole(USM_SWAP_FREEZER_ROLE, address(DUSD_USM_SWAP_FREEZER));

        PERMISSIONED_DUSD_USM.grantRole(USM_LIQUIDATOR_ROLE, address(DUSD_USM_LAST_RESORT_LIQUIDATOR));
        PERMISSIONED_DUSD_USM.grantRole(USM_SWAP_FREEZER_ROLE, address(DUSD_USM_SWAP_FREEZER));
        PERMISSIONED_DUSD_USM.grantRole(USM_SWAPPER_ROLE, multisigTreasury);
        PERMISSIONED_DUSD_USM.updateAccessMode(AccessMode.PERMISSIONED);

        DUSD(DUSD_TOKEN).setMinterStatus(address(DUSD_USM), true);
        DUSD(DUSD_TOKEN).setMinterStatus(address(PERMISSIONED_DUSD_USM), true);
        DUSD(DUSD_TOKEN).setMinterCeiling(address(DUSD_USM), DEFAULT_CAPACITY);
        DUSD(DUSD_TOKEN).setMinterCeiling(address(PERMISSIONED_DUSD_USM), DEFAULT_CAPACITY);
        DUSD(DUSD_TOKEN).setBurnerStatus(address(DUSD_USM), true);
        DUSD(DUSD_TOKEN).setBurnerStatus(address(PERMISSIONED_DUSD_USM), true);

        DUSD(DUSD_TOKEN).setMinterStatus(FAUCET, true);
        DUSD(DUSD_TOKEN).setMinterCeiling(FAUCET, uint256(type(uint128).max));
    }

    function _sellAsset(IUsm usm, ERC20MockMintableDecimals token, address receiver, uint256 amount)
        internal
        returns (uint256)
    {
        vm.startPrank(FAUCET);
        token.mint(FAUCET, amount);
        token.approve(address(usm), amount);
        (, uint256 dusdBought) = usm.sellAsset(amount, receiver);
        vm.stopPrank();
        return dusdBought;
    }

    function deployDusdUsm(address dusd, address underlyingAsset, DusdUsmInitParams memory _initParams)
        internal
        returns (DUSDUsm)
    {
        return DUSDUsm(UsmDeployer.deployDusdUsm(dusd, underlyingAsset, _initParams));
    }

    function dusdFaucet(address to, uint256 amount) internal {
        vm.prank(FAUCET);
        DUSD_TOKEN.mint(to, amount);
    }
}
