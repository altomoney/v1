// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {AltoLeverageSwapperV1} from "@alto/lending/leverage/AltoLeverageSwapperV1.sol";
import {IAltoLeverageSwapperV1Errors, SwapParamsV1} from "@alto/lending/leverage/interfaces/IAltoLeverageSwapper.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract AltoLeverageSwapperV1Test is Test {
    event SetWhitelisted(address indexed contractAddress, bool isWhitelisted);
    event SetValidSwapTarget(address indexed swapTarget, bool isValid);

    AltoLeverageSwapperV1 internal swapper;

    address internal constant PENDLE_ROUTER_V4 = 0x888888888889758F76e7103c6CbF23ABbF58F946;
    address internal constant OPEN_OCEAN_ROUTER = 0x6352a56caadC4F1E25CD6c75970Fa768A3304e64;
    address internal constant ENSO_ROUTER = 0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf;

    string internal constant SWAP_DATA_DIR = "test/lending/leverage/0xswapData/pt-reusd-25June-2026/aggregators/";

    address internal constant PT_REUSD = 0x3EAA0F0f0A5d3D595ae4e4b0D27f439d01c3E7b2;
    address internal constant DUSD = 0x63d74d22E689C715a04F2C13962b1f77F443d35b;

    // PT-reUSD has 6 decimals; DUSD has 18 decimals
    uint256 internal constant PT_REUSD_AMOUNT_IN = 100_000 * 1e6;
    uint256 internal constant DUSD_AMOUNT_IN = 100_000 ether;
    uint256 internal constant DUSD_MIN_AMOUNT_OUT = 98_000 ether;
    uint256 internal constant PT_REUSD_MIN_AMOUNT_OUT = 100_000 * 1e6;

    address internal caller = address(0xBEEF);

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("ethereum"), 24984279);

        address[] memory validSwapTargets = new address[](3);
        validSwapTargets[0] = PENDLE_ROUTER_V4;
        validSwapTargets[1] = OPEN_OCEAN_ROUTER;
        validSwapTargets[2] = ENSO_ROUTER;

        swapper = new AltoLeverageSwapperV1(address(this), validSwapTargets);
        swapper.setWhitelisted(caller, true);
    }

    function test_reverts_when_swap_target_not_allowed() public {
        address notAllowed = address(0x2222222222222222222222222222222222222222);
        bytes memory swapParams = abi.encode(SwapParamsV1({minAmountOut: 0, swapTarget: notAllowed, swapData: hex""}));

        vm.expectRevert(
            abi.encodeWithSelector(
                IAltoLeverageSwapperV1Errors.AltoLeverageSwapperInvalidSwapTarget.selector, notAllowed
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

    function test_swap_pendleOdos_ptreusd_to_dusd() public {
        _executeSwapAndAssert(
            PENDLE_ROUTER_V4, _loadSwapData("pendleOdos-100000-ptresud-to-dusd.json", ".routes[0].tx.data")
        );
    }

    function test_swap_pendleKyberswap_ptreusd_to_dusd() public {
        _executeSwapAndAssert(
            PENDLE_ROUTER_V4, _loadSwapData("pendleKyberswap-100000-ptresud-to-dusd.json", ".routes[0].tx.data")
        );
    }

    function test_swap_pendleOkx_ptreusd_to_dusd() public {
        _executeSwapAndAssert(
            PENDLE_ROUTER_V4, _loadSwapData("pendleOkx-100000-ptresud-to-dusd.json", ".routes[0].tx.data")
        );
    }

    function test_swap_pendleVelora_ptreusd_to_dusd() public {
        _executeSwapAndAssert(
            PENDLE_ROUTER_V4, _loadSwapData("pendleVelora-100000-ptresud-to-dusd.json", ".routes[0].tx.data")
        );
    }

    function test_swap_openOcean_ptreusd_to_dusd() public {
        _executeSwapAndAssert(OPEN_OCEAN_ROUTER, _loadSwapData("openocean-100000-ptresud-to-dusd.json", ".data.data"));
    }

    function test_swap_enso_ptreusd_to_dusd() public {
        _executeSwapAndAssert(ENSO_ROUTER, _loadSwapData("enso-100000-ptresud-to-dusd.json", ".tx.data"));
    }

    // ─── DUSD → PT-reUSD ───────────────────────────────────────────────────────

    function test_swap_pendleOdos_dusd_to_ptreusd() public {
        _executeSwapAndAssertReverse(
            PENDLE_ROUTER_V4, _loadSwapData("pendleOdos-100000-dusd-to-ptreusd.json", ".routes[0].tx.data")
        );
    }

    function test_swap_pendleKyberswap_dusd_to_ptreusd() public {
        _executeSwapAndAssertReverse(
            PENDLE_ROUTER_V4, _loadSwapData("pendleKyberswap-100000-dusd-to-ptreusd.json", ".routes[0].tx.data")
        );
    }

    function test_swap_pendleOkx_dusd_to_ptreusd() public {
        _executeSwapAndAssertReverse(
            PENDLE_ROUTER_V4, _loadSwapData("pendleOkx-100000-dusd-to-ptreusd.json", ".routes[0].tx.data")
        );
    }

    // @dev This test fails due to incorrect swap data from pendle + velora API
    //      PT-reUSD -> DUSD works but DUSD -> PT-reUSD doesn't
    // function test_swap_pendleVelora_dusd_to_ptreusd() public {
    //     _executeSwapAndAssertReverse(
    //         PENDLE_ROUTER_V4, _loadSwapData("pendleVelora-100000-dusd-to-ptreusd.json", ".routes[0].tx.data")
    //     );
    // }

    function test_swap_openOcean_dusd_to_ptreusd() public {
        _executeSwapAndAssertReverse(
            OPEN_OCEAN_ROUTER, _loadSwapData("openocean-100000-dusd-to-ptreusd.json", ".data.data")
        );
    }

    function test_swap_enso_dusd_to_ptreusd() public {
        _executeSwapAndAssertReverse(ENSO_ROUTER, _loadSwapData("enso-100000-dusd-to-ptreusd.json", ".tx.data"));
    }

    function _loadSwapData(string memory fileName, string memory path) internal view returns (bytes memory swapData) {
        string memory json = vm.readFile(string.concat(SWAP_DATA_DIR, fileName));
        swapData = vm.parseJsonBytes(json, path);
    }

    function _executeSwapAndAssert(
        address sellToken,
        address buyToken,
        uint256 amountIn,
        uint256 minAmountOut,
        address swapTarget,
        bytes memory swapData
    ) internal {
        deal(sellToken, caller, amountIn);
        vm.prank(caller);
        IERC20(sellToken).approve(address(swapper), amountIn);

        bytes memory swapParams =
            abi.encode(SwapParamsV1({minAmountOut: minAmountOut, swapTarget: swapTarget, swapData: swapData}));

        uint256 buyTokenBalanceBefore = IERC20(buyToken).balanceOf(caller);
        vm.prank(caller);
        uint256 buyTokenBalanceReceived = swapper.swap(sellToken, buyToken, amountIn, swapParams);
        uint256 buyTokenBalanceAfter = IERC20(buyToken).balanceOf(caller);

        assertGt(buyTokenBalanceReceived, minAmountOut, "buyTokenBalanceReceived should exceed minAmountOut");
        assertGt(buyTokenBalanceAfter, minAmountOut, "caller final balance should exceed minAmountOut");
        assertEq(
            buyTokenBalanceReceived,
            buyTokenBalanceAfter - buyTokenBalanceBefore,
            "buyTokenBalanceReceived should equal caller's balance increase"
        );
    }

    function _executeSwapAndAssert(address swapTarget, bytes memory swapData) internal {
        _executeSwapAndAssert(PT_REUSD, DUSD, PT_REUSD_AMOUNT_IN, DUSD_MIN_AMOUNT_OUT, swapTarget, swapData);
    }

    function _executeSwapAndAssertReverse(address swapTarget, bytes memory swapData) internal {
        _executeSwapAndAssert(DUSD, PT_REUSD, DUSD_AMOUNT_IN, PT_REUSD_MIN_AMOUNT_OUT, swapTarget, swapData);
    }
}
