// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {OracleMock} from "@alto/oracles/mocks/OracleMock.sol";
import {ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";

struct TestnetOracles {
    address stETHOracle;
    address usdoOracle;
    address usdcOracle;
    address altoOracle;
}

/// @title TestnetOraclesBatch
/// @notice Deploy testnet oracles
/// @dev Batches performs 1-tx deployments via constructor deployment pattern and contains on-chain reports of deployed contracts
contract TestnetOraclesBatch {
    TestnetOracles public oracles;

    constructor() {
        oracles = TestnetOracles({
            stETHOracle: address(new OracleMock()),
            altoOracle: address(new OracleMock()),
            usdoOracle: address(new OracleMock()),
            usdcOracle: address(new OracleMock())
        });

        OracleMock(oracles.stETHOracle).setPrice(1800 * ORACLE_PRICE_PRECISION);
        OracleMock(oracles.altoOracle).setPrice(3 * ORACLE_PRICE_PRECISION);
        OracleMock(oracles.usdoOracle).setPrice(ORACLE_PRICE_PRECISION);
        OracleMock(oracles.usdcOracle).setPrice(1 * 1e48);
    }

    function getOraclesReport() public view returns (TestnetOracles memory) {
        return oracles;
    }
}
