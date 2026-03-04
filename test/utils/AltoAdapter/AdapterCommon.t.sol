// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {AltoAdapter} from "@alto/utils/AltoAdapter.sol";
import {Test} from "forge-std/Test.sol";
import {OracleMock} from "@alto/oracles/mocks/OracleMock.sol";
import {IMarket} from "@alto/lending/interfaces/IMarket.sol";
import {IRewardsDistributor, ClaimData} from "@alto/rewards/interfaces/IRewardsDistributor.sol";
import {IAltoStaking} from "@alto/staking/interfaces/IAltoStaking.sol";
import {Authorization, Signature} from "@alto/utils/interfaces/IAuth.sol";
import {Bundler3, Call} from "@morpho-org/bundler3/Bundler3.sol";
import {CoreAdapter} from "@morpho-org/bundler3/adapters/CoreAdapter.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {UniversalRewardsDistributorInstance} from "./UniversalRewardsDistributorInstance.sol";

import {LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {SigUtils, Permit} from "@alto-test/helpers/SigUtils.sol";
import {MarketInstance} from "./MarketInstance.sol";
import {RewardsDistributorInstance} from "./RewardsDistributorInstance.sol";
import {StakingInstance} from "./StakingInstance.sol";
import {VestingInstance} from "./VestingInstance.sol";
import {DUSDUsmInstance} from "./DUSDUsmInstance.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";
import {FixedPointMath} from "@alto/utils/FixedPointMath.sol";
import {IUniversalRewardsDistributor} from "@alto/utils/interfaces/IUniversalRewardsDistributor.sol";
import {IAltoVesting, VestingInfo} from "@alto/vesting/interfaces/IAltoVesting.sol";
import {IUsm} from "@alto/usm/interfaces/IUsm.sol";
import {IAuth} from "@alto/utils/interfaces/IAuth.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

// Mock WETH contract for testing
contract WETHMock {
    string public name = "Wrapped Ether";
    string public symbol = "WETH";
    uint8 public decimals = 18;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    uint256 public totalSupply;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Deposit(address indexed dst, uint256 wad);
    event Withdrawal(address indexed src, uint256 wad);

    receive() external payable {
        deposit();
    }

    function deposit() public payable {
        balanceOf[msg.sender] += msg.value;
        totalSupply += msg.value;
        emit Deposit(msg.sender, msg.value);
        emit Transfer(address(0), msg.sender, msg.value);
    }

    function withdraw(uint256 wad) public {
        require(balanceOf[msg.sender] >= wad, "insufficient balance");
        balanceOf[msg.sender] -= wad;
        totalSupply -= wad;
        payable(msg.sender).transfer(wad);
        emit Withdrawal(msg.sender, wad);
        emit Transfer(msg.sender, address(0), wad);
    }

    function transfer(address to, uint256 value) public returns (bool) {
        require(balanceOf[msg.sender] >= value, "insufficient balance");
        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;
        emit Transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) public returns (bool) {
        require(balanceOf[from] >= value, "insufficient balance");
        require(allowance[from][msg.sender] >= value, "insufficient allowance");

        balanceOf[from] -= value;
        balanceOf[to] += value;

        if (allowance[from][msg.sender] != type(uint256).max) {
            allowance[from][msg.sender] -= value;
        }

        emit Transfer(from, to, value);
        return true;
    }

    function approve(address spender, uint256 value) public returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }
}

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
    WETHMock internal weth;

    Bundler3 internal bundler3;
    AltoAdapter internal altoAdapter;

    Call[] internal bundle;
    Call[] internal callbackBundle;

    function setUp() public virtual {
        bundler3 = new Bundler3();
        weth = new WETHMock();
        altoAdapter = new AltoAdapter(address(bundler3), address(weth), OWNER);
        oracle = new OracleMock();
        oracle.setPrice(LENDING_ORACLE_PRICE_PRECISION);
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

    function _erc20TransferFrom(address token, address recipient, uint256 amount)
        internal
        view
        virtual
        returns (Call memory)
    {
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
    ) internal view virtual returns (Call memory) {
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
    ) internal view virtual returns (Call memory) {
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
        return _call(
            altoAdapter, abi.encodeCall(AltoAdapter.marketAddCollateral, (market, assets, onBehalf)), bytes32(0)
        );
    }

    function _marketRemoveCollateral(IMarket market, uint256 assets, address receiver, bytes memory data)
        internal
        view
        returns (Call memory)
    {
        return _call(
            altoAdapter,
            abi.encodeCall(AltoAdapter.marketRemoveCollateral, (market, assets, receiver, data)),
            bytes32(0)
        );
    }

    function _marketBorrow(
        IMarket market,
        uint256 assets,
        uint256 shares,
        uint256 minSharePriceE27,
        address receiver,
        bytes memory data
    ) internal view returns (Call memory) {
        return _call(
            altoAdapter,
            abi.encodeCall(AltoAdapter.marketBorrow, (market, assets, shares, minSharePriceE27, receiver, data)),
            bytes32(0)
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

    /* REWARDS DISTRIBUTOR ACTIONS */

    function _rewardsDistributorSetAuthorizationWithSig(
        IRewardsDistributor rewardsDistributor,
        uint256 privateKey,
        bool isAuthorized,
        uint256 nonce,
        bool skipRevert,
        address spender
    ) internal view returns (Call memory) {
        address user = vm.addr(privateKey);

        Authorization memory authorization = Authorization({
            owner: user, spender: spender, isAuthorizedStatus: isAuthorized, nonce: nonce, deadline: SIGNATURE_DEADLINE
        });

        bytes32 digest = SigUtils.toTypedDataHash(
            RewardsDistributorInstance(address(rewardsDistributor)).authorizationTypeHash(),
            RewardsDistributorInstance(address(rewardsDistributor)).domainSeparator(),
            authorization
        );

        Signature memory signature;
        (signature.v, signature.r, signature.s) = vm.sign(privateKey, digest);

        return _call(
            address(rewardsDistributor),
            abi.encodeCall(rewardsDistributor.setAuthorizationWithSignature, (authorization, signature)),
            0,
            skipRevert
        );
    }

    function _rewardsDistributorClaimRewardTokensWithERC20Transfer(
        IRewardsDistributor rewardsDistributor,
        uint256 totalRewardsForUser,
        bytes32[] memory proof,
        uint256 rewardsPurchaseAmount,
        uint256 discount,
        uint256 id,
        uint256 expirationTimestamp,
        address paymentToken,
        uint256 paymentAmount,
        bool lockPurchasedRewards,
        uint256 maxEpochsToLockFor
    ) internal view returns (Call memory) {
        ClaimData memory claimData = ClaimData({
            totalRewardsForUser: totalRewardsForUser,
            discount: discount,
            id: id,
            expirationTimestamp: expirationTimestamp
        });
        return _call(
            altoAdapter,
            abi.encodeCall(
                AltoAdapter.rewardsDistributorClaimRewardTokensWithERC20Transfer,
                (
                    rewardsDistributor,
                    claimData,
                    proof,
                    rewardsPurchaseAmount,
                    paymentToken,
                    paymentAmount,
                    lockPurchasedRewards,
                    maxEpochsToLockFor
                )
            ),
            bytes32(0)
        );
    }

    /* STAKING ACTIONS */

    function _stakingSetAuthorizationWithSig(
        IAltoStaking staking,
        uint256 privateKey,
        bool isAuthorized,
        uint256 nonce,
        bool skipRevert,
        address spender
    ) internal view returns (Call memory) {
        address user = vm.addr(privateKey);

        Authorization memory authorization = Authorization({
            owner: user, spender: spender, isAuthorizedStatus: isAuthorized, nonce: nonce, deadline: SIGNATURE_DEADLINE
        });

        bytes32 digest = SigUtils.toTypedDataHash(
            StakingInstance(address(staking)).authorizationTypeHash(),
            StakingInstance(address(staking)).domainSeparator(),
            authorization
        );

        Signature memory signature;
        (signature.v, signature.r, signature.s) = vm.sign(privateKey, digest);

        return _call(
            address(staking),
            abi.encodeCall(staking.setAuthorizationWithSignature, (authorization, signature)),
            0,
            skipRevert
        );
    }

    function _stakingLock(
        IAltoStaking staking,
        uint256 amount,
        uint256 containerId,
        bool isReuse,
        uint256 maxEpochsToLockFor
    ) internal view returns (Call memory) {
        return _call(
            altoAdapter,
            abi.encodeCall(AltoAdapter.stakingLock, (staking, amount, containerId, isReuse, maxEpochsToLockFor)),
            bytes32(0)
        );
    }

    function _stakingUnlock(IAltoStaking staking, address receiver, uint256 containerId)
        internal
        view
        returns (Call memory)
    {
        return
            _call(altoAdapter, abi.encodeCall(AltoAdapter.stakingUnlock, (staking, receiver, containerId)), bytes32(0));
    }

    function _universalRewardsDistributorSetAuthorizationWithSig(
        IUniversalRewardsDistributor universalRewardsDistributor,
        uint256 privateKey,
        bool isAuthorized,
        uint256 nonce,
        bool skipRevert,
        address spender
    ) internal view returns (Call memory) {
        address user = vm.addr(privateKey);

        Authorization memory authorization = Authorization({
            owner: user, spender: spender, isAuthorizedStatus: isAuthorized, nonce: nonce, deadline: SIGNATURE_DEADLINE
        });

        bytes32 digest = SigUtils.toTypedDataHash(
            UniversalRewardsDistributorInstance(address(universalRewardsDistributor)).authorizationTypeHash(),
            UniversalRewardsDistributorInstance(address(universalRewardsDistributor)).domainSeparator(),
            authorization
        );

        Signature memory signature;
        (signature.v, signature.r, signature.s) = vm.sign(privateKey, digest);

        return _call(
            address(universalRewardsDistributor),
            abi.encodeCall(universalRewardsDistributor.setAuthorizationWithSignature, (authorization, signature)),
            0,
            skipRevert
        );
    }

    function _universalRewardsDistributorClaimRewardTokens(
        IUniversalRewardsDistributor universalRewardsDistributor,
        address rewardToken,
        uint256 totalRewardTokenAssignedToUser,
        bytes32[] memory proof
    ) internal view returns (Call memory) {
        return _call(
            altoAdapter,
            abi.encodeCall(
                AltoAdapter.claimRewardTokens,
                (universalRewardsDistributor, rewardToken, totalRewardTokenAssignedToUser, proof)
            ),
            bytes32(0)
        );
    }

    function _vestingSetAuthorizationWithSig(
        IAltoVesting vesting,
        uint256 privateKey,
        bool isAuthorized,
        uint256 nonce,
        bool skipRevert,
        address spender
    ) internal view returns (Call memory) {
        address user = vm.addr(privateKey);

        Authorization memory authorization = Authorization({
            owner: user, spender: spender, isAuthorizedStatus: isAuthorized, nonce: nonce, deadline: SIGNATURE_DEADLINE
        });

        bytes32 digest = SigUtils.toTypedDataHash(
            VestingInstance(address(vesting)).authorizationTypeHash(),
            VestingInstance(address(vesting)).domainSeparator(),
            authorization
        );

        Signature memory signature;
        (signature.v, signature.r, signature.s) = vm.sign(privateKey, digest);

        return _call(
            address(vesting),
            abi.encodeCall(vesting.setAuthorizationWithSignature, (authorization, signature)),
            0,
            skipRevert
        );
    }

    function _claimVestedTokens(
        IAltoVesting vesting,
        address onBehalf,
        VestingInfo memory vestingInfo,
        bytes32[] memory proof
    ) internal view returns (Call memory) {
        return _call(
            altoAdapter, abi.encodeCall(AltoAdapter.claimVestedTokens, (vesting, vestingInfo, proof)), bytes32(0)
        );
    }

    function _usmBuyAssetWithERC20Transfer(IUsm usm, uint256 minAmount, uint256 maxStableTokenAmount, address receiver)
        internal
        view
        returns (Call memory)
    {
        return _call(
            altoAdapter,
            abi.encodeCall(AltoAdapter.usmBuyAssetWithERC20Transfer, (usm, minAmount, maxStableTokenAmount, receiver)),
            bytes32(0)
        );
    }

    function _usmSellAssetWithERC20Transfer(IUsm usm, uint256 maxAmount, uint256 minStableTokenAmount, address receiver)
        internal
        view
        returns (Call memory)
    {
        return _call(
            altoAdapter,
            abi.encodeCall(AltoAdapter.usmSellAssetWithERC20Transfer, (usm, maxAmount, minStableTokenAmount, receiver)),
            bytes32(0)
        );
    }

    /* VAULT ACTIONS */

    function _vaultDeposit(IERC4626 vault, uint256 assets, address receiver, uint256 expectedShares)
        internal
        view
        returns (Call memory)
    {
        return _call(
            altoAdapter,
            abi.encodeCall(AltoAdapter.vaultDeposit, (vault, assets, receiver, expectedShares)),
            bytes32(0)
        );
    }

    function _vaultMint(IERC4626 vault, uint256 shares, address receiver, uint256 expectedAssets)
        internal
        view
        returns (Call memory)
    {
        return _call(
            altoAdapter,
            abi.encodeCall(AltoAdapter.vaultMint, (vault, shares, receiver, expectedAssets)),
            bytes32(0)
        );
    }

    function _vaultWithdraw(IERC4626 vault, uint256 assets, address receiver, uint256 expectedShares)
        internal
        view
        returns (Call memory)
    {
        return _call(
            altoAdapter,
            abi.encodeCall(AltoAdapter.vaultWithdraw, (vault, assets, receiver, expectedShares)),
            bytes32(0)
        );
    }

    function _vaultRedeem(IERC4626 vault, uint256 shares, address receiver, uint256 expectedAssets)
        internal
        view
        returns (Call memory)
    {
        return _call(
            altoAdapter,
            abi.encodeCall(AltoAdapter.vaultRedeem, (vault, shares, receiver, expectedAssets)),
            bytes32(0)
        );
    }
}
