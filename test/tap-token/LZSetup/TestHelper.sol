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

contract TestHelper is Test, OptionsHelper {
    using OptionsBuilder for bytes;

    enum LibraryType {
        UltraLightNode,
        SimpleMessageLib
    }

    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;
    using PacketV1Codec for bytes;

    mapping(uint32 => mapping(bytes32 => DoubleEndedQueue.Bytes32Deque)) packetsQueue; // dstEid => dstUA => guids queue
    mapping(bytes32 => bytes) packets; // guid => packet bytes
    mapping(bytes32 => bytes) optionsLookup; // guid => options
    mapping(uint32 => address) endpoints; // eid => endpoint
    uint256 public constant TREASURY_GAS_CAP = 1000000000000;
    uint256 public constant TREASURY_GAS_FOR_FEE_CAP = 100000;
    uint128 public executorValueCap = 0.1 ether;

    function setUp() public virtual {}
    /**
     * @dev set executorValueCap if more than 0.1 ether is necessary
     * @dev this must be called prior to setUpEndpoints() if the value is to be used
     * @param _valueCap amount executor can pass as msg.value to lzReceive()
     */

    function setExecutorValueCap(uint128 _valueCap) public {
        executorValueCap = _valueCap;
    }

    function _setupDvnParams(
        DVN dvn,
        PriceFeed priceFeed,
        SendUln302 sendUln,
        ReceiveUln302 receiveUln,
        Executor executor,
        uint8 _endpointNum,
        uint8 i
    )
        internal
        returns (IExecutor.DstConfigParam[] memory dstConfigParams, IDVN.DstConfigParam[] memory dvnConfigParams)
    {
        dstConfigParams = new IExecutor.DstConfigParam[](_endpointNum);
        dvnConfigParams = new IDVN.DstConfigParam[](_endpointNum);
        for (uint8 j = 0; j < _endpointNum; j++) {
            if (i == j) continue;
            {
                address[] memory defaultDVNs = new address[](1);
                address[] memory optionalDVNs = new address[](0);
                defaultDVNs[0] = address(dvn);
                SetDefaultUlnConfigParam[] memory params = new SetDefaultUlnConfigParam[](1);
                params[0] = SetDefaultUlnConfigParam(
                    j + 1,
                    UlnConfig(100, uint8(defaultDVNs.length), uint8(optionalDVNs.length), 0, defaultDVNs, optionalDVNs)
                );
                sendUln.setDefaultUlnConfigs(params);
            }
            {
                address[] memory defaultDVNs = new address[](1);
                address[] memory optionalDVNs = new address[](0);
                defaultDVNs[0] = address(dvn);
                SetDefaultExecutorConfigParam[] memory params = new SetDefaultExecutorConfigParam[](1);
                params[0] = SetDefaultExecutorConfigParam(j + 1, ExecutorConfig(10000, address(executor)));
                sendUln.setDefaultExecutorConfigs(params);
            }
            {
                address[] memory defaultDVNs = new address[](1);
                address[] memory optionalDVNs = new address[](0);
                defaultDVNs[0] = address(dvn);
                SetDefaultUlnConfigParam[] memory params = new SetDefaultUlnConfigParam[](1);
                UlnConfig memory ulnConfig =
                    UlnConfig(100, uint8(defaultDVNs.length), uint8(optionalDVNs.length), 0, defaultDVNs, optionalDVNs);
                params[0] = SetDefaultUlnConfigParam(j + 1, ulnConfig);
                receiveUln.setDefaultUlnConfigs(params);
            }
            // executor config
            dstConfigParams[j] = IExecutor.DstConfigParam({
                dstEid: j + 1,
                lzReceiveBaseGas: 5000,
                lzComposeBaseGas: 5000,
                multiplierBps: 10000,
                floorMarginUSD: 1e10,
                nativeCap: executorValueCap
            });
            // dvn config
            dvnConfigParams[j] =
                IDVN.DstConfigParam({dstEid: j + 1, gas: 5000, multiplierBps: 10000, floorMarginUSD: 1e10});
            ILayerZeroPriceFeed.UpdatePrice[] memory prices = new ILayerZeroPriceFeed.UpdatePrice[](1);
            prices[0] = ILayerZeroPriceFeed.UpdatePrice(
                j + 1, ILayerZeroPriceFeed.Price(1 * priceFeed.getPriceRatioDenominator(), 1, 1)
            );
            priceFeed.setPrice(prices);
        }
    }

    function _setupLightNodeEndpoint(EndpointV2 endpoint, PriceFeed priceFeed, uint8 i, uint8 _endpointNum)
        internal
        returns (SendUln302 sendUln, ReceiveUln302 receiveUln)
    {
        Executor executor = new Executor();
        DVN dvn;
        {
            sendUln = new SendUln302(payable(this), address(endpoint), TREASURY_GAS_CAP, TREASURY_GAS_FOR_FEE_CAP);
            receiveUln = new ReceiveUln302(address(endpoint));
            endpoint.registerLibrary(address(sendUln));
            endpoint.registerLibrary(address(receiveUln));
        }
        {
            address[] memory admins = new address[](1);
            admins[0] = address(this);
            address[] memory messageLibs = new address[](2);
            messageLibs[0] = address(sendUln);
            messageLibs[1] = address(receiveUln);
            address[] memory signers = new address[](1);
            signers[0] = vm.addr(1);
            executor.initialize(address(endpoint), address(0x0), messageLibs, address(priceFeed), address(this), admins);
            ExecutorFeeLib executorLib = new ExecutorFeeLibMock();
            executor.setWorkerFeeLib(address(executorLib));

            dvn = new DVN(i + 1, messageLibs, address(priceFeed), signers, 1, admins);
            DVNFeeLib dvnLib = new DVNFeeLib(1e18);
            dvn.setWorkerFeeLib(address(dvnLib));
        }
        (Executor.DstConfigParam[] memory dstConfigParams, IDVN.DstConfigParam[] memory dvnConfigParams) =
            _setupDvnParams(dvn, priceFeed, sendUln, receiveUln, executor, _endpointNum, i);
        executor.setDstConfig(dstConfigParams);
        dvn.setDstConfig(dvnConfigParams);
    }
    /**
     * @dev setup the endpoints
     * @param _endpointNum num of endpoints
     */

    function setUpEndpoints(uint8 _endpointNum, LibraryType _libraryType) public {
        EndpointV2[] memory endpointList = new EndpointV2[](_endpointNum);
        address[] memory sendLibs = new address[](_endpointNum);
        address[] memory receiveLibs = new address[](_endpointNum);

        PriceFeed priceFeed = new PriceFeed();
        priceFeed.initialize(address(this));
        for (uint8 i = 0; i < _endpointNum; i++) {
            endpointList[i] = new EndpointV2(i + 1, address(this));
            registerEndpoint(endpointList[i]);
        }
        for (uint8 i = 0; i < _endpointNum; i++) {
            if (_libraryType == LibraryType.UltraLightNode) {
                {
                    (SendUln302 sendUln, ReceiveUln302 receiveUln) =
                        _setupLightNodeEndpoint(endpointList[i], priceFeed, i, _endpointNum);
                    sendLibs[i] = address(sendUln);
                    receiveLibs[i] = address(receiveUln);
                }
            } else if (_libraryType == LibraryType.SimpleMessageLib) {
                SimpleMessageLibMock messageLib = new SimpleMessageLibMock(payable(this), address(endpointList[i]));
                endpointList[i].registerLibrary(address(messageLib));
                sendLibs[i] = address(messageLib);
                receiveLibs[i] = address(messageLib);
            } else {
                revert("invalid library type");
            }
        }
        // config up
        for (uint8 i = 0; i < _endpointNum; i++) {
            EndpointV2 endpoint = endpointList[i];
            for (uint8 j = 0; j < _endpointNum; j++) {
                if (i == j) continue;
                endpoint.setDefaultSendLibrary(j + 1, sendLibs[i]);
                endpoint.setDefaultReceiveLibrary(j + 1, receiveLibs[i], 0);
            }
        }
    }
    /**
     * @dev setup UAs, only if the UA has `endpoint` address as the unique parameter
     */

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
    /**
     * @dev verify packets to destination chain's UA address
     * @param _dstEid  destination eid
     * @param _dstAddress  destination address
     */

    function verifyPackets(uint32 _dstEid, bytes32 _dstAddress) public {
        verifyPackets(_dstEid, _dstAddress, 0, address(0x0));
    }
    /**
     * @dev verify packets to destination chain's UA address
     * @param _dstEid  destination eid
     * @param _dstAddress  destination address
     */

    function verifyPackets(uint32 _dstEid, address _dstAddress) public {
        verifyPackets(_dstEid, bytes32(uint256(uint160(_dstAddress))), 0, address(0x0));
    }
    /**
     * @dev dst UA receive/execute packets
     * @dev will NOT work calling this directly with composer IF the composed payload is different from the lzReceive msg payload
     */

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
    // @dev the verifyPackets does not know the composeMsg if it is NOT the same as the original lzReceive payload
    // Can call this directly from your test to lzCompose those types of packets

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

    function validatePacket(bytes calldata _packetBytes) external {}

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
