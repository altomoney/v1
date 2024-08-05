// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {Penrose} from "tapioca-bar/Penrose.sol";
import {UsdoSender} from "tapioca-bar/usdo/modules/UsdoSender.sol";
import {UsdoReceiver} from "tapioca-bar/usdo/modules/UsdoReceiver.sol";
import {UsdoMarketReceiverModule} from "tapioca-bar/usdo/modules/UsdoMarketReceiverModule.sol";
import {UsdoOptionReceiverModule} from "tapioca-bar/usdo/modules/UsdoOptionReceiverModule.sol";
import {Usdo} from "tapioca-bar/usdo/Usdo.sol";
import {TapiocaOmnichainExtExec} from "tap-utils/tapiocaOmnichainEngine/extension/TapiocaOmnichainExtExec.sol";
import {UsdoReport, UsdoModulesReport, UsdoMarketModulesReport} from "../interfaces/ITapiocaReport.sol";
import {IPearlmit} from "tap-utils/pearlmit/PearlmitHandler.sol";
import {ICluster} from "tap-utils/interfaces/periph/ICluster.sol";
import {IMagnetarHelper} from "tap-utils/interfaces/periph/IMagnetarHelper.sol";
import {IYieldBox} from "yieldbox/interfaces/IYieldBox.sol";
import {IERC20} from "@boringcrypto/boring-solidity/contracts/libraries/BoringERC20.sol";
import {UsdoInitStruct, UsdoModulesInitStruct} from "tap-utils/interfaces/oft/IUsdo.sol";

abstract contract BarProcedure {
    function _deployPenrose(
        address owner,
        address yieldbox,
        address cluster,
        address tapToken,
        address nativeWrappedToken,
        address pearlmit,
        uint256 tapAssetId,
        uint256 wrappedTokenId,
        uint256 usdoId,
        address usdoToken
    ) internal returns (address penrose) {
        penrose = address(
            new Penrose(
                IYieldBox(yieldbox),
                ICluster(cluster),
                IERC20(tapToken),
                IERC20(nativeWrappedToken),
                IPearlmit(pearlmit),
                tapAssetId,
                wrappedTokenId,
                owner
            )
        );
        Penrose(penrose).setUsdoToken(usdoToken, usdoId);
    }

    function _deployUsdoSenderAndReceiver(
        address endpoint,
        address delegate,
        address yieldbox,
        address cluster,
        address extExec,
        address pearlmit
    ) internal returns (UsdoModulesReport memory report) {
        UsdoInitStruct memory initData;

        initData.endpoint = endpoint;
        initData.delegate = delegate;
        initData.yieldBox = yieldbox;
        initData.cluster = cluster;
        initData.extExec = extExec;
        initData.pearlmit = IPearlmit(pearlmit);

        report.usdoSenderModule = address(new UsdoSender(initData));
        report.usdoReceiverModule = address(new UsdoReceiver(initData));

        return report;
    }

    function _deployUsdoMarketModules(
        address endpoint,
        address delegate,
        address yieldbox,
        address cluster,
        address extExec,
        address pearlmit
    ) internal returns (UsdoMarketModulesReport memory report) {
        UsdoInitStruct memory initData;

        initData.endpoint = endpoint;
        initData.delegate = delegate;
        initData.yieldBox = yieldbox;
        initData.cluster = cluster;
        initData.extExec = extExec;
        initData.pearlmit = IPearlmit(pearlmit);

        report.marketReceiverModule = address(new UsdoMarketReceiverModule(initData));
        report.optionReceiverModule = address(new UsdoOptionReceiverModule(initData));

        return report;
    }

    function _deployUsdo(
        address endpoint,
        address delegate,
        address yieldbox,
        address cluster,
        address extExec,
        address pearlmit,
        address usdoSenderModule,
        address usdoReceiverModule,
        address usdoMarketReceiverModule,
        address usdoOptionReceiverModule
    ) internal returns (UsdoReport memory report) {
        UsdoInitStruct memory initData;
        UsdoModulesInitStruct memory modulesData;

        initData.endpoint = endpoint;
        initData.delegate = delegate;
        initData.yieldBox = yieldbox;
        initData.cluster = cluster;
        initData.extExec = extExec;
        initData.pearlmit = IPearlmit(pearlmit);

        modulesData.usdoSenderModule = usdoSenderModule;
        modulesData.usdoReceiverModule = usdoReceiverModule;
        modulesData.marketReceiverModule = usdoMarketReceiverModule;
        modulesData.optionReceiverModule = usdoOptionReceiverModule;

        report.usdo = (address(new Usdo(initData, modulesData)));
        return report;
    }
}
