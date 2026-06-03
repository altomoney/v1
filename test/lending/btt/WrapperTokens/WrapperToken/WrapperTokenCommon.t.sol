// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {FixedPointMath} from "@alto/utils/FixedPointMath.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {
    IWrapperTokenErrors,
    IWrapperTokenEvents,
    SwapTargetMetadata
} from "@alto/lending/wrappedToken/IWrapperToken.sol";
import {WrapperTokenHarness} from "./mocks/WrapperTokenHarness.sol";
import {SwapTargetMock} from "./mocks/SwapTargetMock.sol";
import {ERC20MockMintableDecimals} from "@alto-test/helpers/ERC20MockMintableDecimals.sol";

abstract contract WrapperTokenCommon is Test {
    using FixedPointMath for uint256;

    string internal constant WRAPPER_NAME = "Wrapped PT";
    string internal constant WRAPPER_SYMBOL = "wPT";
    uint8 internal constant TOKEN_DECIMALS = 18;

    address internal owner;
    address internal user;
    address internal nonOwner;
    address internal pauser;
    address internal rollOverBot;

    ERC20MockMintableDecimals internal underlyingPt;
    WrapperTokenHarness internal wrapper;

    function setUp() public virtual {
        owner = makeAddr("owner");
        user = makeAddr("user");
        nonOwner = makeAddr("nonOwner");
        pauser = makeAddr("pauser");
        rollOverBot = makeAddr("rollOverBot");

        underlyingPt = new ERC20MockMintableDecimals("PT", "PT", TOKEN_DECIMALS);
        wrapper = new WrapperTokenHarness(WRAPPER_NAME, WRAPPER_SYMBOL, address(underlyingPt), owner, rollOverBot);

        vm.prank(owner);
        wrapper.setPauser(pauser, PAUSE_TYPE, true);
    }

    function _tenPowDecimals() internal pure returns (uint256) {
        return 10 ** TOKEN_DECIMALS;
    }

    function _expectedWrappedAmount(uint256 ptAmount, uint256 exchangeRate) internal pure returns (uint256) {
        return ptAmount.divideWithRounding(_tenPowDecimals(), exchangeRate, false);
    }

    function _expectedPtAmount(uint256 wrappedAmount, uint256 exchangeRate) internal pure returns (uint256) {
        return wrappedAmount.divideWithRounding(exchangeRate, _tenPowDecimals(), false);
    }

    function _fundUserPt(address account, uint256 amount) internal {
        underlyingPt.mint(account, amount);
    }

    function _approveWrapper(address account, uint256 amount) internal {
        vm.prank(account);
        underlyingPt.approve(address(wrapper), amount);
    }

    function _fundAndApproveUser(uint256 ptAmount) internal {
        _fundUserPt(user, ptAmount);
        _approveWrapper(user, ptAmount);
    }

    function _mintUnderlyingToWrapper(uint256 amount) internal {
        underlyingPt.mint(address(wrapper), amount);
    }

    function _pauseWrapper() internal {
        vm.prank(pauser);
        wrapper.pause(PAUSE_TYPE, true);
    }

    function _unpauseWrapper() internal {
        vm.prank(pauser);
        wrapper.pause(PAUSE_TYPE, false);
    }

    function _whitelistSwapTarget(SwapTargetMock swapTarget) internal {
        vm.prank(owner);
        wrapper.setSwapTargetToApproveTarget(
            address(swapTarget), SwapTargetMetadata({approveTarget: address(swapTarget), isValid: true})
        );
    }

    function _buildSwapData(
        address,
        /* swapTarget */
        address sellToken,
        address buyToken,
        uint256 amountIn,
        uint256 buyAmountOut
    )
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeCall(SwapTargetMock.executeSwap, (sellToken, buyToken, amountIn, buyAmountOut));
    }
}
