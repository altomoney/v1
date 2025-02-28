// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// Tapioca
import {Module} from "tap-utils/interfaces/bar/IMarket.sol";
import {BigBang} from "tapioca-bar/markets/bigBang/BigBang.sol";
import {Market} from "tapioca-bar/markets/Market.sol";

import {IMarket} from "tap-utils/interfaces/bar/ISingularity.sol";

import {ZeroXSwapperMockTarget_test} from "../../../mocks/ZeroXSwapperMockTarget_test.sol";
import {TOFTMock_test} from "../../../mocks/TOFTMock_test.sol";

// tests
import {BigBang_Unit_Shared} from "../../shared/BigBang_Unit_Shared.t.sol";

contract BigBang_liquidateBadDebt is BigBang_Unit_Shared {
    function test_RevertWhen_LiquidateBadDebtIsCalledFromNon_owner() external resetPrank(userA) {
        // **** Main BB market ****
        (Module[] memory modules, bytes[] memory calls) =
            _getLiquidateBadDebtData(address(this), address(this), address(this), "", false);
        // it should revert
        //    │   │   └─ ← [Revert] NotAuthorized()
        //     │   │   └─ ← [Revert] EvmError: Revert
        //     │   └─ ← [Revert] EvmError: Revert
        vm.expectRevert();
        mainBB.execute(modules, calls, true);

        // **** Secondary BB market ****
        // it should revert
        //    │   │   └─ ← [Revert] NotAuthorized()
        //     │   │   └─ ← [Revert] EvmError: Revert
        //     │   └─ ← [Revert] EvmError: Revert
        vm.expectRevert();
        secondaryBB.execute(modules, calls, true);
    }

    function test_whenOwnerIsCalling_RevertWhen_FromIsNotWhitelisted() external {
        // **** Main BB market ****
        (Module[] memory modules, bytes[] memory calls) =
            _getLiquidateBadDebtData(address(this), address(this), address(this), "", false);
        // it should revert
        //         │   │   │   │   └─ ← [Revert] NotAuthorized()
        // │   │   │   └─ ← [Revert] EvmError: Revert
        // │   │   └─ ← [Revert] EvmError: Revert
        // │   └─ ← [Revert] revert: RevertMsgDecoder: no data
        // └─ ← [Revert] revert: RevertMsgDecoder: no data
        cluster.updateContract(0, address(this), false);
        vm.expectRevert();
        mainBB.execute(modules, calls, true);
    }

    function test_whenOwnerIsCalling_RevertWhen_RequiredCollateralIsLessThanCollateralShare(
        uint256 collateralAmount,
        uint256 borrowAmount
    )
        external
        whenOracleRateIsEth
        whenAssetOracleRateIsBelowMin
        whenCollateralAmountIsValid(collateralAmount)
        givenBorrowCapIsNotReachedYet
        whenWhitelisted(address(this))
    {
        borrowAmount = _boundBorrowAmount(borrowAmount, collateralAmount);
        (Module[] memory modules, bytes[] memory calls) =
            _getLiquidateBadDebtData(address(this), address(this), address(this), "", false);

        // **** Main BB market ****
        // add collateral
        _addCollateral(collateralAmount, mainBB, address(this), address(this), address(this));

        // borrow
        // already does the necessary checks
        _borrow(borrowAmount, mainBB, address(this), address(this), address(this));

        // it should revert
        //        │   │   │   │   └─ ← [Revert] ForbiddenAction()
        // │   │   │   └─ ← [Revert] EvmError: Revert
        // │   │   └─ ← [Revert] EvmError: Revert
        // │   └─ ← [Revert] revert: RevertMsgDecoder: no data
        // └─ ← [Revert] revert: RevertMsgDecoder: no data
        vm.expectRevert();
        mainBB.execute(modules, calls, true);

        // **** Secondary BB market ****
        // add collateral
        _addCollateral(collateralAmount, secondaryBB, address(this), address(this), address(this));

        // borrow
        // already does the necessary checks
        _borrow(borrowAmount, secondaryBB, address(this), address(this), address(this));

        // it should revert
        //        │   │   │   │   └─ ← [Revert] ForbiddenAction()
        // │   │   │   └─ ← [Revert] EvmError: Revert
        // │   │   └─ ← [Revert] EvmError: Revert
        // │   └─ ← [Revert] revert: RevertMsgDecoder: no data
        // └─ ← [Revert] revert: RevertMsgDecoder: no data
        vm.expectRevert();
        secondaryBB.execute(modules, calls, true);
    }

    function test_whenOwnerIsCalling_WhenBadLiquidationIsExecuted(uint256 collateralAmount, uint256 borrowAmount)
        external
        whenAssetOracleRateIsBelowMin
        whenCollateralAmountIsValid(collateralAmount)
        givenBorrowCapIsNotReachedYet
        whenWhitelisted(address(this))
    {
        address rndAddr = makeAddr("rndAddress");

        // **** Main BB market ****
        _liquidateBadDebt(collateralAmount, borrowAmount, mainBB, address(this), rndAddr, false);

        // **** Secondary BB market ****
        _liquidateBadDebt(collateralAmount, borrowAmount, secondaryBB, address(this), rndAddr, false);
    }

    function test_whenOwnerIsCalling_WhenSwapCollateralIsRequired(uint256 collateralAmount, uint256 borrowAmount)
        external
        whenAssetOracleRateIsBelowMin
        whenCollateralAmountIsValid(collateralAmount)
        givenBorrowCapIsNotReachedYet
        whenWhitelisted(address(this))
    {
        address rndAddr = makeAddr("rndAddress");

        // it should transfer assets to the receiver
        // **** Main BB market ****
        cluster.updateContract(0, address(mainBB), true);
        cluster.updateContract(0, address(liquidatorReceiver), true);
        _liquidateBadDebt(collateralAmount, borrowAmount, mainBB, address(this), rndAddr, true);

        // **** Secondary BB market ****
        cluster.updateContract(0, address(secondaryBB), true);
        cluster.updateContract(0, address(liquidatorReceiver), true);
        _liquidateBadDebt(collateralAmount, borrowAmount, secondaryBB, address(this), rndAddr, true);
    }

    function test_whenOwnerIsCalling_whenSwapCollateralIsRequired_RevertWhen_ReturnedAmountIsZero(
        uint256 collateralAmount
    )
        external
        whenAssetOracleRateIsBelowMin
        whenOracleRateIsEth
        whenCollateralAmountIsValid(collateralAmount)
        givenBorrowCapIsNotReachedYet
        whenWhitelisted(address(this))
        whenWhitelisted(address(mainBB))
        whenWhitelisted(address(liquidatorReceiver))
    {
        // it should revert
        _addCollateral(collateralAmount, mainBB, address(this), address(this), address(this));

        uint256 maxBorrowAmount = _computeMaxBorrowAmount(collateralAmount, IMarket(address(mainBB)));
        maxBorrowAmount = maxBorrowAmount - (maxBorrowAmount * 2e4 / 1e5);
        _borrow(maxBorrowAmount, mainBB, address(this), address(this), address(this));

        _spawnAsset(mainBB._userBorrowPart(address(this)) * 2, address(this));

        oracle.set(SMALL_AMOUNT);

        // compute asset amount
        SZeroXSwapData memory szeroXSwapData = SZeroXSwapData({
            sellToken: TOFTMock_test(payable(mainBB.collateral())).erc20(),
            buyToken: address(mainBB._asset()),
            swapTarget: payable(swapperTarget),
            swapCallData: abi.encodeWithSelector(
                ZeroXSwapperMockTarget_test.transferTokens.selector, address(mainBB._asset()), 0
            )
        });
        SSwapData memory sswapData = SSwapData({minAmountOut: 0, data: szeroXSwapData});
        bytes memory swapData = abi.encode(sswapData);

        (Module[] memory modules, bytes[] memory calls) =
            _getLiquidateBadDebtData(address(this), address(this), address(this), swapData, true);
        // │   │   │   └─ ← [Revert] OnCollateralReceiverFailed(0, 0)
        // │   │   └─ ← [Revert] revert: <empty>
        // │   └─ ← [Revert] revert: <empty>
        vm.expectRevert();
        mainBB.execute(modules, calls, true);
    }
}
