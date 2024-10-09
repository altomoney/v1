pragma solidity ^0.8.22;

import "tap-utils/interfaces/oft/ITOFT.sol";
import "tapiocaz/tOFT/mTOFT.sol";
import "tapiocaz/tOFT/TOFTVault.sol";
import {mTOFTReceiver} from "tapiocaz/tOFT/modules/mTOFTReceiver.sol";
import {ERC20Mock} from "yieldbox/mocks/ERC20Mock.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MTOFTFactory
 * @dev Factory for mTOFT wrapper. Re-deploy if any of the immutable contracts are updated.
 */
contract MTOFTFactory is Ownable {
    address immutable CLUSTER;
    address immutable ENDPOINT;
    address immutable EXT_EXEC;
    address immutable PEARLMIT;
    address immutable YIELD_BOX;
    address immutable DELEGATE;
    uint256 immutable HOST_EID;

    address immutable TOFT_SENDER_MODULE;
    address immutable MTOFT_RECEIVER_MODULE;
    address immutable MARKET_RECEIVER_MODULE;
    address immutable OPTIONS_RECEIVER_MODULE;
    address immutable GENERIC_RECEIVER_MODULE;

    error InvalidStargateRouter();

    struct TOFTConstructorParams {
        address cluster;
        address endpoint;
        uint256 hostEid;
        address extExec;
        address pearlmit;
        address yieldbox;
        address tOFTSenderModule;
        address MTOFTReceiverModule;
        address marketReceiverModule;
        address optionsReceiverModule;
        address genericReceiverModule;
        address delegate;
        address owner;
    }

    constructor(TOFTConstructorParams memory params) {
        CLUSTER = params.cluster;
        ENDPOINT = params.endpoint;
        EXT_EXEC = params.extExec;
        PEARLMIT = params.pearlmit;
        YIELD_BOX = params.yieldbox;
        DELEGATE = params.delegate;
        HOST_EID = params.hostEid;
        TOFT_SENDER_MODULE = params.tOFTSenderModule;
        MTOFT_RECEIVER_MODULE = params.MTOFTReceiverModule;
        MARKET_RECEIVER_MODULE = params.marketReceiverModule;
        OPTIONS_RECEIVER_MODULE = params.optionsReceiverModule;
        GENERIC_RECEIVER_MODULE = params.genericReceiverModule;

        transferOwnership(params.owner);
    }

    function deployMTOFT(address erc20Token, string calldata name, string calldata symbol, address stargateRouter)
        public
        onlyOwner
        returns (TOFTVault vault, mTOFT mtoft)
    {
        if (stargateRouter == address(0)) revert InvalidStargateRouter();
        vault = new TOFTVault(erc20Token);

        TOFTInitStruct memory toftInitStruct = TOFTInitStruct({
            name: name,
            symbol: symbol,
            endpoint: ENDPOINT,
            delegate: DELEGATE,
            yieldBox: YIELD_BOX,
            cluster: CLUSTER,
            erc20: erc20Token,
            vault: address(vault),
            hostEid: HOST_EID,
            extExec: EXT_EXEC,
            pearlmit: IPearlmit(PEARLMIT)
        });
        TOFTModulesInitStruct memory toftModulesInitStruct = TOFTModulesInitStruct({
            tOFTSenderModule: TOFT_SENDER_MODULE,
            tOFTReceiverModule: MTOFT_RECEIVER_MODULE,
            marketReceiverModule: MARKET_RECEIVER_MODULE,
            optionsReceiverModule: OPTIONS_RECEIVER_MODULE,
            genericReceiverModule: GENERIC_RECEIVER_MODULE
        });

        mtoft = new mTOFT(toftInitStruct, toftModulesInitStruct, stargateRouter);
    }
}
