// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// contracts
import {UsdoInitStruct, UsdoModulesInitStruct} from "tap-utils/interfaces/oft/IUsdo.sol";
import {IPearlmit, Pearlmit} from "tap-utils/pearlmit/Pearlmit.sol";
import {TokenType} from "yieldbox/enums/YieldBoxTokenType.sol";
import {IStrategy} from "yieldbox/interfaces/IStrategy.sol";
import {Cluster} from "tap-utils/Cluster/Cluster.sol";
import {YieldBox} from "yieldbox/YieldBox.sol";
import {Penrose} from "tapioca-bar/Penrose.sol";

import {TapiocaOmnichainExtExec} from "tap-utils/tapiocaOmnichainEngine/extension/TapiocaOmnichainExtExec.sol";
import {IUsdo, UsdoInitStruct, UsdoModulesInitStruct} from "tap-utils/interfaces/oft/IUsdo.sol";
import {UsdoMarketReceiverModule} from "tapioca-bar/usdo/modules/UsdoMarketReceiverModule.sol";
import {UsdoOptionReceiverModule} from "tapioca-bar/usdo/modules/UsdoOptionReceiverModule.sol";
import {UsdoReceiver} from "tapioca-bar/usdo/modules/UsdoReceiver.sol";
import {UsdoSender} from "tapioca-bar/usdo/modules/UsdoSender.sol";
import {Usdo} from "tapioca-bar/usdo/Usdo.sol";

// tests
import {TestHelper} from "../LZSetup/TestHelper.sol";
import {Events} from "./utils/Events.sol";
import {Utils} from "./utils/Utils.sol";
import {Types} from "./utils/Types.sol";

import {MagnetarMock_test} from "./mocks/MagnetarMock_test.sol";
import {ERC20Mock_test} from "./mocks/ERC20Mock_test.sol";
import {TOFTMock_test} from "./mocks/TOFTMock_test.sol";

