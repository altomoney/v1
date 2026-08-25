// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ErpOffboard02Json, SafeTransaction} from "./ErpOffboard02Json.sol";
import {IAltoVault, IAltoVaultBase} from "@alto/lending/interfaces/IAltoVault.sol";
import {PendingUint192} from "@alto/lending/libraries/PendingLib.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {FROZEN_TYPE, PAUSE_TYPE} from "@alto/utils/Constants.sol";

interface IPauserState is IPausable {
    function pausers(address account, bytes32 pauseType) external view returns (bool);
}

/// @notice Generates the Safe batch used to freeze the Batch A borrow markets.
contract BatchAScript is ErpOffboard02Json {
    string public constant ADDRESSES_FILE =
        "contracts/deployments/ethereum-mainnet/output/ethereum-mainnet-1-1765364975/addresses.json";
    string public constant FREEZER_OUTPUT_FILE = "batch-a-freeze-safe.json";
    string public constant VAULT_CURATOR_OUTPUT_FILE = "batch-a-vault-curator-safe.json";

    /// @dev Production Freezer Safe from `script/DeployAltoEthereumMainnet.s.sol`.
    /// The deployment output JSON contains contract addresses only, so this control address cannot be read from it.
    address public constant FREEZER_SAFE = 0x1c11d2d42929bd17aB7212b79c91862Adfa8bbe4;

    function run() external {
        require(block.chainid == 1, "Batch A: Ethereum mainnet only");

        string memory addresses = vm.readFile(ADDRESSES_FILE);
        address vault = vm.parseJsonAddress(addresses, ".contracts.dusdVault");
        address[] memory borrowMarkets = borrowMarketsToDeprecate();

        _validateMarkets(borrowMarkets);
        _writeFreezerBatch(FREEZER_SAFE, borrowMarkets);
        _writeVaultCuratorBatch(vault, borrowMarkets);
    }

    function _validateMarkets(address[] memory borrowMarkets) private view {
        require(borrowMarkets.length != 0, "Batch A: no markets");

        for (uint256 i; i < borrowMarkets.length; ++i) {
            address market = borrowMarkets[i];
            require(market != address(0) && market.code.length != 0, "Batch A: invalid market");
            require(!IPauserState(market).paused(FROZEN_TYPE), "Batch A: market already frozen");
            require(!IPauserState(market).paused(PAUSE_TYPE), "Batch A: market paused");
            require(IPauserState(market).pausers(FREEZER_SAFE, FROZEN_TYPE), "Batch A: Safe is not freezer");

            for (uint256 j; j < i; ++j) {
                require(market != borrowMarkets[j], "Batch A: duplicate market");
            }
        }
    }

    function _writeFreezerBatch(address freezerSafe, address[] memory borrowMarkets) internal {
        SafeTransaction[] memory transactions = new SafeTransaction[](borrowMarkets.length);

        for (uint256 i; i < borrowMarkets.length; ++i) {
            transactions[i] = _transaction(borrowMarkets[i], abi.encodeCall(IPausable.pause, (FROZEN_TYPE, true)));
        }

        _writeSafeBatch(
            FREEZER_OUTPUT_FILE, "ERP-OFFBOARD-02 - Batch A Freeze Borrow Markets", freezerSafe, transactions
        );
    }

    function _writeVaultCuratorBatch(address vault, address[] memory borrowMarkets) internal {
        bool[] memory hasPendingCap = new bool[](borrowMarkets.length);
        uint256 transactionCount = borrowMarkets.length;

        for (uint256 i; i < borrowMarkets.length; ++i) {
            PendingUint192 memory pendingCap = IAltoVault(vault).pendingCap(borrowMarkets[i]);
            hasPendingCap[i] = pendingCap.validAt != 0;
            if (hasPendingCap[i]) ++transactionCount;
        }

        SafeTransaction[] memory transactions = new SafeTransaction[](transactionCount);
        uint256 transactionIndex;

        for (uint256 i; i < borrowMarkets.length; ++i) {
            if (hasPendingCap[i]) {
                transactions[transactionIndex] =
                    _transaction(vault, abi.encodeCall(IAltoVaultBase.revokePendingCap, (borrowMarkets[i])));
                ++transactionIndex;
            }

            transactions[transactionIndex] =
                _transaction(vault, abi.encodeCall(IAltoVaultBase.submitCap, (borrowMarkets[i], 0)));
            ++transactionIndex;
        }

        _writeSafeBatch(
            VAULT_CURATOR_OUTPUT_FILE,
            "ERP-OFFBOARD-02 - Batch A Zero Borrow Market Caps",
            IAltoVaultBase(vault).curator(),
            transactions
        );
    }

    /// @dev Placeholder targets for the current activation, in mainnet deployment order.
    /// Replace this array when an approved manifest names a different set of borrow markets.
    function borrowMarketsToDeprecate() public pure returns (address[] memory borrowMarkets) {
        borrowMarkets = new address[](5);
        borrowMarkets[0] = 0xefd78a5970a43e25b30426C3952065217c55e5E4; // WBTC borrow market
        borrowMarkets[1] = 0xaE4f2B998783e2041E87E08Da73985e4E0420159; // cbBTC borrow market
        borrowMarkets[2] = 0x133cf03d2A7a87B9239b1a3a8Dd62f3f27c46788; // sUSDe borrow market
        borrowMarkets[3] = 0x33B24510233281350bF8679A7c427d04db0ed208; // syrupUSDC borrow market
        borrowMarkets[4] = 0x99f538Ec7c840197DcAf30A25B635482ba9e8817; // PAXG borrow market
    }
}
