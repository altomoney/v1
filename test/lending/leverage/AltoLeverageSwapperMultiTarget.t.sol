// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {AltoLeverageSwapperMultiTarget} from "@alto/lending/leverage/AltoLeverageSwapperMultiTarget.sol";
import {
    IAltoLeverageSwapperMultiTargetErrors,
    SwapParamsMultiTarget
} from "@alto/lending/leverage/interfaces/IAltoLeverageSwapper.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract AltoLeverageSwapperMultiTargetTest is Test {
    event SetWhitelisted(address indexed contractAddress, bool isWhitelisted);
    event SetValidSwapTarget(address indexed swapTarget, bool isValid);

    AltoLeverageSwapperMultiTarget internal swapper;

    address internal constant PENDLE_ROUTER_V4 = 0x888888888889758F76e7103c6CbF23ABbF58F946;
    address internal constant OPEN_OCEAN_ROUTER = 0x6352a56caadC4F1E25CD6c75970Fa768A3304e64;
    address internal constant ENSO_ROUTER = 0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf;

    address internal caller = address(0xBEEF);

    function setUp() public {
        address[] memory validSwapTargets = new address[](3);
        validSwapTargets[0] = PENDLE_ROUTER_V4;
        validSwapTargets[1] = OPEN_OCEAN_ROUTER;
        validSwapTargets[2] = ENSO_ROUTER;

        swapper = new AltoLeverageSwapperMultiTarget(address(this), validSwapTargets);
        swapper.setWhitelisted(caller, true);
    }

    function test_reverts_when_swap_target_not_allowed() public {
        address notAllowed = address(0x2222222222222222222222222222222222222222);
        bytes memory swapParams =
            abi.encode(SwapParamsMultiTarget({minAmountOut: 0, swapTarget: notAllowed, swapData: hex""}));

        vm.expectRevert(
            abi.encodeWithSelector(
                IAltoLeverageSwapperMultiTargetErrors.AltoLeverageSwapperInvalidSwapTarget.selector, notAllowed
            )
        );
        vm.prank(caller);
        swapper.swap(address(1), address(2), 0, swapParams);
    }

    function test_revertWhen_setWhitelisted_onlyByOwner() public {
        address nonOwner = address(0xABCD);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        vm.prank(nonOwner);
        swapper.setWhitelisted(address(0xCAFE), true);
    }

    function test_revertWhen_setValidSwapTarget_onlyByOwner() public {
        address nonOwner = address(0xABCD);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        vm.prank(nonOwner);
        swapper.setValidSwapTarget(address(0xD00D), true);
    }

    function test_setWhitelisted_ownerCanSet() public {
        address account = address(0xCAFE);

        vm.expectEmit(true, false, false, true, address(swapper));
        emit SetWhitelisted(account, true);
        swapper.setWhitelisted(account, true);
        assertTrue(swapper.isWhitelisted(account), "owner should be able to whitelist account");

        vm.expectEmit(true, false, false, true, address(swapper));
        emit SetWhitelisted(account, false);
        swapper.setWhitelisted(account, false);
        assertFalse(swapper.isWhitelisted(account), "owner should be able to remove whitelist");
    }

    function test_setValidSwapTarget_ownerCanSet() public {
        address swapTarget = address(0xD00D);

        vm.expectEmit(true, false, false, true, address(swapper));
        emit SetValidSwapTarget(swapTarget, true);
        swapper.setValidSwapTarget(swapTarget, true);
        assertTrue(swapper.isValidSwapTarget(swapTarget), "owner should be able to add valid swap target");

        vm.expectEmit(true, false, false, true, address(swapper));
        emit SetValidSwapTarget(swapTarget, false);
        swapper.setValidSwapTarget(swapTarget, false);
        assertFalse(swapper.isValidSwapTarget(swapTarget), "owner should be able to remove valid swap target");
    }
}
