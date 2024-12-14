// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// Tapioca
import {TOFTVault} from "tapiocaz/tOFT/TOFTVault.sol";
import {BaseTOFT} from "tapiocaz/tOFT/BaseTOFT.sol";
import {mTOFT} from "tapiocaz/tOFT/mTOFT.sol";
import {TOFT} from "tapiocaz/tOFT/TOFT.sol";

// tests
import {Base_Test} from "../../Base_Test.t.sol";
import {ERC20Mock_test} from "../../mocks/ERC20Mock_test.sol";

abstract contract OFT_Unit_Shared is Base_Test {
    // ************* //
    // *** SETUP *** //
    // ************* //
    function setUp() public virtual override {
        super.setUp();
    }

    // ***************** //
    // *** MODIFIERS *** //
    // ***************** //
    modifier whenPaused() {
        toft.setPause(true);
        mToft.setPause(true);
        _;
    }

    // *************** //
    // *** HELPERS *** //
    // *************** //
    function _wrapOft(uint256 amount, address token, address payable oft)
        internal
        // TODO Review it whenApprovedViaERC20(token, address(this), type(uint256).max)
    {
        __wrap(amount, token, oft);
    }

    function __wrap(uint256 amount, address token, address payable oft) private {
        {
            ERC20Mock_test(token).mint(address(this), amount);
        }
        TOFT(oft).wrap(address(this), address(this), amount);
    }
}
