pragma solidity ^0.8.22;

import "tap-utils/interfaces/oft/ITOFT.sol";
import "tapiocaz/tOFT/TOFT.sol";
import "tapiocaz/tOFT/mTOFT.sol";
import "tapiocaz/tOFT/TOFTVault.sol";
import {mTOFTReceiver} from "tapiocaz/tOFT/modules/mTOFTReceiver.sol";
import {ERC20Mock} from "tap-token/mocks/ERC20Mock.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title TOFTFactory
 * @dev Factory for TOFT wrapper. Re-deploy if any of the immutable contracts are updated.
 */
contract TOFTFactory is Ownable {
    address immutable CLUSTER;
    address immutable ENDPOINT;
    address immutable EXT_EXEC;
    address immutable DELEGATE;
    uint256 immutable HOST_EID;

    address immutable TOFT_SENDER_MODULE;
    address immutable TOFT_RECEIVER_MODULE;
    address immutable MARKET_RECEIVER_MODULE;
    address immutable OPTIONS_RECEIVER_MODULE;
    address immutable GENERIC_RECEIVER_MODULE;

    struct TOFTConstructorParams {
        address cluster;
        address endpoint;
        uint256 hostEid;
        address extExec;
        address tOFTSenderModule;
        address tOFTReceiverModule;
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
        DELEGATE = params.delegate;
        HOST_EID = params.hostEid;
        TOFT_SENDER_MODULE = params.tOFTSenderModule;
        TOFT_RECEIVER_MODULE = params.tOFTReceiverModule;
        MARKET_RECEIVER_MODULE = params.marketReceiverModule;
        OPTIONS_RECEIVER_MODULE = params.optionsReceiverModule;
        GENERIC_RECEIVER_MODULE = params.genericReceiverModule;

        transferOwnership(params.owner);
    }

    function deployTOFT(address erc20Token, string calldata name, string calldata symbol)
        public
        onlyOwner
        returns (TOFTVault vault, TOFT toft)
    {
        vault = new TOFTVault(erc20Token);

        TOFTInitStruct memory toftInitStruct = TOFTInitStruct({
            name: name,
            symbol: symbol,
            endpoint: ENDPOINT,
            delegate: DELEGATE,
            
            cluster: CLUSTER,
            erc20: erc20Token,
            vault: address(vault),
            hostEid: HOST_EID,
            extExec: EXT_EXEC
            
        });
        TOFTModulesInitStruct memory toftModulesInitStruct = TOFTModulesInitStruct({
            tOFTSenderModule: TOFT_SENDER_MODULE,
            tOFTReceiverModule: TOFT_RECEIVER_MODULE,
            marketReceiverModule: MARKET_RECEIVER_MODULE,
            optionsReceiverModule: OPTIONS_RECEIVER_MODULE,
            genericReceiverModule: GENERIC_RECEIVER_MODULE
        });

        toft = new TOFT(toftInitStruct, toftModulesInitStruct);
    }
}
