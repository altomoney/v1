// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./TestGhoBase.t.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract TestGsmFixedPriceStrategy is TestGhoBase {
    function testConstructor(uint256 ratio, address underlying, uint8 decimals) public {
        vm.assume(ratio > 0);
        decimals = uint8(bound(decimals, 0, 40));

        FixedPriceStrategy strategy = new FixedPriceStrategy(ratio, underlying, decimals, address(this));
        assertEq(strategy.STABLE_TOKEN_DECIMALS(), 18, "Unexpected GHO decimals");
        assertEq(strategy.PRICE_RATIO(), ratio, "Unexpected price ratio");
        assertEq(strategy.UNDERLYING_ASSET(), underlying, "Unexpected underlying asset");
        assertEq(strategy.UNDERLYING_ASSET_DECIMALS(), decimals, "Unexpected underlying asset decimals");
    }

    function testOneToOnePriceRatio() public {
        FixedPriceStrategy strategy = new FixedPriceStrategy(1e18, address(USDC_TOKEN), 6, address(this));
        uint256 usdcIn = 100e6;
        uint256 ghoOut = 100e18;
        assertEq(strategy.getAssetPriceInStableToken(usdcIn, true), ghoOut, "Unexpected asset price in GHO");
        assertEq(strategy.getStableTokenPriceInAsset(ghoOut, false), usdcIn, "Unexpected gho price in asset");
    }

    function testOneToTwoPriceRatio() public {
        FixedPriceStrategy strategy = new FixedPriceStrategy(2e18, address(USDC_TOKEN), 6, address(this));
        uint256 usdcIn = 100e6;
        uint256 ghoOut = 200e18;
        assertEq(strategy.getAssetPriceInStableToken(usdcIn, true), ghoOut, "Unexpected asset price in GHO");
        assertEq(strategy.getStableTokenPriceInAsset(ghoOut, false), usdcIn, "Unexpected gho price in asset");
    }

    function testTwoToOnePriceRatio() public {
        FixedPriceStrategy strategy = new FixedPriceStrategy(0.5e18, address(USDC_TOKEN), 6, address(this));
        uint256 usdcIn = 100e6;
        uint256 ghoOut = 50e18;
        assertEq(strategy.getAssetPriceInStableToken(usdcIn, true), ghoOut, "Unexpected asset price in GHO");
        assertEq(strategy.getStableTokenPriceInAsset(ghoOut, false), usdcIn, "Unexpected gho price in asset");
    }

    function testRevertZeroPriceRatio() public {
        vm.expectRevert("INVALID_PRICE_RATIO");
        new FixedPriceStrategy(0, address(USDC_TOKEN), 6, address(this));
    }

    function testOwnerCanUpdatePriceRatio() public {
        FixedPriceStrategy strategy = new FixedPriceStrategy(1e18, address(USDC_TOKEN), 6, address(this));
        vm.startPrank(address(this));
        strategy.setPriceRatio(2e18);
        vm.stopPrank();
        assertEq(strategy.PRICE_RATIO(), 2e18, "Unexpected price ratio");

        vm.startPrank(address(ALICE));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, ALICE));
        strategy.setPriceRatio(3e18);
        vm.stopPrank();
    }

    function testFuzzingExchangeRate(uint256 ratio, address underlying, uint8 decimals, uint256 amount) public {
        decimals = uint8(bound(decimals, 1, 40));
        ratio = bound(ratio, 1, type(uint128).max - 1);
        amount = bound(amount, 0, type(uint128).max - 1);

        FixedPriceStrategy strategy = new FixedPriceStrategy(ratio, underlying, decimals, address(this));
        uint256 amountInGho = (amount * ratio) / (10 ** decimals);
        assertEq(strategy.getAssetPriceInStableToken(amount, false), amountInGho, "Unexpected asset price in GHO");
    }
}
