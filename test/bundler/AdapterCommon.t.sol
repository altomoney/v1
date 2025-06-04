// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

import {AltoAdapter} from "@alto-monorepo/bundler/AltoAdapter.sol";
import {Test} from "forge-std/Test.sol";
import {OracleMock} from "@alto-monorepo/lending/mocks/OracleMock.sol";
import {IMarket} from "@alto-monorepo/lending/interfaces/IMarket.sol";
import {Authorization, Signature} from "@alto-monorepo/utils/interfaces/common/IAuth.sol";
import {Bundler3, Call} from "@morpho-org/bundler3/Bundler3.sol";
import {CoreAdapter} from "@morpho-org/bundler3/adapters/CoreAdapter.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {ORACLE_PRICE_PRECISION} from "@alto-monorepo/lending/interfaces/IOracle.sol";
import {SigUtils, Permit} from "../helpers/SigUtils.sol";
import {MarketInstance} from "./MarketInstance.sol";

import {AssetShareConversionMath} from "@alto-monorepo/lending/libraries/AssetShareConversionMath.sol";
import {FixedPointMath} from "@alto-monorepo/lending/libraries/FixedPointMath.sol";

uint256 constant MIN_AMOUNT = 1000;
uint256 constant MAX_AMOUNT = 2 ** 64; // Must be less than or equal to type(uint160).max.
uint256 constant SIGNATURE_DEADLINE = type(uint32).max;