abstract contract Base_Test is TestHelper, Utils, Types, Events {
    // ************ //
    // *** VARS *** //
    // ************ //
    // endpoints
    uint32 public aEid = 1;
    uint32 public bEid = 2;

    // users
    address public userA;
    address public userB;
    address public userC;
    uint256 public initialBalance = LARGE_AMOUNT;

    // common general storage
    Cluster cluster;
    Penrose penrose;
    MagnetarMock_test magnetar; // same as the original; avoids a new foundry reference

    // tokens
    ERC20Mock_test mainTokenErc20; // used as the main token underlying erc20
    TOFTMock_test mainToken; // used as the main token in Penrose

    ERC20Mock_test tapToken; // no need for real TAP; used only to simulate fees

    Usdo usdo;

    UsdoSender usdoSender;
    UsdoReceiver usdoReceiver;
    UsdoMarketReceiverModule usdoMarketReceiverModule;
    UsdoOptionReceiverModule usdoOptionsReceiverModule;

    Usdo secondaryUsdo;

    // ************* //
    // *** SETUP *** //
    // ************* //
    function setUp() public virtual override {
        // ***  *** //
        userA = _createUser(USER_A_PKEY, "User A");
        userB = _createUser(USER_B_PKEY, "User B");
        userC = _createUser(USER_C_PKEY, "User C");

        // setup 3 LZ endpoints
        setUpEndpoints(3, LibraryType.UltraLightNode);

        // create mock main token
        mainTokenErc20 = _createToken("MainTokenErc20");
        // create mock tap token
        tapToken = _createToken("TapToken");

        // create real Cluster
        cluster = _createCluster(address(this));

        mainToken = new TOFTMock_test(address(mainTokenErc20));
        vm.label(address(mainToken), "MainToken TOFT");

        magnetar = new MagnetarMock_test(address(cluster));
        vm.label(address(magnetar), "MagnetarMock_test");

        // create real Penrose
        penrose = _createPenrose({
            _cluster: address(cluster),
            _tapToken: address(tapToken),
            _mainToken: address(mainToken),
            _owner: address(this)
        });

        // create real USDO
        TapiocaOmnichainExtExec extExec = new TapiocaOmnichainExtExec();
        vm.label(address(extExec), "TapiocaOmnichainExtExec");

        UsdoInitStruct memory usdoInitStruct = UsdoInitStruct({
            endpoint: address(endpoints[aEid]),
            delegate: address(this),
            cluster: address(cluster),
            extExec: address(extExec)
        });
        usdoSender = new UsdoSender(usdoInitStruct);
        usdoReceiver = new UsdoReceiver(usdoInitStruct);
        usdoMarketReceiverModule = new UsdoMarketReceiverModule(usdoInitStruct);
        usdoOptionsReceiverModule = new UsdoOptionReceiverModule(usdoInitStruct);
        vm.label(address(usdoSender), "Usdo Sender");
        vm.label(address(usdoReceiver), "Usdo Receiver");
        vm.label(address(usdoMarketReceiverModule), "Usdo Market Receiver Module");
        vm.label(address(usdoOptionsReceiverModule), "Usdo Options Receiver Module");

        UsdoModulesInitStruct memory usdoModulesInitStruct = UsdoModulesInitStruct({
            usdoSenderModule: address(usdoSender),
            usdoReceiverModule: address(usdoReceiver),
            marketReceiverModule: address(usdoMarketReceiverModule),
            optionReceiverModule: address(usdoOptionsReceiverModule)
        });
        usdo = Usdo(payable(_deployOApp(type(Usdo).creationCode, abi.encode(usdoInitStruct, usdoModulesInitStruct))));
        vm.label(address(usdo), "Usdo");

        // create secondary real Usdo
        usdoInitStruct = UsdoInitStruct({
            endpoint: address(endpoints[bEid]),
            delegate: address(this),
            cluster: address(cluster),
            extExec: address(extExec)
        });
        UsdoSender secondaryUsdoSender = new UsdoSender(usdoInitStruct);
        UsdoReceiver secondaryUsdoReceiver = new UsdoReceiver(usdoInitStruct);
        UsdoMarketReceiverModule secondaryUsdoMarketReceiverModule = new UsdoMarketReceiverModule(usdoInitStruct);
        UsdoOptionReceiverModule secondaryUsdoOptionsReceiverModule = new UsdoOptionReceiverModule(usdoInitStruct);
        vm.label(address(secondaryUsdoSender), "Secondary Usdo Sender");
        vm.label(address(secondaryUsdoReceiver), "Secondary Usdo Receiver");
        vm.label(address(secondaryUsdoMarketReceiverModule), "Secondary Usdo Market Receiver");
        vm.label(address(secondaryUsdoOptionsReceiverModule), "Secondary Usdo Options Receiver");
        usdoModulesInitStruct = UsdoModulesInitStruct({
            usdoSenderModule: address(secondaryUsdoSender),
            usdoReceiverModule: address(secondaryUsdoReceiver),
            marketReceiverModule: address(secondaryUsdoMarketReceiverModule),
            optionReceiverModule: address(secondaryUsdoOptionsReceiverModule)
        });
        secondaryUsdo =
            Usdo(payable(_deployOApp(type(Usdo).creationCode, abi.encode(usdoInitStruct, usdoModulesInitStruct))));
        vm.label(address(secondaryUsdo), "Secondary Usdo");

        // *** AFTER DEPLOYMENT *** //

        // config and wire the ofts
        address[] memory ofts = new address[](2);
        ofts[0] = address(usdo);
        ofts[1] = address(secondaryUsdo);
        this.wireOApps(ofts);

        // set Usdo token on Penrose
        penrose.setUsdoToken(address(usdo));
        // set BB default debt rate
        penrose.setBigBangEthMarketDebtRate(DEFAULT_PENROSE_DEBT_RATE);

        cluster.setRoleForContract(address(this), keccak256("LIQUIDATOR"), true);

        deal(address(mainTokenErc20), address(mainToken), type(uint128).max);
    }

    // ***************** //
    // *** MODIFIERS *** //
    // ***************** //

    /// @notice Modifier to approve an operator via regular ERC20.
    modifier whenApprovedViaERC20(address _token, address _from, address _operator, uint256 _amount) {
        _approveViaERC20({token: _token, from: _from, operator: _operator, amount: _amount});
        _;
    }

    /// @notice Modifier to changea user's prank.
    modifier resetPrank(address user) {
        _resetPrank(user);
        _;
    }

    /// @notice Modifier to verify a value is not zero.
    modifier assumeNoZeroValue(uint256 value) {
        vm.assume(value != 0);
        _;
    }

    /// @notice Modifier to verify a value is greater than or equal to a certain number.
    modifier assumeGtE(uint256 value, uint256 toCompare) {
        vm.assume(value >= toCompare);
        _;
    }

    /// @notice Modifier to verify a value is less than or equal to a certain number.
    modifier assumeLtE(uint256 value, uint256 toCompare) {
        vm.assume(value <= toCompare);
        _;
    }

    /// @notice Modifier to verify a value is less than or equal to a minimum and greater than or equal to a maximum
    /// @dev combined version of `assumeLtE` and `assumeGtE`
    modifier assumeRange(uint256 value, uint256 min, uint256 max) {
        vm.assume(value >= min && value <= max);
        _;
    }

    modifier whenWhitelisted(address _addy) {
        cluster.updateContract(0, _addy, true);
        _;
    }
}
