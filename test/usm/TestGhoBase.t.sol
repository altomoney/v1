// SPDX-License-Identifier: MIT
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
import {SampleLiquidator} from "@alto/usm/mocks/SampleLiquidator.sol";
import {SampleSwapFreezer} from "@alto/usm/mocks/SampleSwapFreezer.sol";
import {DUSDUsm} from "@alto/usm/DUSDUsm.sol";
import {PercentageMath} from "./PercentageMath.sol";
import {IUsm} from "@alto/usm/interfaces/IUsm.sol";

contract TestGhoBase is Test, TestHelperOz5, Constants {
    using PercentageMath for uint256;

    DUSD GHO_TOKEN;
    ERC20MockMintableDecimals USDC_TOKEN;
    ERC20MockMintableDecimals WETH;
    DUSDUsm GHO_GSM;
    FixedPriceStrategy GHO_GSM_FIXED_PRICE_STRATEGY;
    FixedFeeStrategy GHO_GSM_FIXED_FEE_STRATEGY;
    SampleLiquidator GHO_GSM_LAST_RESORT_LIQUIDATOR;
    SampleSwapFreezer GHO_GSM_SWAP_FREEZER;

    constructor() {
        setupGho();
    }

    function setUp() public virtual override {
        // we setup TestHelperOz5 in constructor - no need to do it here
    }

    function setupGho() public {
        super.setUp();
        setUpEndpoints(1, LibraryType.UltraLightNode);

        GHO_TOKEN = new DUSD(address(endpoints[1]), address(this));
        USDC_TOKEN = new ERC20MockMintableDecimals("USDC Coin", "USDC", 6);
        WETH = new ERC20MockMintableDecimals("Wrapped Ether", "WETH", 18);

        GHO_GSM_FIXED_PRICE_STRATEGY = new FixedPriceStrategy(DEFAULT_FIXED_PRICE, address(USDC_TOKEN), 6);
        GHO_GSM_LAST_RESORT_LIQUIDATOR = new SampleLiquidator();
        GHO_GSM_SWAP_FREEZER = new SampleSwapFreezer();
        DUSDUsm gsm = new DUSDUsm(address(GHO_TOKEN), address(USDC_TOKEN), address(GHO_GSM_FIXED_PRICE_STRATEGY));
        // TODO deploy proxy instead once we have it
        // AdminUpgradeabilityProxy gsmProxy = new AdminUpgradeabilityProxy(address(gsm), SHORT_EXECUTOR, "");
        GHO_GSM = gsm;
        GHO_GSM.initialize(address(this), TREASURY, DEFAULT_GSM_USDC_EXPOSURE);

        GHO_GSM_FIXED_FEE_STRATEGY = new FixedFeeStrategy(DEFAULT_GSM_BUY_FEE, DEFAULT_GSM_SELL_FEE);
        GHO_GSM.updateFeeStrategy(address(GHO_GSM_FIXED_FEE_STRATEGY));

        GHO_GSM.grantRole(GSM_LIQUIDATOR_ROLE, address(GHO_GSM_LAST_RESORT_LIQUIDATOR));
        GHO_GSM.grantRole(GSM_SWAP_FREEZER_ROLE, address(GHO_GSM_SWAP_FREEZER));

        DUSD(GHO_TOKEN).setMinterStatus(address(GHO_GSM), true);
        DUSD(GHO_TOKEN).setMinterCeiling(address(GHO_GSM), DEFAULT_CAPACITY);
        DUSD(GHO_TOKEN).setBurnerStatus(address(GHO_GSM), true);

        DUSD(GHO_TOKEN).setMinterStatus(FAUCET, true);
        DUSD(GHO_TOKEN).setMinterCeiling(FAUCET, uint256(type(uint128).max));
    }

    function ghoFaucet(address to, uint256 amount) public {
        vm.prank(FAUCET);
        GHO_TOKEN.mint(to, amount);
    }

    function _sellAsset(IUsm gsm, ERC20MockMintableDecimals token, address receiver, uint256 amount)
        internal
        returns (uint256)
    {
        vm.startPrank(FAUCET);
        token.mint(FAUCET, amount);
        token.approve(address(gsm), amount);
        (, uint256 ghoBought) = gsm.sellAsset(amount, receiver);
        vm.stopPrank();
        return ghoBought;
    }
}
