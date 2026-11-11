// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AltoLeverageSwapperForWrapperToken} from "@alto/lending/wrappedToken/AltoLeverageSwapperForWrapperToken.sol";
import {SwapParamsWrapperToken} from "@alto/lending/wrappedToken/IAltoLeverageSwapperForWrapperToken.sol";
import {MarketMock} from "./mocks/MarketMock.sol";
import {WrapperTokenHarness} from "../WrapperToken/mocks/WrapperTokenHarness.sol";
import {SwapTargetMock} from "../WrapperToken/mocks/SwapTargetMock.sol";
import {ERC20MockMintableDecimals} from "@alto-test/helpers/ERC20MockMintableDecimals.sol";

abstract contract AltoLeverageSwapperForWrapperTokenCommon is Test {
    uint8 internal constant TOKEN_DECIMALS = 18;

    /// @dev exchangeRate > 10**DECIMALS so wrap/unwrap are not 1:1 and rounding is exercised.
    uint256 internal constant EXCHANGE_RATE = (0.9 ether * 10 ** TOKEN_DECIMALS) / 1 ether;

    uint256 internal constant WRAPPED_COLLATERAL_IN = 100 ether;
    uint256 internal constant PT_COLLATERAL_IN = WRAPPED_COLLATERAL_IN * EXCHANGE_RATE / 10 ** TOKEN_DECIMALS;
    uint256 internal constant OTHER_TOKEN_AMOUNT_IN = 100 ether;
    uint256 internal constant BUY_AMOUNT_OUT = 90 ether;
    uint256 internal constant MIN_AMOUNT_OUT = 80 ether;
    uint256 internal constant DONATED_UNDERLYING = 5 ether;

    address internal owner;
    address internal nonOwner;
    address internal caller;
    address internal nonWhitelisted;

    ERC20MockMintableDecimals internal underlyingPt;
    ERC20MockMintableDecimals internal otherToken;
    ERC20MockMintableDecimals internal unrelatedToken;
    WrapperTokenHarness internal collateralWrapper;
    MarketMock internal market;
    SwapTargetMock internal swapTarget;
    AltoLeverageSwapperForWrapperToken internal swapper;

    function setUp() public virtual {
        owner = makeAddr("owner");
        nonOwner = makeAddr("nonOwner");
        caller = makeAddr("caller");
        nonWhitelisted = makeAddr("nonWhitelisted");

        underlyingPt = new ERC20MockMintableDecimals("PT", "PT", TOKEN_DECIMALS);
        otherToken = new ERC20MockMintableDecimals("DUSD", "DUSD", TOKEN_DECIMALS);
        unrelatedToken = new ERC20MockMintableDecimals("UNREL", "UNREL", TOKEN_DECIMALS);
        collateralWrapper =
            new WrapperTokenHarness("Wrapped PT", "wPT", address(underlyingPt), owner, makeAddr("rollOverBot"));
        vm.prank(owner);
        collateralWrapper.setExchangeRateForTest(EXCHANGE_RATE);

        market = new MarketMock(address(collateralWrapper));
        swapTarget = new SwapTargetMock();

        address[] memory validSwapTargets = new address[](1);
        validSwapTargets[0] = address(swapTarget);

        swapper = new AltoLeverageSwapperForWrapperToken(owner, address(market), validSwapTargets);

        vm.prank(owner);
        swapper.setWhitelisted(caller, true);
    }

    function _collateralToken() internal view returns (address) {
        return address(collateralWrapper);
    }

    function _encodeSwapParams(
        uint256 minAmountOut,
        address underlyingToken,
        address swapTargetAddr,
        bytes memory swapData
    ) internal pure returns (bytes memory) {
        return abi.encode(
            SwapParamsWrapperToken({
                minAmountOut: minAmountOut,
                underlyingToken: underlyingToken,
                swapTarget: swapTargetAddr,
                swapData: swapData
            })
        );
    }

    function _buildSwapData(address sellToken, address buyToken, uint256 amountIn, uint256 buyAmountOut)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeCall(SwapTargetMock.executeSwap, (sellToken, buyToken, amountIn, buyAmountOut));
    }

    function _fundCallerWithCollateral(uint256 wrappedAmount) internal returns (uint256 ptDeposited) {
        ptDeposited = collateralWrapper.previewUnwrap(wrappedAmount);
        assertEq(collateralWrapper.previewWrap(ptDeposited), wrappedAmount);

        underlyingPt.mint(caller, ptDeposited);
        vm.startPrank(caller);
        underlyingPt.approve(_collateralToken(), ptDeposited);
        assertEq(collateralWrapper.wrap(ptDeposited), wrappedAmount);
        collateralWrapper.approve(address(swapper), wrappedAmount);
        vm.stopPrank();
    }

    function _fundCallerWithOtherToken(uint256 amount) internal {
        otherToken.mint(caller, amount);
        vm.prank(caller);
        otherToken.approve(address(swapper), amount);
    }

    function _assertZeroResidualBalances() internal view {
        assertEq(underlyingPt.balanceOf(address(swapper)), 0, "underlyingToken balance");
        assertEq(otherToken.balanceOf(address(swapper)), 0, "otherToken balance");
        assertEq(collateralWrapper.balanceOf(address(swapper)), 0, "collateral balance");
        assertEq(unrelatedToken.balanceOf(address(swapper)), 0, "unrelatedToken balance");
    }

    function _callSwap(address sellToken, address buyToken, uint256 amountIn, bytes memory swapParams) internal {
        vm.prank(caller);
        swapper.swap(sellToken, buyToken, amountIn, swapParams);
    }

    function _donateUnderlyingToSwapper(uint256 amount) internal {
        underlyingPt.mint(address(swapper), amount);
    }

    function _donateCollateralToSwapper(uint256 underlyingAmount) internal returns (uint256 wrappedDonated) {
        address donor = makeAddr("donor");
        underlyingPt.mint(donor, underlyingAmount);
        vm.startPrank(donor);
        underlyingPt.approve(_collateralToken(), underlyingAmount);
        wrappedDonated = collateralWrapper.wrap(underlyingAmount);
        collateralWrapper.transfer(address(swapper), wrappedDonated);
        vm.stopPrank();
    }
}
