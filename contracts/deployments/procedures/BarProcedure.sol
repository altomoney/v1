// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Penrose} from "tapioca-bar/Penrose.sol";
import {UsdoSender} from "tapioca-bar/usdo/modules/UsdoSender.sol";
import {UsdoReceiver} from "tapioca-bar/usdo/modules/UsdoReceiver.sol";
import {UsdoMarketReceiverModule} from "tapioca-bar/usdo/modules/UsdoMarketReceiverModule.sol";
import {UsdoOptionReceiverModule} from "tapioca-bar/usdo/modules/UsdoOptionReceiverModule.sol";
import {Usdo} from "tapioca-bar/usdo/Usdo.sol";
import {TapiocaOmnichainExtExec} from "tap-utils/tapiocaOmnichainEngine/extension/TapiocaOmnichainExtExec.sol";
import {
    UsdoReport,
    UsdoModulesReport,
    UsdoMarketModulesReport,
    PenroseReport,
    BBReport,
    IPenroseInput
} from "../interfaces/ITapiocaReport.sol";

import {ICluster} from "tap-utils/interfaces/periph/ICluster.sol";
import {IMagnetarHelper} from "tap-utils/interfaces/periph/IMagnetarHelper.sol";
import {IERC20} from "@boringcrypto/boring-solidity/contracts/libraries/BoringERC20.sol";
import {UsdoInitStruct, UsdoModulesInitStruct} from "tap-utils/interfaces/oft/IUsdo.sol";
import {UsdoHelper} from "tapioca-bar/usdo/extensions/UsdoHelper.sol";
import {USDOFlashloanHelper} from "tapioca-bar/usdo/USDOFlashloanHelper.sol";
import {IUsdo} from "tap-utils/interfaces/oft/IUsdo.sol";
import {MarketHelper} from "tapioca-bar/markets/MarketHelper.sol";
import {BBLeverage} from "tapioca-bar/markets/bigBang/BBLeverage.sol";
import {BBDebtRateHelper} from "tapioca-bar/markets/bigBang/BBDebtRateHelper.sol";
import {BigBang} from "tapioca-bar/markets/bigBang/BigBang.sol";
import {BBDebtRateHelper} from "tapioca-bar/markets/bigBang/BBDebtRateHelper.sol";
import {IPenrose} from "tap-utils/interfaces/bar/IPenrose.sol";

abstract contract BarProcedure {
    function _deployPenrose(IPenroseInput memory input) internal returns (PenroseReport memory report) {
        report.marketHelper = address(new MarketHelper());
        if (input.prevPenrose == address(0)) {
            report.penrose = address(
                new Penrose(
                    ICluster(input.cluster),
                    IERC20(input.tapToken),
                    IERC20(input.nativeWrappedToken),
                    address(this) // set owner temporarily for setup
                )
            );
            Penrose(report.penrose).setUsdoToken(input.usdoToken);
            Penrose(report.penrose).registerBigBangMasterContract(
                input.bigbangMaster, IPenrose.ContractType.mediumRisk
            );
            Penrose(report.penrose).registerSingularityMasterContract(
                input.singularityMaster, IPenrose.ContractType.mediumRisk
            );
            Penrose(report.penrose).setMarketApprovalBypassContract(input.magnetar, true);
            Penrose(report.penrose).transferOwnership(input.owner);
        } else {
            report.penrose = input.prevPenrose;
        }
    }

    function _deployUsdoSenderAndReceiver(address endpoint, address delegate, address cluster, address extExec)
        internal
        returns (UsdoModulesReport memory report)
    {
        UsdoInitStruct memory initData;

        initData.endpoint = endpoint;
        initData.delegate = delegate;
        initData.cluster = cluster;
        initData.extExec = extExec;

        report.usdoSenderModule = address(new UsdoSender(initData));
        report.usdoReceiverModule = address(new UsdoReceiver(initData));

        return report;
    }

    function _deployUsdoMarketModules(address endpoint, address delegate, address cluster, address extExec)
        internal
        returns (UsdoMarketModulesReport memory report)
    {
        UsdoInitStruct memory initData;

        initData.endpoint = endpoint;
        initData.delegate = delegate;
        initData.cluster = cluster;
        initData.extExec = extExec;

        report.marketReceiverModule = address(new UsdoMarketReceiverModule(initData));
        report.optionReceiverModule = address(new UsdoOptionReceiverModule(initData));

        return report;
    }

    function _deployUsdo(
        address endpoint,
        address delegate,
        address cluster,
        address extExec,
        address usdoSenderModule,
        address usdoReceiverModule,
        address usdoMarketReceiverModule,
        address usdoOptionReceiverModule
    ) internal returns (UsdoReport memory report) {
        UsdoInitStruct memory initData;
        UsdoModulesInitStruct memory modulesData;

        initData.endpoint = endpoint;
        initData.delegate = address(this);
        initData.cluster = cluster;
        initData.extExec = extExec;

        modulesData.usdoSenderModule = usdoSenderModule;
        modulesData.usdoReceiverModule = usdoReceiverModule;
        modulesData.marketReceiverModule = usdoMarketReceiverModule;
        modulesData.optionReceiverModule = usdoOptionReceiverModule;
        report.usdo = (address(new Usdo(initData, modulesData)));
        report.usdoFlashloanHelper = address(new USDOFlashloanHelper(IUsdo(report.usdo), delegate));
        report.usdoHelper = address(new UsdoHelper());

        Usdo(payable(report.usdo)).setFlashloanHelper(report.usdoFlashloanHelper);
        Usdo(payable(report.usdo)).setMinterStatus(report.usdoFlashloanHelper, true);
        Usdo(payable(report.usdo)).setBurnerStatus(report.usdoFlashloanHelper, true);

        // Transfer ownership to the delegate
        Usdo(payable(report.usdo)).setDelegate(delegate);
        Usdo(payable(report.usdo)).transferOwnership(delegate);

        return report;
    }

    function _deployBBModulesThree(BBReport memory report) internal returns (BBReport memory) {
        report.bigbang = address(new BigBang());
        return report;
    }
}
