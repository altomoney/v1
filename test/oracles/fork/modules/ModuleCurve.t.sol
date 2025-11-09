// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ModuleCurve} from "@alto/oracles/modules/ModuleCurve.sol";
import {ICurvePool} from "@alto/oracles/interfaces/ICurvePool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CurveNode} from "@alto/oracles/interfaces/IModuleNode.sol";

contract ModuleCurveTest is Test {
    ModuleCurve moduleCurve;
    address constant PXETH_WETH_CURVE_POOL = 0xC8Eb2Cf2f792F77AF0Cd9e203305a585E588179D; // curve pool for pxETH/WETH
    address constant PXETH_STETH_CURVE_POOL = 0x6951bDC4734b9f7F3E1B74afeBC670c736A0EDB6; // curve pool for pxETH/STETH
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant PXETH = 0x04C154b66CB340F3Ae24111CC767e0184Ed00Cc6;
    address constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;

    function setUp() public {
        string memory rpcUrl = vm.rpcUrl("ethereum");
        vm.createSelectFork(rpcUrl, 23466674);
        moduleCurve = new ModuleCurve();
    }

    function testGetPricePxEthWeth() public view {
        uint256 pxethQuoteAmount = 10 ** 18;
        uint256 wethAmount = moduleCurve.readCurvePool(
            pxethQuoteAmount, CurveNode(ICurvePool(PXETH_WETH_CURVE_POOL), 0, 1, 18, 18, 10 minutes, 1 days)
        );
        assertGt(wethAmount, 0, "Invalid wethAmount in CurveModule");
        console2.log("price of pxETH/WETH from CurveModule", wethAmount);
        assertApproxEqAbs(wethAmount, 0.994817 * 10 ** 18, 1e12);

        uint256 pxethAmountBack = moduleCurve.readCurvePool(
            wethAmount, CurveNode(ICurvePool(PXETH_WETH_CURVE_POOL), 0, 0, 18, 18, 10 minutes, 1 days)
        );
        assertGt(pxethAmountBack, 0, "Invalid pxethAmountBack in CurveModule");
        console2.log("pxeth amount back", pxethAmountBack);
        assertApproxEqAbs(pxethAmountBack, pxethQuoteAmount, 1e2);
    }

    function testGetPricePxEthSteth() public view {
        uint256 pxethQuoteAmount = 10 ** 18;
        uint256 stethAmount = moduleCurve.readCurvePool(
            pxethQuoteAmount, CurveNode(ICurvePool(PXETH_STETH_CURVE_POOL), 0, 1, 18, 18, 10 minutes, 1 days)
        );
        assertGt(stethAmount, 0, "Invalid stethAmount in CurveModule");
        console2.log("price of pxETH/STETH from CurveModule", stethAmount);
        assertApproxEqAbs(stethAmount, 1.004887 * 10 ** 18, 1e12);
        uint256 pxethAmountBack = moduleCurve.readCurvePool(
            stethAmount, CurveNode(ICurvePool(PXETH_STETH_CURVE_POOL), 0, 0, 18, 18, 10 minutes, 1 days)
        );
        assertGt(pxethAmountBack, 0, "Invalid pxethAmountBack in CurveModule");
        console2.log("pxeth amount back", pxethAmountBack);
        assertApproxEqAbs(pxethAmountBack, pxethQuoteAmount, 1e2);
    }

    function testRevertWhenPricesAreStale() public {
        uint256 pxethQuoteAmount = 10 ** 18;
        vm.expectRevert(abi.encodeWithSelector(ModuleCurve.ModuleCurveInvalidRate.selector));
        moduleCurve.readCurvePool(
            pxethQuoteAmount, CurveNode(ICurvePool(PXETH_WETH_CURVE_POOL), 0, 1, 18, 18, 10 minutes, 2 hours)
        );
    }

    function testRevertWhenMinMaExpTimeIsNotMet() public {
        uint256 pxethQuoteAmount = 10 ** 18;
        vm.expectRevert(abi.encodeWithSelector(ModuleCurve.ModuleCurveInvalidRate.selector));
        moduleCurve.readCurvePool(
            pxethQuoteAmount, CurveNode(ICurvePool(PXETH_WETH_CURVE_POOL), 0, 1, 18, 18, 15 minutes, 2 hours)
        );
    }
}