abstract contract AdapterCommon is Test {
    using FixedPointMath for uint256;
    using AssetShareConversionMath for uint256;

    address internal immutable USER = makeAddr("User");
    address internal immutable SUPPLIER = makeAddr("Supplier");
    address internal immutable OWNER = makeAddr("Owner");
    address internal immutable RECEIVER = makeAddr("Receiver");
    address internal immutable LIQUIDATOR = makeAddr("Liquidator");

    OracleMock internal oracle;

    Bundler3 internal bundler3;
    AltoAdapter internal altoAdapter;

    Call[] internal bundle;
    Call[] internal callbackBundle;

    function setUp() public virtual {
        bundler3 = new Bundler3();
        altoAdapter = new AltoAdapter(address(bundler3), address(1));
        oracle = new OracleMock();
        oracle.setPrice(ORACLE_PRICE_PRECISION);
    }

    function _boundPrivateKey(uint256 privateKey) internal returns (uint256) {
        privateKey = bound(privateKey, 1, type(uint160).max);

        address user = vm.addr(privateKey);
        vm.label(user, "address of generated private key");

        return privateKey;
    }

    /* GENERAL ADAPTER CALL */
    function _call(CoreAdapter to, bytes memory data) internal pure returns (Call memory) {
        return _call(address(to), data, 0, false, hex"");
    }

    function _call(address to, bytes memory data) internal pure returns (Call memory) {
        return _call(to, data, 0, false, hex"");
    }

    function _call(CoreAdapter to, bytes memory data, uint256 value) internal pure returns (Call memory) {
        return _call(address(to), data, value, false, hex"");
    }

    function _call(address to, bytes memory data, uint256 value) internal pure returns (Call memory) {
        return _call(to, data, value, false, hex"");
    }

    function _call(CoreAdapter to, bytes memory data, bool skipRevert) internal pure returns (Call memory) {
        return _call(address(to), data, 0, skipRevert, hex"");
    }

    function _call(address to, bytes memory data, bool skipRevert) internal pure returns (Call memory) {
        return _call(to, data, 0, skipRevert, hex"");
    }

    function _call(CoreAdapter to, bytes memory data, bytes32 callbackHash) internal pure returns (Call memory) {
        return _call(address(to), data, 0, false, callbackHash);
    }

    function _call(CoreAdapter to, bytes memory data, uint256 value, bool skipRevert, bytes32 callbackHash)
        internal
        pure
        returns (Call memory)
    {
        return _call(address(to), data, value, skipRevert, callbackHash);
    }

    function _call(CoreAdapter to, bytes memory data, uint256 value, bool skipRevert)
        internal
        pure
        returns (Call memory)
    {
        return _call(address(to), data, value, skipRevert, hex"");
    }

    function _call(address to, bytes memory data, uint256 value, bool skipRevert) internal pure returns (Call memory) {
        return _call(to, data, value, skipRevert, hex"");
    }

    function _call(address to, bytes memory data, uint256 value, bool skipRevert, bytes32 callbackHash)
        internal
        pure
        returns (Call memory)
    {
        require(to != address(0), "Adapter address is zero");
        return Call(to, data, value, skipRevert, callbackHash);
    }

    /* CALL WITH VALUE */

    function _transferNativeToAdapter(address adapter, uint256 amount) internal pure returns (Call memory) {
        return _call(adapter, hex"", amount);
    }

    /* TRANSFER */

    function _nativeTransfer(address recipient, uint256 amount, CoreAdapter adapter)
        internal
        pure
        returns (Call memory)
    {
        return _call(adapter, abi.encodeCall(adapter.nativeTransfer, (recipient, amount)));
    }

    function _nativeTransferNoFunding(address recipient, uint256 amount, CoreAdapter adapter)
        internal
        pure
        returns (Call memory)
    {
        return _call(adapter, abi.encodeCall(adapter.nativeTransfer, (recipient, amount)), uint256(0));
    }

    /* ERC20 ACTIONS */

    function _erc20Transfer(address token, address recipient, uint256 amount, CoreAdapter adapter)
        internal
        pure
        returns (Call memory)
    {
        return _call(adapter, abi.encodeCall(adapter.erc20Transfer, (token, recipient, amount)));
    }

    function _erc20TransferFrom(address token, address recipient, uint256 amount) internal view returns (Call memory) {
        return _call(altoAdapter, abi.encodeCall(AltoAdapter.erc20TransferFrom, (token, recipient, amount)));
    }

    function _erc20TransferFrom(address token, uint256 amount) internal view returns (Call memory) {
        return _erc20TransferFrom(token, address(altoAdapter), amount);
    }

    /* MARKET ACTIONS */

    function _marketSetAuthorizationWithSig(
        IMarket market,
        uint256 privateKey,
        bool isAuthorized,
        uint256 nonce,
        bool skipRevert
    ) internal view returns (Call memory) {
        address user = vm.addr(privateKey);

        Authorization memory authorization = Authorization({
            owner: user,
            spender: address(altoAdapter),
            isAuthorizedStatus: isAuthorized,
            nonce: nonce,
            deadline: SIGNATURE_DEADLINE
        });

        bytes32 digest = SigUtils.toTypedDataHash(
            MarketInstance(address(market)).authorizationTypeHash(),
            MarketInstance(address(market)).domainSeparator(),
            authorization
        );

        Signature memory signature;
        (signature.v, signature.r, signature.s) = vm.sign(privateKey, digest);

        return _call(
            address(market),
            abi.encodeCall(market.setAuthorizationWithSignature, (authorization, signature)),
            0,
            skipRevert
        );
    }

    function _marketAddSupply(
        IMarket market,
        uint256 assets,
        uint256 shares,
        uint256 maxSharePriceE27,
        address onBehalf
    ) internal view returns (Call memory) {
        return _call(
            altoAdapter,
            abi.encodeCall(AltoAdapter.marketAddSupply, (market, assets, shares, maxSharePriceE27, onBehalf)),
            bytes32(0)
        );
    }

    function _marketRemoveSupply(
        IMarket market,
        uint256 assets,
        uint256 shares,
        uint256 minSharePriceE27,
        address receiver
    ) internal view returns (Call memory) {
        return _call(
            altoAdapter,
            abi.encodeCall(AltoAdapter.marketRemoveSupply, (market, assets, shares, minSharePriceE27, receiver))
        );
    }

    function _marketAddCollateral(IMarket market, uint256 assets, address onBehalf)
        internal
        view
        returns (Call memory)
    {
        return
            _call(altoAdapter, abi.encodeCall(AltoAdapter.marketAddCollateral, (market, assets, onBehalf)), bytes32(0));
    }

    function _marketRemoveCollateral(IMarket market, uint256 assets, address receiver)
        internal
        view
        returns (Call memory)
    {
        return _call(
            altoAdapter, abi.encodeCall(AltoAdapter.marketRemoveCollateral, (market, assets, receiver)), bytes32(0)
        );
    }

    function _marketBorrow(IMarket market, uint256 assets, uint256 shares, uint256 minSharePriceE27, address receiver)
        internal
        view
        returns (Call memory)
    {
        return _call(
            altoAdapter, abi.encodeCall(AltoAdapter.marketBorrow, (market, assets, shares, minSharePriceE27, receiver))
        );
    }

    function _marketRepay(IMarket market, uint256 assets, uint256 shares, uint256 maxSharePriceE27, address onBehalf)
        internal
        view
        returns (Call memory)
    {
        return _call(
            altoAdapter,
            abi.encodeCall(AltoAdapter.marketRepay, (market, assets, shares, maxSharePriceE27, onBehalf)),
            bytes32(0)
        );
    }

    /* PERMIT ACTIONS */

    function _permit(
        IERC20Permit token,
        uint256 privateKey,
        address spender,
        uint256 amount,
        uint256 deadline,
        bool skipRevert
    ) internal view returns (Call memory) {
        address user = vm.addr(privateKey);

        Permit memory permit = Permit(user, spender, amount, token.nonces(user), deadline);

        bytes32 digest = SigUtils.toTypedDataHash(token.DOMAIN_SEPARATOR(), permit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        bytes memory callData = abi.encodeCall(IERC20Permit.permit, (user, spender, amount, deadline, v, r, s));
        return _call(address(token), callData, 0, skipRevert);
    }
}
