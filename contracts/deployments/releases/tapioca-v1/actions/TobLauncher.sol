// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {AltoRelease} from "deployments/releases/tapioca-v1/AltoRelease.sol";
import {AltoReport, TapiocaInput} from "deployments/interfaces/IAltoReport.sol";
import {TapToken, ITapToken} from "contracts/tap-token/tokens/TapToken.sol";
import {ICluster} from "tap-utils/interfaces/periph/ICluster.sol";
import {WETH} from "solady/tokens/WETH.sol";
import {TapiocaOptionBroker} from "tap-token/options/TapiocaOptionBroker.sol";
import {TwTAP} from "tap-token/governance/twTAP.sol";
import {TapiocaMulticall} from "contracts/utils/TapiocaMulticall/TapiocaMulticall.sol";
import {Singularity} from "tapioca-bar/markets/singularity/Singularity.sol";
import {BigBang} from "tapioca-bar/markets/bigBang/BigBang.sol";
import {Bucket} from "tap-token/interfaces/ITWLBase.sol";
import {SeerCLSolo} from "contracts/utils/oracle/SeerCLSolo.sol";
import {OracleChainlinkSingleConstructorData} from "contracts/utils/oracle/OracleChainlinkSingle.sol";
import {TestnetOracle} from "test/utils/mocks/TestnetOracle.sol";
import {ERC20Testnet} from "test/utils/mocks/ERC20Testnet.sol";
import {IERC20} from "@boringcrypto/boring-solidity/contracts/interfaces/IERC20.sol";
import {Usdo} from "tapioca-bar/usdo/Usdo.sol";
import {SGLInit} from "tapioca-bar/markets/singularity/SGLInit.sol";
import {
    TestnetOracles,
    TestnetOraclesBatch
} from "contracts/deployments/releases/tapioca-v1/batches/testnet/TestnetOraclesBatch.sol";

contract TapiocaTestnetTobSetter {
    TapiocaOptionBroker public tob;

    constructor(
        AltoReport memory report,
        address singularityMarket,
        address tapToken,
        address feeCollector,
        address owner,
        address paymentToken,
        address paymentTokenOracle,
        address tapOracle,
        uint256 epochDuration,
        uint256 maxDebtBuffer
    ) {
        _createTapiocaOptionBroker(
            report,
            singularityMarket,
            tapToken,
            feeCollector,
            owner,
            paymentToken,
            paymentTokenOracle,
            tapOracle,
            epochDuration,
            maxDebtBuffer
        );
    }

    function _createTapiocaOptionBroker(
        AltoReport memory report,
        address singularityMarket,
        address tapToken,
        address feeCollector,
        address owner,
        address paymentToken,
        address paymentTokenOracle,
        address tapOracle,
        uint256 epochDuration,
        uint256 maxDebtBuffer
    ) internal {
        Bucket[] memory buckets = new Bucket[](4);

        buckets[0] = Bucket({
            enabled: true,
            lockEpochDuration: 1, // 1 Epoch
            epochGrowthRate: 1,
            epochDecayRate: 1,
            epochCeiling: 100,
            epochFloor: 1,
            rewardsMultiplier: 10_00,
            currentEpochInflows: 0,
            lastEpochInflows: 0,
            growthGoal: 10 ether
        });
        buckets[1] = Bucket({
            enabled: true,
            lockEpochDuration: 2, // 2 Epochs
            epochGrowthRate: 1,
            epochDecayRate: 1,
            epochCeiling: 100,
            epochFloor: 1,
            rewardsMultiplier: 20_00,
            currentEpochInflows: 0,
            lastEpochInflows: 0,
            growthGoal: 20 ether
        });
        buckets[2] = Bucket({
            enabled: true,
            lockEpochDuration: 3, // 3 Epochs
            epochGrowthRate: 1,
            epochDecayRate: 1,
            epochCeiling: 100,
            epochFloor: 1,
            rewardsMultiplier: 35_00,
            currentEpochInflows: 0,
            lastEpochInflows: 0,
            growthGoal: 30 ether
        });
        buckets[3] = Bucket({
            enabled: true,
            lockEpochDuration: 4, // 4 Epochs
            epochGrowthRate: 1,
            epochDecayRate: 1,
            epochCeiling: 100,
            epochFloor: 1,
            rewardsMultiplier: 50_00,
            currentEpochInflows: 0,
            lastEpochInflows: 0,
            growthGoal: 40 ether
        });

        tob = new TapiocaOptionBroker(
            payable(tapToken), address(report.usdo), feeCollector, epochDuration, buckets, address(2), address(this)
        );

        tob.setPaymentToken(address(paymentToken), paymentTokenOracle, "");
        tob.setPaymentTokenBeneficiary(feeCollector);
        tob.setTapOracle(tapOracle, "");
        tob.setCluster(address(1));
        tob.setPenrose(address(2));
        tob.setMaxDebtBuffer(maxDebtBuffer);
        tob.setMarket(singularityMarket, true);

        tob.transferOwnership(owner);
    }
}
