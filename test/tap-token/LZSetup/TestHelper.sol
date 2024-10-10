// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DoubleEndedQueue} from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";

import {UlnConfig, SetDefaultUlnConfigParam} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import {
    SetDefaultExecutorConfigParam,
    ExecutorConfig
} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/SendLibBase.sol";
import {ReceiveUln302} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/uln302/ReceiveUln302.sol";
import {IDVN} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/interfaces/IDVN.sol";
import {DVN, ExecuteParam} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/dvn/DVN.sol";
import {DVNFeeLib} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/dvn/DVNFeeLib.sol";
import {IExecutor} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/interfaces/IExecutor.sol";
import {Executor} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/Executor.sol";
import {PriceFeed} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/PriceFeed.sol";
import {ILayerZeroPriceFeed} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/interfaces/ILayerZeroPriceFeed.sol";
import {IReceiveUlnE2} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/interfaces/IReceiveUlnE2.sol";
import {ReceiveUln302} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/uln302/ReceiveUln302.sol";
import {IMessageLib} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLib.sol";
import {EndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/EndpointV2.sol";
import {ExecutorOptions} from "@layerzerolabs/lz-evm-protocol-v2/contracts/messagelib/libs/ExecutorOptions.sol";
import {PacketV1Codec} from "@layerzerolabs/lz-evm-protocol-v2/contracts/messagelib/libs/PacketV1Codec.sol";
import {Origin} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {OApp} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import {OptionsHelper} from "./mocks/OptionsHelper.sol";
import {SendUln302Mock as SendUln302} from "./mocks/SendUln302Mock.sol";
import {SimpleMessageLibMock} from "./mocks/SimpleMessageLibMock.sol";
import "./mocks/ExecutorFeeLibMock.sol";

// solhint-disable-next-line
import "forge-std/console.sol";

contract TestHelper is Test, OptionsHelper {
    using OptionsBuilder for bytes;

    enum LibraryType {
        UltraLightNode,
        SimpleMessageLib
    }

    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;
    using PacketV1Codec for bytes;

    struct EndpointSetup {
        EndpointV2 endpoint;
        SendUln302 sendUln;
        ReceiveUln302 receiveUln;
        Executor executor;
        DVN dvn;
    }

    struct PacketValidation {
        uint32 dstEid;
        address receiveLib;
        ReceiveUln302 dstUln;
        DVN dvn;
        bytes packetHeader;
        bytes32 payloadHash;
    }

    mapping(uint32 => mapping(bytes32 => DoubleEndedQueue.Bytes32Deque)) packetsQueue; // dstEid => dstUA => guids queue
    mapping(bytes32 => bytes) packets; // guid => packet bytes
    mapping(bytes32 => bytes) optionsLookup; // guid => options

    mapping(uint32 => address) endpoints; // eid => endpoint

    uint256 public constant TREASURY_GAS_CAP = 1000000000000;
    uint256 public constant TREASURY_GAS_FOR_FEE_CAP = 100000;

    uint128 public executorValueCap = 0.1 ether;

    function setUp() public virtual {}

    function setExecutorValueCap(uint128 _valueCap) public {
        executorValueCap = _valueCap;
    }

    function setUpEndpoints(uint8 _endpointNum, LibraryType _libraryType) public {
        EndpointV2[] memory endpointList = new EndpointV2[](_endpointNum);
        EndpointSetup[] memory setups = new EndpointSetup[](_endpointNum);

        PriceFeed priceFeed = new PriceFeed();
        priceFeed.initialize(address(this));

        for (uint8 i = 0; i < _endpointNum; i++) {
            endpointList[i] = new EndpointV2(i + 1, address(this));
            registerEndpoint(endpointList[i]);

            if (_libraryType == LibraryType.UltraLightNode) {
                setups[i] = _setupUltraLightNode(endpointList[i], priceFeed, i, _endpointNum);
                _configureUltraLightNode(setups[i], priceFeed, _endpointNum, i);
            } else if (_libraryType == LibraryType.SimpleMessageLib) {
                setups[i] = _setupSimpleMessageLib(endpointList[i]);
            } else {
                revert("invalid library type");
            }
        }

        _configureEndpoints(endpointList, setups);
    }

    function _setupUltraLightNode(EndpointV2 endpoint, PriceFeed priceFeed, uint8 i, uint8 _endpointNum)
        internal
        returns (EndpointSetup memory setup)
    {
        setup.endpoint = endpoint;
        setup.sendUln = new SendUln302(payable(this), address(endpoint), TREASURY_GAS_CAP, TREASURY_GAS_FOR_FEE_CAP);
        setup.receiveUln = new ReceiveUln302(address(endpoint));
        endpoint.registerLibrary(address(setup.sendUln));
        endpoint.registerLibrary(address(setup.receiveUln));

        setup.executor = new Executor();
        _setupExecutor(setup, priceFeed);

        setup.dvn = _setupDVN(setup, i, _endpointNum, priceFeed);

        return setup;
    }

    function _setupExecutor(EndpointSetup memory setup, PriceFeed priceFeed) internal {
        address[] memory admins = new address[](1);
        admins[0] = address(this);

        address[] memory messageLibs = new address[](2);
        messageLibs[0] = address(setup.sendUln);
        messageLibs[1] = address(setup.receiveUln);

        setup.executor.initialize(
            address(setup.endpoint), address(0x0), messageLibs, address(priceFeed), address(this), admins
        );
        ExecutorFeeLib executorLib = new ExecutorFeeLibMock();
        setup.executor.setWorkerFeeLib(address(executorLib));
    }

    function _setupDVN(EndpointSetup memory setup, uint8 i, uint8 _endpointNum, PriceFeed priceFeed)
        internal
        returns (DVN dvn)
    {
        address[] memory signers = new address[](1);
        signers[0] = vm.addr(1);
        address[] memory admins = new address[](1);
        admins[0] = address(this);

        address[] memory messageLibs = new address[](2);
        messageLibs[0] = address(setup.sendUln);
        messageLibs[1] = address(setup.receiveUln);

        dvn = new DVN(i + 1, messageLibs, address(priceFeed), signers, 1, admins);
        DVNFeeLib dvnLib = new DVNFeeLib(1e18);
        dvn.setWorkerFeeLib(address(dvnLib));

        return dvn;
    }

    function _setupSimpleMessageLib(EndpointV2 endpoint) internal returns (EndpointSetup memory setup) {
        address messageLib = address(new SimpleMessageLibMock(payable(this), address(endpoint)));
        endpoint.registerLibrary(messageLib);

        setup.endpoint = endpoint;
        setup.sendUln = SendUln302(payable(messageLib));
        setup.receiveUln = ReceiveUln302(payable(messageLib));

        return setup;
    }

    function _configureUltraLightNode(
        EndpointSetup memory setup,
        PriceFeed priceFeed,
        uint8 _endpointNum,
        uint8 currentEid
    ) internal {
        IExecutor.DstConfigParam[] memory dstConfigParams = new IExecutor.DstConfigParam[](_endpointNum);
        IDVN.DstConfigParam[] memory dvnConfigParams = new IDVN.DstConfigParam[](_endpointNum);

        for (uint8 j = 0; j < _endpointNum; j++) {
            if (currentEid == j) continue;
            uint32 dstEid = j + 1;

            dstConfigParams[j] = IExecutor.DstConfigParam({
                dstEid: dstEid,
                lzReceiveBaseGas: 5000,
                lzComposeBaseGas: 5000,
                multiplierBps: 10000,
                floorMarginUSD: 1e10,
                nativeCap: executorValueCap
            });

            dvnConfigParams[j] =
                IDVN.DstConfigParam({dstEid: dstEid, gas: 5000, multiplierBps: 10000, floorMarginUSD: 1e10});

            _configureUln(setup.sendUln, setup.receiveUln, setup.dvn, setup.executor, dstEid);

            _setPriceFeed(priceFeed, dstEid);
        }

        setup.executor.setDstConfig(dstConfigParams);
        setup.dvn.setDstConfig(dvnConfigParams);
    }

    function _configureUln(SendUln302 sendUln, ReceiveUln302 receiveUln, DVN dvn, Executor executor, uint32 dstEid)
        internal
    {
        address[] memory defaultDVNs = new address[](1);
        address[] memory optionalDVNs = new address[](0);
        defaultDVNs[0] = address(dvn);

        // Configure send ULN
        {
            SetDefaultUlnConfigParam[] memory params = new SetDefaultUlnConfigParam[](1);
            UlnConfig memory ulnConfig =
                UlnConfig(100, uint8(defaultDVNs.length), uint8(optionalDVNs.length), 0, defaultDVNs, optionalDVNs);
            params[0] = SetDefaultUlnConfigParam(dstEid, ulnConfig);
            sendUln.setDefaultUlnConfigs(params);
        }

        // Configure send executor
        {
            SetDefaultExecutorConfigParam[] memory params = new SetDefaultExecutorConfigParam[](1);
            ExecutorConfig memory executorConfig = ExecutorConfig(10000, address(executor));
            params[0] = SetDefaultExecutorConfigParam(dstEid, executorConfig);
            sendUln.setDefaultExecutorConfigs(params);
        }

        // Configure receive ULN
        {
            SetDefaultUlnConfigParam[] memory params = new SetDefaultUlnConfigParam[](1);
            UlnConfig memory ulnConfig =
                UlnConfig(100, uint8(defaultDVNs.length), uint8(optionalDVNs.length), 0, defaultDVNs, optionalDVNs);
            params[0] = SetDefaultUlnConfigParam(dstEid, ulnConfig);
            receiveUln.setDefaultUlnConfigs(params);
        }
    }

    function _setPriceFeed(PriceFeed priceFeed, uint32 dstEid) internal {
        ILayerZeroPriceFeed.UpdatePrice[] memory prices = new ILayerZeroPriceFeed.UpdatePrice[](1);
        prices[0] = ILayerZeroPriceFeed.UpdatePrice(
            dstEid, ILayerZeroPriceFeed.Price(1 * priceFeed.getPriceRatioDenominator(), 1, 1)
        );
        priceFeed.setPrice(prices);
    }

    function _configureEndpoints(EndpointV2[] memory endpointList, EndpointSetup[] memory setups) internal {
        uint8 _endpointNum = uint8(endpointList.length);

        for (uint8 i = 0; i < _endpointNum; i++) {
            EndpointV2 endpoint = endpointList[i];
            for (uint8 j = 0; j < _endpointNum; j++) {
                if (i == j) continue;
                endpoint.setDefaultSendLibrary(j + 1, address(setups[i].sendUln));
                endpoint.setDefaultReceiveLibrary(j + 1, address(setups[i].receiveUln), 0);
            }
        }
    }

    function setupOApps(bytes memory _oappCreationCode, uint8 _startEid, uint8 _oappNum)
        public
        returns (address[] memory oapps)
    {
        oapps = new address[](_oappNum);
        for (uint8 eid = _startEid; eid < _startEid + _oappNum; eid++) {
            address oapp = _deployOApp(_oappCreationCode, abi.encode(address(endpoints[eid]), address(this), true));
            oapps[eid - _startEid] = oapp;
        }
        // config
        wireOApps(oapps);
    }

    function wireOApps(address[] memory oapps) public {
        uint256 size = oapps.length;
        for (uint256 i = 0; i < size; i++) {
            OApp localOApp = OApp(payable(oapps[i]));
            for (uint256 j = 0; j < size; j++) {
                if (i == j) continue;
                OApp remoteOApp = OApp(payable(oapps[j]));
                uint32 remoteEid = (remoteOApp.endpoint()).eid();
                localOApp.setPeer(remoteEid, addressToBytes32(address(remoteOApp)));
            }
        }
    }

    function _deployOApp(bytes memory _oappBytecode, bytes memory _constructorArgs) internal returns (address addr) {
        bytes memory bytecode = bytes.concat(abi.encodePacked(_oappBytecode), _constructorArgs);
        assembly {
            addr := create(0, add(bytecode, 0x20), mload(bytecode))
            if iszero(extcodesize(addr)) { revert(0, 0) }
        }
    }

    function schedulePacket(bytes calldata _packetBytes, bytes calldata _options) public {
        uint32 dstEid = _packetBytes.dstEid();
        bytes32 dstAddress = _packetBytes.receiver();
        DoubleEndedQueue.Bytes32Deque storage queue = packetsQueue[dstEid][dstAddress];
        // front in, back out
        bytes32 guid = _packetBytes.guid();
        queue.pushFront(guid);
        packets[guid] = _packetBytes;
        optionsLookup[guid] = _options;
    }

    function verifyPackets(uint32 _dstEid, bytes32 _dstAddress) public {
        verifyPackets(_dstEid, _dstAddress, 0, address(0x0));
    }

    function verifyPackets(uint32 _dstEid, address _dstAddress) public {
        verifyPackets(_dstEid, bytes32(uint256(uint160(_dstAddress))), 0, address(0x0));
    }

    function verifyPackets(uint32 _dstEid, bytes32 _dstAddress, uint256 _packetAmount, address _composer) public {
        require(endpoints[_dstEid] != address(0), "endpoint not yet registered");

        DoubleEndedQueue.Bytes32Deque storage queue = packetsQueue[_dstEid][_dstAddress];
        uint256 pendingPacketsSize = queue.length();
        uint256 numberOfPackets;
        if (_packetAmount == 0) {
            numberOfPackets = queue.length();
        } else {
            numberOfPackets = pendingPacketsSize > _packetAmount ? _packetAmount : pendingPacketsSize;
        }
        while (numberOfPackets > 0) {
            numberOfPackets--;
            // front in, back out
            bytes32 guid = queue.popBack();
            bytes memory packetBytes = packets[guid];
            this.assertGuid(packetBytes, guid);
            this.validatePacket(packetBytes);

            bytes memory options = optionsLookup[guid];
            if (_executorOptionExists(options, ExecutorOptions.OPTION_TYPE_NATIVE_DROP)) {
                (uint256 amount, bytes32 receiver) = _parseExecutorNativeDropOption(options);
                address to = address(uint160(uint256(receiver)));
                (bool sent,) = to.call{value: amount}("");
                require(sent, "Failed to send Ether");
            }
            if (_executorOptionExists(options, ExecutorOptions.OPTION_TYPE_LZRECEIVE)) {
                this.lzReceive(packetBytes, options);
            }
            if (_composer != address(0) && _executorOptionExists(options, ExecutorOptions.OPTION_TYPE_LZCOMPOSE)) {
                this.lzCompose(packetBytes, options, guid, _composer);
            }
        }
    }

    function lzReceive(bytes calldata _packetBytes, bytes memory _options) external payable {
        EndpointV2 endpoint = EndpointV2(endpoints[_packetBytes.dstEid()]);
        (uint256 gas, uint256 value) = OptionsHelper._parseExecutorLzReceiveOption(_options);

        Origin memory origin = Origin(_packetBytes.srcEid(), _packetBytes.sender(), _packetBytes.nonce());
        endpoint.lzReceive{value: value, gas: gas}(
            origin, _packetBytes.receiverB20(), _packetBytes.guid(), _packetBytes.message(), bytes("")
        );
    }

    function lzCompose(bytes calldata _packetBytes, bytes memory _options, bytes32 _guid, address _composer)
        external
        payable
    {
        this.lzCompose(
            _packetBytes.dstEid(), _packetBytes.receiverB20(), _options, _guid, _composer, _packetBytes.message()
        );
    }

    function lzCompose(
        uint32 _dstEid,
        address _from,
        bytes memory _options,
        bytes32 _guid,
        address _to,
        bytes calldata _composerMsg
    ) external payable {
        EndpointV2 endpoint = EndpointV2(endpoints[_dstEid]);
        (uint16 index, uint256 gas, uint256 value) = _parseExecutorLzComposeOption(_options);
        endpoint.lzCompose{value: value, gas: gas}(_from, _to, _guid, index, _composerMsg, bytes(""));
    }

    function validatePacket(bytes calldata _packetBytes) external {
        uint32 dstEid = _packetBytes.dstEid();
        EndpointV2 endpoint = EndpointV2(endpoints[dstEid]);
        (address receiveLib,) = endpoint.getReceiveLibrary(_packetBytes.receiverB20(), _packetBytes.srcEid());
        ReceiveUln302 dstUln = ReceiveUln302(receiveLib);

        (uint64 major,,) = IMessageLib(receiveLib).version();
        if (major == 3) {
            // it is ultra light node
            bytes memory config = dstUln.getConfig(_packetBytes.srcEid(), _packetBytes.receiverB20(), 2); // CONFIG_TYPE_ULN
            DVN dvn = DVN(abi.decode(config, (UlnConfig)).requiredDVNs[0]);

            bytes memory packetHeader = _packetBytes.header();
            bytes32 payloadHash = keccak256(_packetBytes.payload());

            // sign
            bytes memory signatures;
            bytes memory verifyCalldata =
                abi.encodeWithSelector(IReceiveUlnE2.verify.selector, packetHeader, payloadHash, 100);
            {
                bytes32 hash = dvn.hashCallData(dstEid, address(dstUln), verifyCalldata, block.timestamp + 1000);
                bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
                (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, ethSignedMessageHash); // matches dvn signer
                signatures = abi.encodePacked(r, s, v);
            }
            ExecuteParam[] memory params = new ExecuteParam[](1);
            params[0] = ExecuteParam(dstEid, address(dstUln), verifyCalldata, block.timestamp + 1000, signatures);
            dvn.execute(params);

            // commit verification
            bytes memory callData =
                abi.encodeWithSelector(IReceiveUlnE2.commitVerification.selector, packetHeader, payloadHash);
            {
                bytes32 hash = dvn.hashCallData(dstEid, address(dstUln), callData, block.timestamp + 1000);
                bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
                (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, ethSignedMessageHash); // matches dvn signer
                signatures = abi.encodePacked(r, s, v);
            }
            params[0] = ExecuteParam(dstEid, address(dstUln), callData, block.timestamp + 1000, signatures);
            dvn.execute(params);
        } else {
            SimpleMessageLibMock(payable(receiveLib)).validatePacket(_packetBytes);
        }
    }

    function assertGuid(bytes calldata packetBytes, bytes32 guid) external pure {
        bytes32 packetGuid = packetBytes.guid();
        require(packetGuid == guid, "guid not match");
    }

    function registerEndpoint(EndpointV2 endpoint) public {
        endpoints[endpoint.eid()] = address(endpoint);
    }

    function hasPendingPackets(uint16 _dstEid, bytes32 _dstAddress) public view returns (bool flag) {
        DoubleEndedQueue.Bytes32Deque storage queue = packetsQueue[_dstEid][_dstAddress];
        return queue.length() > 0;
    }

    function getNextInflightPacket(uint16 _dstEid, bytes32 _dstAddress)
        public
        view
        returns (bytes memory packetBytes)
    {
        DoubleEndedQueue.Bytes32Deque storage queue = packetsQueue[_dstEid][_dstAddress];
        if (queue.length() > 0) {
            bytes32 guid = queue.back();
            packetBytes = packets[guid];
        }
    }

    function addressToBytes32(address _addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }

    receive() external payable {}
}
