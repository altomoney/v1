// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {DUSD} from "@alto/tokens/DUSD.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";
import {IPausable} from "@alto/utils/Pausable.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import {ERC3156FlashBorrowerMock} from "@openzeppelin/contracts/mocks/ERC3156FlashBorrowerMock.sol";

contract DUSDCommon is Test, TestHelperOz5 {
    address constant OWNER = address(0x1);
    address constant NON_OWNER = address(0x2);
    address constant MINTER = address(0x3);
    address constant BURNER = address(0x4);
    address constant USER = address(0x5);
    address constant FLASH_FEE_RECEIVER = address(0x6);
    address constant NON_BURNER = address(0x7);
    address constant NON_MINTER = address(0x8);
    address constant NEW_OWNER = address(0x9);
    address constant ANOTHER_OWNER = address(0xa);

    DUSD dusd;
    ERC3156FlashBorrowerMock flashBorrower;

    uint256 constant DEFAULT_FLASH_FEE = 1000; // 0.1%
    uint256 constant MINT_AMOUNT = 1000e18;
    uint256 constant BURN_AMOUNT = 500e18;

    event SetMinterStatus(address indexed _for, bool _status);
    event SetBurnerStatus(address indexed _for, bool _status);
    event SetFlashFeeReceiver(address indexed _oldFeeReceiver, address indexed _newFeeReceiver);
    event SetFlashFee(uint256 indexed _oldFee, uint256 indexed _newFee);

    function setUp() public virtual override {
        super.setUp();
        setUpEndpoints(1, LibraryType.UltraLightNode);

        vm.startPrank(OWNER);
        dusd = new DUSD(address(endpoints[1]), OWNER);
        vm.stopPrank();

        flashBorrower = new ERC3156FlashBorrowerMock(true, true);
    }

    function _setupMinter() internal {
        vm.startPrank(OWNER);
        dusd.setMinterStatus(MINTER, true);
        dusd.setMinterCeiling(MINTER, MINT_AMOUNT);
        vm.stopPrank();
    }

    function _setupBurner() internal {
        vm.prank(OWNER);
        dusd.setBurnerStatus(BURNER, true);
    }

    function _mintTokensToUser(uint256 amount) internal {
        _setupMinter();
        vm.prank(MINTER);
        dusd.mint(USER, amount);
    }

    function _pauseContract() internal {
        vm.prank(OWNER);
        dusd.pause(PAUSE_TYPE, true);
    }

    function _unpauseContract() internal {
        vm.prank(OWNER);
        dusd.pause(PAUSE_TYPE, false);
    }
}
