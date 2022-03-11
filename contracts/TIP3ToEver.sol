pragma ton-solidity >= 0.57.0;

pragma AbiHeader time;
pragma AbiHeader expire;
pragma AbiHeader pubkey;

import "./libraries/EverToTip3Gas.sol";
import "./libraries/SwapEverErrors.sol";
import "./libraries/DexOperationTypes.sol";
import "./libraries/EverToTip3OperationStatus.sol";

import "./interfaces/IEverTIP3SwapEvents.sol";
import "./interfaces/IEverTIP3SwapCallbacks.sol";

import "@broxus/contracts/contracts/libraries/MsgFlag.sol";
import "ton-eth-bridge-token-contracts/contracts/interfaces/ITokenRoot.sol";
import "ton-eth-bridge-token-contracts/contracts/interfaces/ITokenWallet.sol";
import "ton-eth-bridge-token-contracts/contracts/interfaces/IAcceptTokensTransferCallback.sol";
import "ton-eth-bridge-token-contracts/contracts/interfaces/IAcceptTokensBurnCallback.sol";

contract TIP3ToEver is IAcceptTokensTransferCallback, IAcceptTokensBurnCallback, IEverTIP3SwapEvents {
   
    uint32 static randomNonce_;
    
    address wEverRoot_;
    address wEverWallet_;
    address wEverVault_;

    constructor(address _wEverRoot, address _wEverVault) public {
        tvm.accept();
        wEverRoot_ = _wEverRoot;
        wEverVault_ = _wEverVault;

        tvm.rawReserve(EverToTip3Gas.DEPLOY_EMPTY_WALLET_VALUE, 0);
        ITokenRoot(wEverRoot_).deployWallet{
            value: EverToTip3Gas.DEPLOY_EMPTY_WALLET_VALUE,
            flag: MsgFlag.SENDER_PAYS_FEES,
            callback: TIP3ToEver.onWEverWallet    
        }(
            address(this), 
            EverToTip3Gas.DEPLOY_EMPTY_WALLET_GRAMS
        );
    }

    // Сallback deploy WEVER wallet for contract
    function onWEverWallet(address _wEverWallet) external {
        require(msg.sender.value != 0 && msg.sender == wEverRoot_, SwapEverErrors.NOT_ROOT_WEVER);
        wEverWallet_ = _wEverWallet;
    }

    // Payload constructor swap TIP-3 -> Ever
    function buildSwapEversPayload(
        uint64 id, 
        address pair,
        uint128 expectedAmount,
        uint64 user
    ) external pure returns (TvmCell) {
        TvmBuilder builderPayload;
        builderPayload.store(EverToTip3OperationStatus.SWAP);
        builderPayload.store(id);
        builderPayload.store(pair);
        builderPayload.store(expectedAmount);
        builderPayload.store(user);
        return builderPayload.toCell();
    }

    // Callback result swap
    function onAcceptTokensTransfer(
        address /*tokenRoot*/,
        uint128 amount,
        address sender,
        address /*senderWallet*/,
        address user,
        TvmCell payload
    ) override external {
        TvmSlice payloadSlice = payload.toSlice();
        bool needCancel;
        tvm.rawReserve(EverToTip3Gas.ACCOUNT_INITIAL_BALANCE, 0);

        if (payloadSlice.bits() >= 8) {
            (uint8 operationStatus) = payloadSlice.decode(uint8);
            if (payloadSlice.bits() == 726 && operationStatus == EverToTip3OperationStatus.SWAP) {
                (uint64 id, address pair, uint128 expectedAmount, address user_) = 
                payloadSlice.decode(uint64, address, uint128, address);    
                
                TvmBuilder successPayload;
                successPayload.store(EverToTip3OperationStatus.SUCCESS);
                successPayload.store(id);
                successPayload.store(user_);
                
                TvmBuilder cancelPayload;
                cancelPayload.store(EverToTip3OperationStatus.CANCEL);
                cancelPayload.store(id);
                cancelPayload.store(user_);

                TvmBuilder resultPayload;
                resultPayload.store(DexOperationTypes.EXCHANGE);
                resultPayload.store(id);
                resultPayload.store(uint128(0));
                resultPayload.store(uint128(0));
                resultPayload.store(expectedAmount);
                
                resultPayload.storeRef(successPayload);
                resultPayload.storeRef(cancelPayload);

                ITokenWallet(msg.sender).transfer{value: 0, flag: MsgFlag.ALL_NOT_RESERVED, bounce: false}(
                    amount,
                    pair,
                    uint128(0),
                    user,
                    true,
                    resultPayload.toCell()
                );
            } else if (payloadSlice.bits() == 331) {
                if (operationStatus == EverToTip3OperationStatus.CANCEL) {
                    (uint64 id_) = payloadSlice.decode(uint64);
            
                    emit SwapTIP3EverCancelTransfer(user, id_);    
                    IEverTIP3SwapCallbacks(user).onSwapTIP3ToEverCancel{value: 0, flag: MsgFlag.SENDER_PAYS_FEES, bounce: false}(id_);

                    TvmBuilder payloadID;
                    payloadID.store(id_);
                    TvmCell payloadID_ = payloadID.toCell();              

                    ITokenWallet(msg.sender).transfer{value: 0, flag: MsgFlag.ALL_NOT_RESERVED, bounce: false}(
                        amount,
                        user,
                        uint128(0),
                        user,
                        true,
                        payloadID_
                    );
                } else if (operationStatus == EverToTip3OperationStatus.SUCCESS && 
                          (msg.sender.value != 0 && msg.sender == wEverWallet_)) {
                    (uint64 id) = payloadSlice.decode(uint64);

                    TvmBuilder payloadID;
                    payloadID.store(id);
                    payloadID.store(amount);
                    TvmCell payloadID_ = payloadID.toCell();

                    ITokenWallet(wEverWallet_).transfer{ value: 0, flag: MsgFlag.ALL_NOT_RESERVED, bounce: false }(
                        amount,
                        wEverVault_,
                        uint128(0),
                        user,
                        true,
                        payloadID_
                    );
                } else {
                    needCancel = true;    
                }
            } else {
                needCancel = true;    
            }
        } else {
            needCancel = true;
        }            

        if (needCancel) {
            TvmCell emptyPayload;
            ITokenWallet(msg.sender).transfer{ value: 0, flag: MsgFlag.ALL_NOT_RESERVED, bounce: false }(
                amount,
                sender,
                uint128(0),
                user,
                true,
                emptyPayload                        
            );
        }
    }

    // Callback Burn token if result swap success
    function onAcceptTokensBurn(
        uint128 /*amount*/,
        address /*walletOwner*/,
        address /*wallet*/,
        address user,
        TvmCell payload
    ) override external {
        require(msg.sender.value != 0 && msg.sender == wEverRoot_, SwapEverErrors.NOT_ROOT_WEVER); 
        tvm.rawReserve(EverToTip3Gas.ACCOUNT_INITIAL_BALANCE, 0);
       
        TvmSlice payloadSlice =  payload.toSlice();
        (uint64 id, uint128 amount) = payloadSlice.decode(uint64, uint128);

        emit SwapTIP3EverSuccessTransfer(user, id);
        IEverTIP3SwapCallbacks(user).onSwapTIP3ToEverSuccess{ value: 0, flag: MsgFlag.SENDER_PAYS_FEES, bounce: false }(id);
    }

}