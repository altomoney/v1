// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {DUSDUsm} from "@alto/usm/DUSDUsm.sol";
import {FixedPriceStrategy} from "@alto/usm/FixedPriceStrategy.sol";
import {FixedFeeStrategy} from "@alto/usm/FixedFeeStrategy.sol";
import {IUsm} from "@alto/usm/interfaces/IUsm.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";
import {AltoAdapter} from "@alto/utils/AltoAdapter.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

struct TestnetUsmBatchParams {
    address owner;
    address dusd;
    address underlyingAsset;
    uint256 buyFee;
    uint256 sellFee;
    uint256 exposureCap;
}

struct TestnetUsmBatchReport {
    address dusdUsm;
    address dusdUsmImplementation;
    address fixedPriceStrategy;
    address fixedFeeStrategy;
}

contract TestnetUsmBatch {
    TestnetUsmBatchReport public report;

    constructor(TestnetUsmBatchParams memory _params) {
        // Deploy FixedPriceStrategy
        address fixedPriceStrategy = address(new FixedPriceStrategy(1 ether, _params.underlyingAsset, _params.owner));

        // Deploy FixedFeeStrategy
        address fixedFeeStrategy = address(new FixedFeeStrategy(_params.buyFee, _params.sellFee, _params.owner));

        // Deploy DUSDUsm Implementation
        address dusdUsmImplementation = address(new DUSDUsm(_params.dusd, _params.underlyingAsset));

        // Deploy DUSDUsm Proxy
        address dusdUsm = UnsafeUpgrades.deployUUPSProxy(
            address(dusdUsmImplementation),
            abi.encodeCall(
                DUSDUsm.initialize, (_params.owner, _params.owner, uint128(_params.exposureCap), fixedPriceStrategy)
            )
        );

        report = TestnetUsmBatchReport({
            dusdUsm: dusdUsm,
            dusdUsmImplementation: dusdUsmImplementation,
            fixedPriceStrategy: fixedPriceStrategy,
            fixedFeeStrategy: fixedFeeStrategy
        });
    }

    function getReport() public view returns (TestnetUsmBatchReport memory) {
        return report;
    }
}

