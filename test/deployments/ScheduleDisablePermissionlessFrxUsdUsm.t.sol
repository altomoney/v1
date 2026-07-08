// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";
import {IUsm} from "@alto/usm/interfaces/IUsm.sol";
import {USDC_MAINNET, FRXUSD_MAINNET} from "@alto/deployments/ethereum-mainnet/Constants.sol";
import {
    TreasuryZeroPermissionlessFrxUsdUsmExposureScript,
    ZeroExposureParams
} from "../../script/TreasuryZeroPermissionlessFrxUsdUsmExposure.s.sol";

contract ScheduleDisablePermissionlessFrxUsdUsmTest is Test {
    address constant TIMELOCK = 0xfAe841679dc1A93D225ECc827E4BbF3e8d703F86;
    address constant TIMELOCK_ADMIN = 0xc49bf619CC9A68F84A6C9aB88506F2627565a4D0;
    address constant TREASURY_MULTISIG = 0xA1148A1b94262540994Cf9Aa431A13ad39764228;
    address constant PERMISSIONLESS_FRXUSD_USM = 0x7b9468fB9f3146ec82ceB2Dd75e6a47F3EAd5f79;
    address constant PERMISSIONED_FRXUSD_USM = 0x1BD08B43D1579881cfAd0A35AEEa5b547dBE4c91;
    address constant FRAX_CUSTODIAN = 0x4F95C5bA0C7c69FB2f9340E190cCeE890B3bd87c;
    address constant DUSD = 0x63d74d22E689C715a04F2C13962b1f77F443d35b;

    TreasuryZeroPermissionlessFrxUsdUsmExposureScript internal script;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("ethereum"));
        script = new TreasuryZeroPermissionlessFrxUsdUsmExposureScript();
    }

    function test_disablePermissionlessFrxUsdUsm() public {
        uint256 delay = TimelockController(payable(TIMELOCK)).getMinDelay();

        address[] memory targets = new address[](3);
        uint256[] memory values = new uint256[](3);
        bytes[] memory payloads = new bytes[](3);

        targets[0] = DUSD;
        values[0] = 0;
        payloads[0] = abi.encodeCall(IDUSD.setMinterCeiling, (PERMISSIONLESS_FRXUSD_USM, 0));

        targets[1] = DUSD;
        values[1] = 0;
        payloads[1] = abi.encodeCall(IDUSD.setMinterStatus, (PERMISSIONLESS_FRXUSD_USM, false));

        targets[2] = PERMISSIONLESS_FRXUSD_USM;
        values[2] = 0;
        payloads[2] = abi.encodeCall(IUsm.updateExposureCap, (uint128(0)));

        vm.prank(TIMELOCK_ADMIN);
        TimelockController(payable(TIMELOCK)).scheduleBatch(
            targets, values, payloads, bytes32(0), bytes32(0), delay
        );

        vm.warp(block.timestamp + delay + 1);

        vm.prank(TIMELOCK_ADMIN);
        TimelockController(payable(TIMELOCK)).executeBatch(
            targets, values, payloads, bytes32(0), bytes32(0)
        );

        assertEq(IUsm(PERMISSIONLESS_FRXUSD_USM).getExposureCap(), 0, "exposure cap should be 0");

        (uint256 minted, uint256 ceiling) = IDUSD(DUSD).minterConfig(PERMISSIONLESS_FRXUSD_USM);
        assertEq(ceiling, 0, "minter ceiling should be 0");
        assertFalse(IDUSD(DUSD).allowedMinter(PERMISSIONLESS_FRXUSD_USM), "minter status should be false");
        assertGt(minted, 0, "minted amount unchanged after shutdown");
    }

    function test_zeroPermissionlessFrxUsdUsmExposure() public {
        test_disablePermissionlessFrxUsdUsm();

        ZeroExposureParams memory params = script.computeParams();
        assertGt(params.frxUsdExposure, 0, "permissionless USM should have exposure");
        assertGt(params.dusdNeeded, params.frxUsdExposure, "DUSD needed should exceed frxUSD due to fees");
        assertGe(
            IERC20(USDC_MAINNET).balanceOf(TREASURY_MULTISIG),
            params.usdcNeeded,
            "insufficient treasury USDC"
        );

        uint256 exposureBefore = IUsm(PERMISSIONLESS_FRXUSD_USM).getAvailableLiquidity();
        assertEq(exposureBefore, params.frxUsdExposure, "unexpected starting exposure");

        uint256 frxUsdBalBefore = IERC20(FRXUSD_MAINNET).balanceOf(TREASURY_MULTISIG);

        vm.startPrank(TREASURY_MULTISIG);

        IERC20(USDC_MAINNET).approve(FRAX_CUSTODIAN, params.usdcNeeded);
        uint256 usdcSpent = IERC4626(FRAX_CUSTODIAN).mint(params.frxUsdSellAmount, TREASURY_MULTISIG);
        assertEq(usdcSpent, params.usdcNeeded, "USDC spent mismatch");

        IERC20(FRXUSD_MAINNET).approve(PERMISSIONED_FRXUSD_USM, params.frxUsdSellAmount);
        (uint256 frxUsdSold, uint256 dusdReceived) =
            IUsm(PERMISSIONED_FRXUSD_USM).sellAsset(params.frxUsdSellAmount, TREASURY_MULTISIG);
        assertEq(frxUsdSold, params.frxUsdSellAmount, "frxUSD sold mismatch");
        assertEq(dusdReceived, params.dusdNeeded, "DUSD received should match fee-inclusive quote");

        IERC20(DUSD).approve(PERMISSIONLESS_FRXUSD_USM, params.dusdNeeded);
        (uint256 frxUsdBought, uint256 dusdSpent) =
            IUsm(PERMISSIONLESS_FRXUSD_USM).buyAsset(params.frxUsdExposure, TREASURY_MULTISIG);
        assertEq(frxUsdBought, params.frxUsdExposure, "frxUSD bought mismatch");
        assertEq(dusdSpent, params.dusdNeeded, "DUSD spent should match fee-inclusive quote");

        vm.stopPrank();

        assertEq(IUsm(PERMISSIONLESS_FRXUSD_USM).getAvailableLiquidity(), 0, "exposure should be zero");
        assertEq(
            IERC20(FRXUSD_MAINNET).balanceOf(PERMISSIONLESS_FRXUSD_USM),
            0,
            "permissionless USM frxUSD balance should be zero"
        );
        assertEq(
            IERC20(FRXUSD_MAINNET).balanceOf(TREASURY_MULTISIG) - frxUsdBalBefore,
            exposureBefore,
            "treasury should receive all frxUSD from permissionless USM"
        );
    }
}
