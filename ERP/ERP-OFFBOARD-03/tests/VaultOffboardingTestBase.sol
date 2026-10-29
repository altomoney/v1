// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {VaultOffboardingScript} from "../scripts/VaultOffboarding.s.sol";
import {VaultOffboarding} from "../VaultOffboarding.sol";
import {VaultOffboardingIO} from "../libraries/VaultOffboardingIO.sol";
import {
    VaultOffboardingManifest,
    VaultOffboardingContracts,
    VaultOffboardingPhase,
    VaultOffboardingAction as Action,
    VaultOffboardingRemovalTarget,
    VaultOffboardingRecoveryTarget,
    VaultOffboardingToken,
    VaultOffboardingClosureMarket
} from "../IVaultOffboarding.sol";
import {ERPOutputWriter} from "../../libraries/ERPOutputWriter.sol";
import {OracleMock} from "@alto/oracles/mocks/OracleMock.sol";
import {LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {IBundler3, Call} from "@morpho-org/bundler3/interfaces/IBundler3.sol";
import {PAUSE_TYPE, FROZEN_TYPE} from "@alto/utils/Constants.sol";
import {ERPVaultQueue} from "../../libraries/ERPVaultQueue.sol";
import {AltoVault} from "@alto/lending/vault/AltoVault.sol";
import {IAltoVault} from "@alto/lending/interfaces/IAltoVault.sol";
import {AltoBorrowMarket} from "@alto/lending/AltoBorrowMarket.sol";
import {IMarket, BaseMarketInitParams, BorrowMarketInitParams} from "@alto/lending/interfaces/IMarket.sol";
import {AltoBalancesLib} from "@alto/lending/libraries/AltoBalancesLib.sol";
import {DlbDcfPriorityLiquidationEngine} from "@alto/lending/liquidation/DlbDcfPriorityLiquidationEngine.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {MarketRegistry} from "@alto/utils/MarketRegistry.sol";
import {IVaultRegistry} from "@alto/utils/interfaces/IVaultRegistry.sol";
import {AltoAdapter} from "@alto/utils/AltoAdapter.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/// @dev Minimal ABI of the live curator Safe. Owners approve the generated transaction hash on the fork.
interface IVaultTestSafe {
    function getOwners() external view returns (address[] memory);
    function getThreshold() external view returns (uint256);
    function nonce() external view returns (uint256);
    function approveHash(bytes32 hash) external;
    function getTransactionHash(
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address refundReceiver,
        uint256 nonce_
    ) external view returns (bytes32);
    function execTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address payable refundReceiver,
        bytes calldata signatures
    ) external payable returns (bool);
}

