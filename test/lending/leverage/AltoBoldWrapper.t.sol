// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {AltoBoldWrapper} from "@alto/lending/leverage/helper/AltoBoldWrapper.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract AltoBoldWrapperTest is Test {
    address constant SBOLD = 0x50Bd66D59911F5e086Ec87aE43C811e0D059DD11;
    address constant BOLD = 0x6440f144b7e50D6a8439336510312d2F54beB01D;
    address alice = makeAddr("alice");
    uint256 constant INITIAL_AMOUNT = 100_000 ether;

    AltoBoldWrapper boldWrapper;

    function setUp() public {
        string memory rpcUrl = vm.rpcUrl("ethereum");
        vm.createSelectFork(rpcUrl, 23574759);

        boldWrapper = new AltoBoldWrapper(SBOLD);

        deal(BOLD, alice, INITIAL_AMOUNT);
    }

    function testDeploymentSuccess() public view {
        assertEq(boldWrapper.WRAPPED_TOKEN(), SBOLD, "Wrapped token address doesn't match with SBOLD");
        assertEq(boldWrapper.BASE_TOKEN(), BOLD, "Base token address doesn't match with BOLD");
    }

    function testWrap() public {
        vm.startPrank(alice);

        uint256 expectedSBoldAmount = IERC4626(SBOLD).previewDeposit(INITIAL_AMOUNT);

        IERC20(BOLD).approve(address(boldWrapper), INITIAL_AMOUNT);
        boldWrapper.wrap(INITIAL_AMOUNT, alice);

        console2.log("SBOLD received by alice is", IERC20(SBOLD).balanceOf(alice));

        assertEq(IERC20(BOLD).balanceOf(address(boldWrapper)), 0, "BOLD balance of bold wrapper should be 0");
        assertEq(IERC20(SBOLD).balanceOf(address(boldWrapper)), 0, "SBOLD balance of bold wrapper should be 0");

        assertGt(IERC20(SBOLD).balanceOf(alice), 0, "SBOLD balance of alice should be greater than 0");
        assertEq(
            IERC20(SBOLD).balanceOf(alice), expectedSBoldAmount, "SBOLD balance of alice should match expected amount"
        );
        vm.stopPrank();
    }

    function testUnwrap() public {
        testWrap();

        uint256 sBoldBalanceOfAlice = IERC20(SBOLD).balanceOf(alice);

        vm.startPrank(alice);
        IERC20(SBOLD).approve(address(boldWrapper), sBoldBalanceOfAlice);
        boldWrapper.unwrap(sBoldBalanceOfAlice, alice);
        vm.stopPrank();

        assertEq(IERC20(BOLD).balanceOf(address(boldWrapper)), 0, "BOLD balance of bold wrapper should be 0");
        assertEq(IERC20(SBOLD).balanceOf(address(boldWrapper)), 0, "SBOLD balance of bold wrapper should be 0");

        assertEq(IERC20(SBOLD).balanceOf(alice), 0, "SBOLD balance of alice should be 0");
        assertApproxEqRel(
            IERC20(BOLD).balanceOf(alice),
            INITIAL_AMOUNT,
            1e14,
            "BOLD balance of alice should almost match initial amount"
        );
    }
}
