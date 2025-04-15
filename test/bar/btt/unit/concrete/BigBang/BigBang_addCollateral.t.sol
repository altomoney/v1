// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// Tapioca
import {Module} from "tap-utils/interfaces/bar/IMarket.sol";
import {BigBang} from "tapioca-bar/markets/bigBang/BigBang.sol";
import {Market} from "tapioca-bar/markets/Market.sol";

// tests
import {BigBang_Unit_Shared} from "../../shared/BigBang_Unit_Shared.t.sol";

contract BigBang_addCollateral is BigBang_Unit_Shared {
    modifier whenIterationsAreValid(uint256 iterations) {
        vm.assume(iterations > 0 && iterations < MAX_ITERATIONS);
        _;
    }

    function test_WhenContractIsPaused(uint256 collateralAmount)
        external
        whenContractIsPaused
        whenCollateralAmountIsValid(collateralAmount)
    {
        (Module[] memory modules, bytes[] memory calls) =
            _getCollateralData(collateralAmount, address(this), address(this));
        // it should revert with 'Market: paused'
        vm.expectRevert("Market: paused");
        mainBB.execute(modules, calls, true);

        // it should revert with 'Market: paused'
        vm.expectRevert("Market: paused");
        secondaryBB.execute(modules, calls, true);

        (modules, calls) = _getCollateralData(collateralAmount, address(this), address(this));
        // it should revert with 'Market: paused'
        vm.expectRevert("Market: paused");
        mainBB.execute(modules, calls, true);

        // it should revert with 'Market: paused'
        vm.expectRevert("Market: paused");
        secondaryBB.execute(modules, calls, true);
    }

    function test_GivenCalledForItself(uint256 collateralAmount)
        external
        whenContractIsNotPaused
        whenCollateralAmountIsValid(collateralAmount)
    {
        (Module[] memory modules, bytes[] memory calls) =
            _getCollateralData(collateralAmount, address(mainBB), address(mainBB));

        // it should revert with 'Market: cannot execute on itself'
        vm.expectRevert("Market: cannot execute on itself");
        mainBB.execute(modules, calls, true);

        // it should revert with 'Market: cannot execute on itself'
        (modules, calls) = _getCollateralData(collateralAmount, address(secondaryBB), address(secondaryBB));
        vm.expectRevert("Market: cannot execute on itself");
        secondaryBB.execute(modules, calls, true);

        // it should revert with 'Market: cannot execute on itself'
        (modules, calls) = _getCollateralData(collateralAmount, address(mainBB), address(mainBB));
        vm.expectRevert("Market: cannot execute on itself");
        mainBB.execute(modules, calls, true);

        // it should revert with 'Market: cannot execute on itself'
        (modules, calls) = _getCollateralData(collateralAmount, address(secondaryBB), address(secondaryBB));
        vm.expectRevert("Market: cannot execute on itself");
        secondaryBB.execute(modules, calls, true);
    }

    function test_RevertGiven_AmountIsTooLow(uint256 collateralAmount) external whenContractIsNotPaused {
        uint256 minCollateralAmount = mainBB.minCollateralAmount();
        vm.assume(collateralAmount > 0 && collateralAmount < minCollateralAmount);

        (Module[] memory modules, bytes[] memory calls) =
            _getCollateralData(collateralAmount, address(this), address(this));

        // min amount revert
        vm.expectRevert();
        mainBB.execute(modules, calls, true);

        // min amount revert
        vm.expectRevert();
        secondaryBB.execute(modules, calls, true);
    }

    function test_givenCalledForAValidSenderByItself(uint256 collateralAmount)
        external
        whenContractIsNotPaused
        whenCollateralAmountIsValid(collateralAmount)
    {
        uint256 iterations = 10;
        // **** Main BB market ****
        for (uint256 i; i < iterations; i++) {
            // already does the necessary checks
            _addCollateral(collateralAmount, mainBB, address(this), address(this), address(this));
        }

        // **** Secondary BB market ****
        for (uint256 i; i < iterations; i++) {
            // already does the necessary checks
            _addCollateral(collateralAmount, secondaryBB, address(this), address(this), address(this));
        }
    }

    function test_givenCalledFromAnotherUser_WhenUserDoesNotHaveEnoughAllowance(uint256 collateralAmount)
        external
        whenContractIsNotPaused
        whenCollateralAmountIsValid(collateralAmount)
    {
        // deal collateral
        _spawnCollateral(collateralAmount, userB);

        _approveViaERC20(address(mainBB.collateral()), userB, address(mainBB), type(uint256).max);

        (Module[] memory modules, bytes[] memory calls) = _getCollateralData(collateralAmount, userB, userB);

        // it should revert with 'Market: not approved'
        vm.expectRevert("Market: not approved");

        _resetPrank(userA);
        mainBB.execute(modules, calls, true);
    }

    function test_givenCalledFromAnotherUser(uint256 collateralAmount)
        external
        whenContractIsNotPaused
        whenCollateralAmountIsValid(collateralAmount)
    {
        // **** Main BB market ****
        _resetPrank(userB);
        _approveViaERC20(mainBB.collateral(), userB, address(mainBB), collateralAmount);
        mainBB.approveCollateral(userA, collateralAmount);
        _addCollateral(collateralAmount, mainBB, userA, userB, userB);

        // **** Secondary BB market ****
        _resetPrank(userB);
        _approveViaERC20(secondaryBB.collateral(), userB, address(secondaryBB), collateralAmount);
        secondaryBB.approveCollateral(userA, collateralAmount);
        _addCollateral(collateralAmount, secondaryBB, userA, userB, userB);
    }
}