/// @dev Like the Mint/Borrow helpers, executes JSON transactions as the recorded Safe. Safe signature collection
/// is outside these tests; the production script, Vault, markets and Timelock execute without mocked implementations.
abstract contract VaultOffboardingTestBase is Test {
    using AltoBalancesLib for address;

    uint256 internal constant FORK_BLOCK = 26_225_900;
    string internal constant EXAMPLE = "ERP/ERP-OFFBOARD-03/config/vault-offboarding.json";
    address internal constant MULTISEND_CALL_ONLY = 0x40A2aCCbd92BCA938b02010E17A5b8929b49130D;
    string internal manifestPath;
    string internal constant CURATOR_FILE = "vault-curator-safe.json";
    string internal constant SCHEDULE_FILE = "vault-governance-schedule.json";
    string internal constant EXECUTE_FILE = "vault-governance-execute.json";

    VaultOffboardingScript internal script;
    VaultOffboardingManifest internal manifest;
    VaultOffboardingContracts internal contracts;
    IAltoVault internal vault;
    IERC4626 internal shares;
    IERC20 internal asset;
    TimelockController internal timelock;
    AltoAdapter internal adapter;
    MarketRegistry internal registry;
    address internal alice;
    address internal guardian;
    address internal feeRecipient;
    address internal retainedAllocator;
    address internal revokedAllocator;
    VaultOffboardingPhase internal phase;

    function _activationId() internal pure virtual returns (string memory) {
        return "test-vault-batch-a";
    }

    function _testRoot() internal pure returns (string memory) {
        return string.concat("ERP/ERP-OFFBOARD-03/output/", _activationId());
    }

    function _setUpFork() internal {
        vm.createSelectFork(vm.rpcUrl("ethereum"), FORK_BLOCK);
        string memory json = vm.readFile(EXAMPLE);
        VaultOffboardingManifest memory loaded = VaultOffboardingIO.loadActivationManifest(json);
        VaultOffboardingIO.loadPhaseParameters(json, VaultOffboardingPhase.BATCH_A_CONTAIN, loaded);
        // Copy Batch A fields only; no exceptional-action structures or test-only compiler settings are needed.
        manifest.severity = loaded.severity;
        manifest.t0 = loaded.t0;
        manifest.step = loaded.step;
        manifest.sourceBlock = loaded.sourceBlock;
        manifest.deploymentId = loaded.deploymentId;
        manifest.vault = loaded.vault;
        manifest.curatorSafe = loaded.curatorSafe;
        manifest.timelockSafe = loaded.timelockSafe;
        manifest.markets = loaded.markets;
        manifest.shareholders = loaded.shareholders;
        manifest.quarantinedMarkets = loaded.quarantinedMarkets;
        manifest.allocatorsToRevoke = loaded.allocatorsToRevoke;
        assertEq(manifest.sourceBlock, FORK_BLOCK, "example fork changed");
        manifest.activationId = _activationId();
        manifestPath = string.concat(_testRoot(), "/live-manifest.json");
        contracts = VaultOffboardingIO.loadCurrentChainContracts(manifest.deploymentId);
        timelock = TimelockController(payable(contracts.timelock));
        adapter = AltoAdapter(payable(contracts.altoAdapter));
        script = new VaultOffboardingScript();
        _bindVault();
        alice = makeAddr("vault shareholder");
        guardian = makeAddr("retained guardian");
        feeRecipient = makeAddr("earned fee recipient");
        retainedAllocator = makeAddr("essential allocator");
        revokedAllocator = makeAddr("nonessential allocator");
        // Filesystem effects survive EVM snapshots; reserve a test-only activation directory.
        if (vm.exists(_testRoot())) vm.removeDir(_testRoot(), true);
        vm.createDir(_testRoot(), true);
    }

    function _bindVault() internal {
        vault = IAltoVault(manifest.vault);
        shares = IERC4626(manifest.vault);
        asset = IERC20(shares.asset());
        registry = MarketRegistry(address(vault.marketRegistry()));
    }

    /// @dev Setup calls seed state only. Every ERP response below must be executed from generated files.
    /// Three real markets: two funded and one empty, with a real zero-rate IRM for deterministic accounting.
    function _useFixture() internal {
        // Each test gets separate inputs and run directories, including when Forge runs cases concurrently.
        manifest.step = uint32(msg.sig);
        manifestPath = string.concat(_testRoot(), "/manifest-", vm.toString(msg.sig), ".json");
        IMarket template = IMarket(manifest.markets[0]);
        address implementation = address(new AltoBorrowMarket());
        address[] memory markets = new address[](3);
        for (uint256 i; i < markets.length; ++i) {
            markets[i] = _deployFixtureMarket(template, implementation);
        }
        manifest.markets = markets;
        manifest.vault =
            address(new AltoVault(address(timelock), 2 days, address(asset), "ERP Vault", "ERP", address(registry)));
        manifest.shareholders = _oneAddress(alice);
        manifest.allocatorsToRevoke = _oneAddress(revokedAllocator);
        delete manifest.quarantinedMarkets;
        _bindVault();
        vm.startPrank(address(timelock));
        vault.setCurator(manifest.curatorSafe);
        vault.submitGuardian(guardian);
        vault.setFeeRecipient(feeRecipient);
        vault.setSkimRecipient(makeAddr("skim recipient"));
        vault.setIsAllocator(revokedAllocator, true);
        vault.setIsAllocator(retainedAllocator, true);
        vm.stopPrank();
        vm.startPrank(manifest.curatorSafe);
        for (uint256 i; i < markets.length; ++i) {
            vault.submitCap(markets[i], 1_000_000 ether);
        }
        vm.warp(block.timestamp + vault.timelock());
        for (uint256 i; i < markets.length; ++i) {
            vault.acceptCap(markets[i]);
        }
        vault.setSupplyQueue(_oneAddress(markets[0]));
        vm.stopPrank();
        _deposit(alice, 600 ether);
        vm.prank(manifest.curatorSafe);
        vault.setSupplyQueue(_oneAddress(markets[1]));
        _deposit(alice, 400 ether);
        vm.prank(manifest.curatorSafe);
        vault.setSupplyQueue(markets);
        vm.prank(address(timelock));
        vault.setFee(0.1 ether);
        vm.prank(Ownable(address(adapter)).owner());
        adapter.approveContract(manifest.vault);
        vm.prank(Ownable(contracts.vaultRegistry).owner());
        IVaultRegistry(contracts.vaultRegistry).addVault(manifest.vault);
        _advanceSourceBlock();
    }

    function _deployFixtureMarket(IMarket template, address implementation) internal returns (address market) {
        BorrowMarketInitParams memory params = BorrowMarketInitParams({
            baseMarketInitParams: BaseMarketInitParams({
                borrowToken: address(asset),
                collateralToken: template.collateralToken(),
                irm: address(new FixedRateIrm(0, address(this))),
                owner: address(this),
                emergencyAdmin: address(this),
                oracle: template.oracle(),
                maxLtv: template.maxLtv(),
                feeRecipient: makeAddr("market fee recipient"),
                liquidationEngine: address(new DlbDcfPriorityLiquidationEngine(address(this)))
            }),
            initialBorrowOpeningFee: 0,
            supplyCapAssets: 0,
            initialInterestFee: 0
        });
        market = address(new ERC1967Proxy(implementation, abi.encodeCall(AltoBorrowMarket.initialize, (params))));
        vm.prank(Ownable(address(registry)).owner());
        registry.addBorrowMarket(market);
    }

    function _deposit(address account, uint256 amount) internal {
        deal(address(asset), account, amount);
        vm.startPrank(account);
        asset.approve(manifest.vault, amount);
        shares.deposit(amount, account);
        vm.stopPrank();
    }

    function _supplyOnBehalf(address market, uint256 amount, address account) internal {
        address supplier = makeAddr("external supplier");
        deal(address(asset), supplier, amount);
        vm.startPrank(supplier);
        asset.approve(market, amount);
        IMarket(market).addSupply(amount, 0, account);
        vm.stopPrank();
    }

    function _seedPendingChanges() internal {
        vm.startPrank(address(timelock));
        vault.submitGuardian(makeAddr("pending guardian"));
        vault.submitTimelock(1 days);
        vm.stopPrank();
        vm.startPrank(manifest.curatorSafe);
        vault.submitCap(manifest.markets[0], 2_000_000 ether);
        for (uint256 i = 1; i < manifest.markets.length; ++i) {
            vault.submitCap(manifest.markets[i], 0);
            vault.submitMarketRemoval(manifest.markets[i]);
        }
        vm.stopPrank();
    }

    function _writeManifest() internal {
        string memory key = "vault-test-input";
        vm.serializeJson(key, "{}");
        vm.serializeString(key, "activationId", manifest.activationId);
        vm.serializeUint(key, "severity", uint256(manifest.severity));
        vm.serializeUint(key, "t0", manifest.t0);
        vm.serializeUint(key, "step", manifest.step);
        vm.serializeUint(key, "sourceBlock", manifest.sourceBlock);
        vm.serializeUint(key, "deploymentId", manifest.deploymentId);
        vm.serializeAddress(key, "vault", manifest.vault);
        vm.serializeAddress(key, "curatorSafe", manifest.curatorSafe);
        vm.serializeAddress(key, "timelockSafe", manifest.timelockSafe);
        vm.serializeAddress(key, "markets", manifest.markets);
        vm.serializeAddress(key, "shareholders", manifest.shareholders);
        vm.serializeAddress(key, "quarantinedMarkets", manifest.quarantinedMarkets);
        string memory json = vm.serializeAddress(key, "allocatorsToRevoke", manifest.allocatorsToRevoke);
        vm.writeJson(json, manifestPath);
        if (phase == VaultOffboardingPhase.BATCH_B_CORRECT) _writeCorrectionParameters();
        else if (phase == VaultOffboardingPhase.BATCH_C_RECOVER) _writeClosureParameters();
    }

    /// @dev Preparation rejections leave protocol state unchanged and must not leave executable stale files.
    function _expectPreparationRevert(string memory reason) internal {
        _writeManifest();
        _expectScriptRevert(reason);
    }

    function _expectScriptRevert(string memory reason) internal {
        bytes32 beforeState = _preparationStateHash();
        if (bytes(reason).length == 0) vm.expectRevert();
        else vm.expectRevert(bytes(reason));
        script.run(uint256(phase), manifestPath);
        _assertNoCalldata();
        assertEq(_preparationStateHash(), beforeState);
    }

    // Read the bound Vault, not manifest market addresses that rejection cases intentionally corrupt.
    function _preparationStateHash() private view returns (bytes32) {
        return keccak256(
            abi.encode(
                shares.totalSupply(),
                vault.lastTotalAssets(),
                vault.lostAssets(),
                vault.fee(),
                vault.curator(),
                vault.guardian(),
                ERPVaultQueue.supplyQueue(vault),
                ERPVaultQueue.withdrawQueue(vault)
            )
        );
    }

    function _assertReportSnapshot() internal view {
        string memory json = vm.readFile(_path("exposure-report.json"));
        assertEq(vm.parseJsonUint(json, ".sourceBlock"), manifest.sourceBlock);
        assertEq(vm.parseJsonUint(json, ".sourceTimestamp"), block.timestamp);
        assertEq(_reportAmount(".totalSupply"), shares.totalSupply());
        assertEq(_reportAmount(".totalAssets"), shares.totalAssets());
        assertEq(_reportAmount(".lastTotalAssets"), vault.lastTotalAssets());
        assertEq(_reportAmount(".lostAssets"), vault.lostAssets());
    }

    /// @dev Files survive EVM snapshot restoration; seed them explicitly for cleanup and directory-isolation cases.
    function _seedStaleArtifacts() internal returns (string[6] memory names) {
        names = [
            CURATOR_FILE,
            SCHEDULE_FILE,
            EXECUTE_FILE,
            "vault-allocator.json",
            "closure-report.json",
            "exposure-report.json"
        ];
        for (uint256 i; i < names.length; ++i) {
            vm.writeFile(_path(names[i]), '{"closure":{"outcome":"stale"}}');
        }
    }

    function _generate() internal {
        _writeManifest();
        script.run(uint256(phase), manifestPath);
    }

    function _directory() internal view returns (string memory) {
        return VaultOffboarding.artifactDirectory(phase, manifest);
    }

    function _path(string memory name) internal view returns (string memory) {
        return string.concat(_directory(), "/", name);
    }

    function _advanceSourceBlock() internal {
        vm.roll(block.number + 1);
        manifest.sourceBlock = block.number;
    }

    function _transaction(string memory json, uint256 i) internal pure returns (address target, bytes memory data) {
        string memory prefix = string.concat(".transactions[", vm.toString(i), "]");
        target = vm.parseJsonAddress(json, string.concat(prefix, ".to"));
        data = vm.parseJsonBytes(json, string.concat(prefix, ".data"));
    }

    function _callFrom(address caller, address target, uint256 value, bytes memory data) internal {
        vm.prank(caller);
        (bool ok, bytes memory reason) = target.call{value: value}(data);
        if (!ok) assembly ("memory-safe") { revert(add(reason, 32), mload(reason)) }
    }

    function _redeemThroughAdapter(uint256 amount) internal {
        _adapterExit(abi.encodeCall(AltoAdapter.erc4626Redeem, (manifest.vault, amount, 0, alice, alice)));
    }

    function _adapterExit(bytes memory data) private {
        vm.prank(alice);
        shares.approve(address(adapter), type(uint256).max);
        Call[] memory calls = new Call[](1);
        calls[0] = Call(address(adapter), data, 0, false, bytes32(0));
        IBundler3 bundler = IBundler3(adapter.BUNDLER3());
        vm.prank(alice);
        bundler.multicall(calls);
    }

    function _executeSafeFile(string memory name, address safe) internal {
        string memory json = vm.readFile(_path(name));
        assertEq(vm.parseJsonAddress(json, ".meta.createdFromSafeAddress"), safe, "wrong Safe");
        uint256 i;
        while (vm.keyExistsJson(json, string.concat(".transactions[", vm.toString(i), "]"))) {
            (address target, bytes memory data) = _transaction(json, i++);
            uint256 value =
                vm.parseUint(vm.parseJsonString(json, string.concat(".transactions[", vm.toString(i - 1), "].value")));
            _callFrom(safe, target, value, data);
        }
    }

    function _scheduleOwner() internal returns (bytes32 id) {
        (address target, bytes memory data) = _transaction(vm.readFile(_path(EXECUTE_FILE)), 0);
        // Decode only to track native readiness and completion of the operation executed from the file.
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory payloads,
            bytes32 predecessor,
            bytes32 salt
        ) = abi.decode(_arguments(data), (address[], uint256[], bytes[], bytes32, bytes32));
        id = timelock.hashOperationBatch(targets, values, payloads, predecessor, salt);
        _executeSafeFile(SCHEDULE_FILE, manifest.timelockSafe);
        assertTrue(timelock.isOperationPending(id));
        if (timelock.getMinDelay() != 0) {
            vm.prank(manifest.timelockSafe);
            (bool ok,) = target.call(data);
            assertFalse(ok, "executed before governance delay");
        }
        vm.warp(timelock.getTimestamp(id));
        assertTrue(timelock.isOperationReady(id));
    }

    function _executeOwner() internal returns (bytes32 id) {
        id = _scheduleOwner();
        _executeSafeFile(EXECUTE_FILE, manifest.timelockSafe);
        assertTrue(timelock.isOperationDone(id));
    }

    function _executeStage() internal {
        _generate();
        _executePrepared();
        _advanceSourceBlock();
    }

    function _executePrepared() internal {
        if (vm.exists(_path("vault-allocator.json"))) _executeAllocator();
        if (vm.exists(_path(CURATOR_FILE))) {
            if (phase == VaultOffboardingPhase.BATCH_B_CORRECT) _executeCuratorAtomic();
            else _executeSafeFile(CURATOR_FILE, manifest.curatorSafe);
        }
        if (vm.exists(_path(SCHEDULE_FILE))) _executeOwner();
    }

    function _completeBatchA() internal {
        for (uint256 i; i < 3; ++i) {
            _executeStage();
        }
        _generate();
        _assertNoCalldata();
        _assertContained();
        assertEq(vault.fee(), 0);
    }

    function _assertNoCalldata() internal view {
        assertFalse(vm.exists(_path(CURATOR_FILE)));
        assertFalse(vm.exists(_path(SCHEDULE_FILE)));
        assertFalse(vm.exists(_path(EXECUTE_FILE)));
        assertFalse(vm.exists(_path("vault-allocator.json")));
    }

    function _assertContained() internal view {
        _assertSupplyClosed();
        assertEq(vault.pendingGuardian().validAt, 0);
        assertEq(vault.pendingTimelock().validAt, 0);
        for (uint256 i; i < manifest.markets.length; ++i) {
            assertEq(vault.config(manifest.markets[i]).removableAt, 0);
        }
    }

    function _claimsHash() internal view returns (bytes32 hash) {
        hash = keccak256(abi.encode(ERPVaultQueue.withdrawQueue(vault)));
        for (uint256 i; i < manifest.markets.length; ++i) {
            address market = manifest.markets[i];
            hash = keccak256(
                abi.encode(
                    hash,
                    market,
                    IMarket(market).position(manifest.vault).supplyShares,
                    vault.config(market).enabled,
                    vault.quarantinedAssets(market)
                )
            );
        }
    }

    function _oneAddress(address value) internal pure returns (address[] memory result) {
        result = new address[](1);
        result[0] = value;
    }

    function _arguments(bytes memory data) internal pure returns (bytes memory result) {
        result = new bytes(data.length - 4);
        for (uint256 i; i < result.length; ++i) {
            result[i] = data[i + 4];
        }
    }

    function _reportAmount(string memory key) internal view returns (uint256) {
        return vm.parseUint(vm.parseJsonString(vm.readFile(_path("exposure-report.json")), key));
    }

    function _allocatorTransaction() internal view returns (address target, bytes memory data) {
        string memory json = vm.readFile(_path("vault-allocator.json"));
        target = vm.parseJsonAddress(json, ".transaction.to");
        data = vm.parseJsonBytes(json, ".transaction.data");
    }

    function _executeAllocator() internal {
        (address target, bytes memory data) = _allocatorTransaction();
        uint256 value =
            vm.parseUint(vm.parseJsonString(vm.readFile(_path("vault-allocator.json")), ".transaction.value"));
        _callFrom(manifest.allocator, target, value, data);
    }

    /// @dev Rebuild only Safe's outer MultiSend envelope; all targets, values and payloads come from generated JSON.
    function _signedCuratorExecution() internal returns (bytes memory execution) {
        string memory json = vm.readFile(_path(CURATOR_FILE));
        assertGt(MULTISEND_CALL_ONLY.code.length, 0);
        bytes memory packed;
        uint256 i;
        while (vm.keyExistsJson(json, string.concat(".transactions[", vm.toString(i), "]"))) {
            (address target, bytes memory data) = _transaction(json, i++);
            uint256 value =
                vm.parseUint(vm.parseJsonString(json, string.concat(".transactions[", vm.toString(i - 1), "].value")));
            packed = bytes.concat(packed, abi.encodePacked(uint8(0), target, value, data.length, data));
        }
        bytes memory multiSendData = abi.encodeWithSignature("multiSend(bytes)", packed);
        IVaultTestSafe safe = IVaultTestSafe(manifest.curatorSafe);
        bytes32 hash = safe.getTransactionHash(
            MULTISEND_CALL_ONLY, 0, multiSendData, 1, 0, 0, 0, address(0), address(0), safe.nonce()
        );
        address[] memory owners = safe.getOwners();
        // Safe requires ascending signer addresses for pre-approved-hash signatures.
        for (i = 0; i < owners.length; ++i) {
            for (uint256 j = i + 1; j < owners.length; ++j) {
                if (owners[j] < owners[i]) (owners[i], owners[j]) = (owners[j], owners[i]);
            }
        }
        uint256 threshold = safe.getThreshold();
        bytes memory signatures;
        for (i = 0; i < threshold; ++i) {
            vm.prank(owners[i]);
            safe.approveHash(hash);
            signatures =
                bytes.concat(signatures, abi.encodePacked(bytes32(uint256(uint160(owners[i]))), bytes32(0), uint8(1)));
        }
        return abi.encodeCall(
            IVaultTestSafe.execTransaction,
            (MULTISEND_CALL_ONLY, 0, multiSendData, 1, 0, 0, 0, address(0), payable(address(0)), signatures)
        );
    }

    function _executeCuratorAtomic() internal {
        bytes memory execution = _signedCuratorExecution();
        (bool ok, bytes memory result) = manifest.curatorSafe.call(execution);
        if (!ok) assembly ("memory-safe") { revert(add(result, 32), mload(result)) }
        assertTrue(abi.decode(result, (bool)), "Safe failed generated batch");
    }

    /// @dev Real borrowing creates illiquidity; only the collateral price feed is controlled by this fixture.
    function _borrow(address market, uint256 amount) internal returns (address borrower) {
        OracleMock oracle = new OracleMock();
        oracle.setPrice(LENDING_ORACLE_PRICE_PRECISION);
        IMarket(market).setOracle(address(oracle));
        borrower = makeAddr("batch-b underlying borrower");
        IERC20 collateral = IERC20(IMarket(market).collateralToken());
        deal(address(collateral), borrower, amount * 10);
        vm.startPrank(borrower);
        collateral.approve(market, amount * 10);
        IMarket(market).addCollateral(amount * 10, borrower);
        IMarket(market).borrow(amount, 0, borrower, borrower, "");
        vm.stopPrank();
    }

    function _assertClosedAllocation() internal view {
        _assertSupplyClosed();
        assertEq(vault.fee(), 0);
    }

    function _assertSupplyClosed() private view {
        assertEq(vault.supplyQueueLength(), 0);
        for (uint256 i; i < manifest.markets.length; ++i) {
            assertEq(vault.config(manifest.markets[i]).cap, 0);
            assertEq(vault.pendingCap(manifest.markets[i]).validAt, 0);
        }
        assertEq(shares.maxDeposit(alice), 0);
        assertEq(shares.maxMint(alice), 0);
    }

    function _withdrawThroughAdapter(uint256 amount) internal {
        _adapterExit(abi.encodeCall(AltoAdapter.erc4626Withdraw, (manifest.vault, amount, 0, alice, alice)));
    }

    function _marketControlsHash() internal view returns (bytes32 result) {
        for (uint256 i; i < manifest.markets.length; ++i) {
            IMarket market = IMarket(manifest.markets[i]);
            result = keccak256(
                abi.encode(
                    result,
                    market.irm(),
                    market.oracle(),
                    market.maxLtv(),
                    market.liquidationEngine(),
                    market.feeRecipient(),
                    market.paused(PAUSE_TYPE),
                    market.paused(FROZEN_TYPE),
                    registry.isBorrowMarket(address(market))
                )
            );
        }
    }

    function _assertIntegrations(bool expected) internal view {
        assertEq(adapter.isApprovedContract(manifest.vault), expected);
        assertEq(IVaultRegistry(contracts.vaultRegistry).isVault(manifest.vault), expected);
    }

    function _writeCorrectionParameters() private {
        vm.writeJson(vm.toString(uint256(manifest.action)), manifestPath, ".action");
        vm.writeJson(vm.toString(manifest.noticeAt), manifestPath, ".noticeAt");
        vm.writeJson(manifest.noticeWaived ? "true" : "false", manifestPath, ".noticeWaived");
        vm.writeJson(string.concat('"', manifest.noticeWaiverReference, '"'), manifestPath, ".noticeWaiverReference");
        vm.writeJson(string.concat('"', vm.toString(manifest.allocator), '"'), manifestPath, ".allocator");
        vm.writeJson(ERPOutputWriter.addressArrayJson(manifest.withdrawQueue), manifestPath, ".withdrawQueue");
        if (manifest.action == Action.SUBMIT_REMOVAL || manifest.action == Action.EXECUTE_REMOVAL) {
            string memory targets = "[";
            for (uint256 i; i < manifest.removalTargets.length; ++i) {
                VaultOffboardingRemovalTarget memory target = manifest.removalTargets[i];
                string memory key = "removal-target";
                vm.serializeJson(key, "{}");
                string memory row = vm.serializeAddress(key, "market", target.market);
                if (manifest.action == Action.EXECUTE_REMOVAL) {
                    vm.serializeUint(key, "approvedSupplyShares", target.approvedSupplyShares);
                    vm.serializeUint(key, "approvedExpectedAssets", target.approvedExpectedAssets);
                    row = vm.serializeUint(key, "maxExceptionalRemovedAssets", target.maxExceptionalRemovedAssets);
                }
                targets = string.concat(targets, i == 0 ? "" : ",", row);
            }
            vm.writeJson(string.concat(targets, "]"), manifestPath, ".removalTargets");
            vm.writeJson(
                vm.toString(manifest.maxExceptionalRemovedAssets), manifestPath, ".maxExceptionalRemovedAssets"
            );
            vm.writeJson(vm.toString(manifest.maxLostAssets), manifestPath, ".maxLostAssets");
            vm.writeJson(vm.toString(manifest.maxQuarantinedAssets), manifestPath, ".maxQuarantinedAssets");
        }
        if (manifest.action == Action.SUBMIT_RECOVERY_CAP || manifest.action == Action.ACCEPT_RECOVERY_CAP) {
            string memory targets = "[";
            for (uint256 i; i < manifest.recoveryTargets.length; ++i) {
                VaultOffboardingRecoveryTarget memory target = manifest.recoveryTargets[i];
                string memory key = "recovery-target";
                vm.serializeJson(key, "{}");
                vm.serializeAddress(key, "market", target.market);
                vm.serializeUint(key, "recoveryCap", target.recoveryCap);
                string memory row = vm.serializeUint(key, "maxTemporaryCapAssets", target.maxTemporaryCapAssets);
                targets = string.concat(targets, i == 0 ? "" : ",", row);
            }
            vm.writeJson(string.concat(targets, "]"), manifestPath, ".recoveryTargets");
            vm.writeJson(vm.toString(manifest.maxTemporaryCapAssets), manifestPath, ".maxTemporaryCapAssets");
        }
    }

    function _writeClosureParameters() private {
        string memory tokens = "[";
        for (uint256 i; i < manifest.tokens.length; ++i) {
            VaultOffboardingToken memory token = manifest.tokens[i];
            string memory key = "closure-token";
            vm.serializeJson(key, "{}");
            vm.serializeAddress(key, "token", token.token);
            vm.serializeUint(key, "approvedBalance", token.approvedBalance);
            string memory row = vm.serializeAddress(key, "recipient", token.recipient);
            tokens = string.concat(tokens, i == 0 ? "" : ",", row);
        }
        vm.writeJson(string.concat(tokens, "]"), manifestPath, ".tokens");
        vm.writeJson(manifest.exceptionalClosure ? "true" : "false", manifestPath, ".exceptionalClosure");
        if (!manifest.exceptionalClosure) return;
        vm.writeJson(
            string.concat('"', manifest.closureApprovalReference, '"'), manifestPath, ".closureApprovalReference"
        );
        vm.writeJson(
            string.concat('"', manifest.closureTreatmentReference, '"'), manifestPath, ".closureTreatmentReference"
        );
        vm.writeJson(vm.toString(manifest.approvedTotalSupply), manifestPath, ".approvedTotalSupply");
        vm.writeJson(vm.toString(manifest.approvedTotalAssets), manifestPath, ".approvedTotalAssets");
        vm.writeJson(vm.toString(manifest.approvedLastTotalAssets), manifestPath, ".approvedLastTotalAssets");
        vm.writeJson(vm.toString(manifest.approvedLostAssets), manifestPath, ".approvedLostAssets");
        vm.writeJson(vm.toString(manifest.maxLostAssets), manifestPath, ".maxLostAssets");
        vm.writeJson(vm.toString(manifest.maxQuarantinedAssets), manifestPath, ".maxQuarantinedAssets");
        string memory markets = "[";
        for (uint256 i; i < manifest.closureMarkets.length; ++i) {
            VaultOffboardingClosureMarket memory entry = manifest.closureMarkets[i];
            string memory key = "closure-market";
            vm.serializeJson(key, "{}");
            vm.serializeAddress(key, "market", entry.market);
            vm.serializeUint(key, "approvedSupplyShares", entry.approvedSupplyShares);
            vm.serializeUint(key, "approvedExpectedAssets", entry.approvedExpectedAssets);
            string memory row = vm.serializeUint(key, "approvedQuarantinedAssets", entry.approvedQuarantinedAssets);
            markets = string.concat(markets, i == 0 ? "" : ",", row);
        }
        vm.writeJson(string.concat(markets, "]"), manifestPath, ".closureMarkets");
    }
}
