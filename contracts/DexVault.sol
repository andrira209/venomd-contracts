pragma ton-solidity >= 0.62.0;

pragma AbiHeader time;
pragma AbiHeader expire;
pragma AbiHeader pubkey;

import "@broxus/contracts/contracts/libraries/MsgFlag.sol";

import "tip3/contracts/interfaces/ITokenWallet.sol";
import "tip3/contracts/interfaces/IBurnableTokenWallet.sol";
import "tip3/contracts/interfaces/IAcceptTokensMintCallback.sol";

import "./abstract/DexContractBase.sol";

import "./DexVaultLpTokenPendingV2.sol";
import "./interfaces/IDexVault.sol";
import "./interfaces/IDexBasePool.sol";
import "./interfaces/IDexAccount.sol";
import "./interfaces/IUpgradable.sol";
import "./interfaces/IResetGas.sol";
import "./interfaces/IDexPairOperationCallback.sol";

import "./structures/INextExchangeData.sol";

import "./libraries/DexErrors.sol";
import "./libraries/DexGas.sol";
import "./libraries/DexOperationTypes.sol";
import "./libraries/PairPayload.sol";
import "./libraries/DirectOperationErrors.sol";

contract DexVault is
    DexContractBase,
    IDexVault,
    IResetGas,
    IUpgradable,
    IAcceptTokensMintCallback,
    INextExchangeData
{
    uint32 private static _nonce;

    TvmCell private _lpTokenPendingCode;

    address private _root;
    address private _owner;
    address private _pendingOwner;

    address private _tokenFactory;

    mapping(address => bool) private _lpVaultWallets;

    modifier onlyOwner() {
        require(msg.sender == _owner, DexErrors.NOT_MY_OWNER);
        _;
    }

    modifier onlyLpTokenPending(
        uint32 nonce,
        address pool,
        address[] roots
    ) {
        address expected = address(
            tvm.hash(
                _buildLpTokenPendingInitData(
                    nonce,
                    pool,
                    roots
                )
            )
        );

        require(msg.sender == expected, DexErrors.NOT_LP_PENDING_CONTRACT);
        _;
    }

    constructor(
        address owner_,
        address root_,
        address token_factory_
    ) public {
        tvm.accept();

        _root = root_;
        _owner = owner_;
        _tokenFactory = token_factory_;
    }

    function _dexRoot() override internal view returns(address) {
        return _root;
    }

    function transferOwner(address new_owner) public override onlyOwner {
        tvm.rawReserve(DexGas.VAULT_INITIAL_BALANCE, 2);

        emit RequestedOwnerTransfer(_owner, new_owner);

        _pendingOwner = new_owner;

        _owner.transfer({ value: 0, flag: MsgFlag.ALL_NOT_RESERVED });
    }

    function acceptOwner() public override {
        require(
            msg.sender == _pendingOwner &&
            msg.sender.value != 0,
            DexErrors.NOT_PENDING_OWNER
        );

        tvm.rawReserve(DexGas.VAULT_INITIAL_BALANCE, 2);

        emit OwnerTransferAccepted(_owner, _pendingOwner);

        _owner = _pendingOwner;
        _pendingOwner = address(0);

        _owner.transfer({ value: 0, flag: MsgFlag.ALL_NOT_RESERVED });
    }

    function getOwner() external view responsible returns (address) {
        return {
            value: 0,
            bounce: false,
            flag: MsgFlag.REMAINING_GAS
        } _owner;
    }

    function getPendingOwner() external view responsible returns (address) {
        return {
            value: 0,
            bounce: false,
            flag: MsgFlag.REMAINING_GAS
        } _pendingOwner;
    }

    function getLpTokenPendingCode() external view responsible returns (TvmCell) {
        return {
            value: 0,
            bounce: false,
            flag: MsgFlag.REMAINING_GAS
        } _lpTokenPendingCode;
    }

    function getTokenFactory() external view responsible returns (address) {
        return {
            value: 0,
            bounce: false,
            flag: MsgFlag.REMAINING_GAS
        } _tokenFactory;
    }

    function getRoot() external view responsible returns (address) {
        return {
            value: 0,
            bounce: false,
            flag: MsgFlag.REMAINING_GAS
        } _root;
    }

    function setTokenFactory(address new_token_factory) public override onlyOwner {
        tvm.rawReserve(DexGas.VAULT_INITIAL_BALANCE, 2);

        emit TokenFactoryAddressUpdated(
            _tokenFactory,
            new_token_factory
        );

        _tokenFactory = new_token_factory;

        _owner.transfer({ value: 0, flag: MsgFlag.ALL_NOT_RESERVED });
    }

    function installPlatformOnce(TvmCell code) external onlyOwner {
        require(platform_code.toSlice().empty(), DexErrors.PLATFORM_CODE_NON_EMPTY);

        tvm.rawReserve(DexGas.VAULT_INITIAL_BALANCE, 2);

        platform_code = code;

        _owner.transfer({ value: 0, flag: MsgFlag.ALL_NOT_RESERVED });
    }

    function installOrUpdateLpTokenPendingCode(TvmCell code) public onlyOwner {
        tvm.rawReserve(DexGas.VAULT_INITIAL_BALANCE, 2);

        _lpTokenPendingCode = code;

        _owner.transfer({ value: 0, flag: MsgFlag.ALL_NOT_RESERVED });
    }

    function addLiquidityToken(
        address pair,
        address left_root,
        address right_root,
        address send_gas_to
    ) public override onlyPool([left_root, right_root]) {
        tvm.rawReserve(
            math.max(
                DexGas.VAULT_INITIAL_BALANCE,
                address(this).balance - msg.value
            ),
            2
        );
        new DexVaultLpTokenPendingV2{
            stateInit: _buildLpTokenPendingInitData(
                now,
                pair,
                [left_root, right_root]
            ),
            value: 0,
            flag: MsgFlag.ALL_NOT_RESERVED
        }(
            _tokenFactory,
            msg.value,
            send_gas_to
        );
    }

    function addLiquidityTokenV2(
        address pool,
        address[] roots,
        address send_gas_to
    ) public override onlyPool(roots) {
        tvm.rawReserve(math.max(DexGas.VAULT_INITIAL_BALANCE, address(this).balance - msg.value), 2);
        new DexVaultLpTokenPendingV2{
            stateInit: _buildLpTokenPendingInitData(
                now,
                pool,
                roots
            ),
            value: 0,
            flag: MsgFlag.ALL_NOT_RESERVED
        }(
            _tokenFactory,
            msg.value,
            send_gas_to
        );
    }

    function onLiquidityTokenDeployed(
        uint32 nonce,
        address pool,
        address[] roots,
        address lp_root,
        address send_gas_to
    ) public override onlyLpTokenPending(
        nonce,
        pool,
        roots
    ) {
        tvm.rawReserve(
            math.max(
                DexGas.VAULT_INITIAL_BALANCE,
                address(this).balance - msg.value
            ),
            2
        );

        IDexBasePool(pool)
            .liquidityTokenRootDeployed{ value: 0, flag: MsgFlag.ALL_NOT_RESERVED }
            (lp_root, send_gas_to);
    }

    function onLiquidityTokenNotDeployed(
        uint32 nonce,
        address pool,
        address[] roots,
        address lp_root,
        address send_gas_to
    ) public override onlyLpTokenPending(
        nonce,
        pool,
        roots
    ) {
        tvm.rawReserve(
            math.max(
                DexGas.VAULT_INITIAL_BALANCE,
                address(this).balance - msg.value
            ),
            2
        );

        IDexBasePool(pool)
            .liquidityTokenRootNotDeployed{ value: 0, flag: MsgFlag.ALL_NOT_RESERVED }
            (lp_root, send_gas_to);
    }

    function withdraw(
        uint64 call_id,
        uint128 amount,
        address /* token_root */,
        address vault_wallet,
        address recipient_address,
        uint128 deploy_wallet_grams,
        address account_owner,
        uint32 /* account_version */,
        address send_gas_to
    ) external override onlyAccount(account_owner) {
        tvm.rawReserve(
            math.max(
                DexGas.VAULT_INITIAL_BALANCE,
                address(this).balance - msg.value
            ),
            2
        );

        emit WithdrawTokens(
            vault_wallet,
            amount,
            account_owner,
            recipient_address
        );

        TvmCell empty;

        ITokenWallet(vault_wallet)
            .transfer{
                value: DexGas.TRANSFER_TOKENS_VALUE + deploy_wallet_grams,
                flag: MsgFlag.SENDER_PAYS_FEES
            }(
                amount,
                recipient_address,
                deploy_wallet_grams,
                send_gas_to,
                false,
                empty
            );

        IDexAccount(msg.sender)
            .successCallback{ value: 0, flag: MsgFlag.ALL_NOT_RESERVED }
            (call_id);
    }

    function transfer(
        uint128 amount,
        address /* token_root */,
        address vault_wallet,
        address recipient_address,
        uint128 deploy_wallet_grams,
        bool    notify_receiver,
        TvmCell payload,
        address left_root,
        address right_root,
        uint32  /* pair_version */,
        address send_gas_to
    ) external override onlyPool([left_root, right_root]) {
        tvm.rawReserve(
            math.max(
                DexGas.VAULT_INITIAL_BALANCE,
                address(this).balance - msg.value
            ),
            2
        );

        emit PairTransferTokens(
            vault_wallet,
            amount,
            left_root,
            right_root,
            recipient_address
        );

        ITokenWallet(vault_wallet)
            .transfer{ value: 0, flag: MsgFlag.ALL_NOT_RESERVED }
            (
                amount,
                recipient_address,
                deploy_wallet_grams,
                send_gas_to,
                notify_receiver,
                payload
            );
    }

    function transferV2(
        uint128 _amount,
        address,
        address _vaultWallet,
        address _recipientAddress,
        uint128 _deployWalletGrams,
        bool _notifyReceiver,
        TvmCell _payload,
        address[] _roots,
        uint32,
        address _remainingGasTo
    ) external override onlyPool(_roots) {
        tvm.rawReserve(
            math.max(
                DexGas.VAULT_INITIAL_BALANCE,
                address(this).balance - msg.value
            ),
            2
        );

        emit PairTransferTokensV2(
            _vaultWallet,
            _amount,
            _roots,
            _recipientAddress
        );

        ITokenWallet(_vaultWallet)
            .transfer{ value: 0, flag: MsgFlag.ALL_NOT_RESERVED }
            (
                _amount,
                _recipientAddress,
                _deployWalletGrams,
                _remainingGasTo,
                _notifyReceiver,
                _payload
            );
    }

    function _buildLpTokenPendingInitData(
        uint32 nonce,
        address pool,
        address[] roots
    ) private view returns (TvmCell) {
        return tvm.buildStateInit({
            contr: DexVaultLpTokenPendingV2,
            varInit: {
                _nonce: nonce,
                vault: address(this),
                pool: pool,
                roots: roots
            },
            pubkey: 0,
            code: _lpTokenPendingCode
        });
    }

    function upgrade(TvmCell code) public override onlyOwner {
        require(msg.value > DexGas.UPGRADE_VAULT_MIN_VALUE, DexErrors.VALUE_TOO_LOW);

        tvm.rawReserve(DexGas.VAULT_INITIAL_BALANCE, 2);

        emit VaultCodeUpgraded();

        TvmBuilder builder;
        TvmBuilder owners_data_builder;

        owners_data_builder.store(_owner);
        owners_data_builder.store(_pendingOwner);

        builder.store(_root);
        builder.store(_tokenFactory);

        builder.storeRef(owners_data_builder);

        builder.store(platform_code);
        builder.store(_lpTokenPendingCode);
        builder.store(abi.encode(_lpVaultWallets));

        tvm.setcode(code);
        tvm.setCurrentCode(code);

        onCodeUpgrade(builder.toCell());
    }

    function onCodeUpgrade(TvmCell _data) private {
        tvm.resetStorage();

        TvmSlice slice = _data.toSlice();

        (_root, _tokenFactory) = slice.decode(address, address);

        TvmCell ownersData = slice.loadRef();
        TvmSlice ownersSlice = ownersData.toSlice();
        (_owner, _pendingOwner) = ownersSlice.decode(address, address);

        platform_code = slice.loadRef();
        _lpTokenPendingCode = slice.loadRef();

        if (slice.refs() >= 1) {
            _lpVaultWallets = abi.decode(slice.loadRef(), mapping(address => bool));
        }

        // Refund remaining gas
        _owner.transfer({
            value: 0,
            flag: MsgFlag.ALL_NOT_RESERVED + MsgFlag.IGNORE_ERRORS,
            bounce: false
        });
    }

    function resetGas(address receiver) override external view onlyOwner {
        tvm.rawReserve(DexGas.VAULT_INITIAL_BALANCE, 2);

        receiver.transfer({ value: 0, flag: MsgFlag.ALL_NOT_RESERVED });
    }

    function resetTargetGas(
        address target,
        address receiver
    ) external view onlyOwner {
        tvm.rawReserve(
            math.max(
                DexGas.VAULT_INITIAL_BALANCE,
                address(this).balance - msg.value
            ),
            2
        );

        IResetGas(target)
            .resetGas{ value: 0, flag: MsgFlag.ALL_NOT_RESERVED }
            (receiver);
    }

    function onAcceptTokensMint(
        address tokenRoot,
        uint128 amount,
        address remainingGasTo,
        TvmCell payload
    ) override external {
        tvm.rawReserve(
            math.max(
                DexGas.VAULT_INITIAL_BALANCE,
                address(this).balance - msg.value
            ),
            2
        );

        TvmSlice payloadSlice = payload.toSlice();

        address lpVaultWallet = payloadSlice.decode(address);
        require(msg.sender.value != 0 && msg.sender == lpVaultWallet && _lpVaultWallets[lpVaultWallet], DexErrors.NOT_LP_VAULT_WALLET);

        uint8 op = DexOperationTypes.CROSS_PAIR_EXCHANGE_V2;

        TvmCell exchangeData = payloadSlice.loadRef();

        (uint64 id,
        uint32 currentVersion,
        uint8 currentType,
        address[] roots,
        address senderAddress,
        address recipient,
        uint128 deployWalletGrams,
        NextExchangeData[] nextSteps) = abi.decode(exchangeData, (uint64, uint32, uint8, address[], address, address, uint128, NextExchangeData[]));

        TvmCell successPayload;
        TvmCell cancelPayload;

        bool notifySuccess = payloadSlice.refs() >= 1;
        bool notifyCancel = payloadSlice.refs() >= 2;

        if (notifySuccess) {
            successPayload = payloadSlice.loadRef();
        }
        if (notifyCancel) {
            cancelPayload = payloadSlice.loadRef();
        }

        uint16 errorCode = 0;

        uint256 denominator = 0;
        address prevPool = _expectedPoolAddress(roots);
        uint32 allNestedNodes = uint32(nextSteps.length);
        uint32 allLeaves = 0;
        uint32 maxNestedNodes = 0;
        uint32 maxNestedNodesIdx = 0;
        for (uint32 i = 0; i < nextSteps.length; i++) {
            NextExchangeData nextStep = nextSteps[i];
            if (nextStep.poolRoot.value == 0 || nextStep.poolRoot == prevPool ||
                nextStep.numerator == 0 || nextStep.leaves == 0) {

                errorCode = DirectOperationErrors.INVALID_NEXT_STEPS;
                break;
            }
            if (nextStep.nestedNodes > maxNestedNodes) {
                maxNestedNodes = nextStep.nestedNodes;
                maxNestedNodesIdx = i;
            }
            denominator += nextStep.numerator;
            allNestedNodes += nextStep.nestedNodes;
            allLeaves += nextStep.leaves;
        }

        if (errorCode == 0 && msg.value < DexGas.CROSS_POOL_EXCHANGE_MIN_VALUE * allNestedNodes + 0.1 ton) {
            errorCode = DirectOperationErrors.VALUE_TOO_LOW;
        }

        if (errorCode == 0 && nextSteps.length > 0) {
            uint128 extraValue = msg.value - DexGas.CROSS_POOL_EXCHANGE_MIN_VALUE * allNestedNodes - 0.1 ton;

            for (uint32 i = 0; i < nextSteps.length; i++) {
                NextExchangeData nextStep = nextSteps[i];

                uint128 nextPoolAmount = uint128(math.muldiv(amount, nextStep.numerator, denominator));
                uint128 currentExtraValue = math.muldiv(uint128(nextStep.leaves), extraValue, uint128(allLeaves));

                IDexBasePool(nextStep.poolRoot).crossPoolExchange{
                    value: i == maxNestedNodesIdx ? 0 : (nextStep.nestedNodes + 1) * DexGas.CROSS_POOL_EXCHANGE_MIN_VALUE + currentExtraValue,
                    flag: i == maxNestedNodesIdx ? MsgFlag.ALL_NOT_RESERVED : MsgFlag.SENDER_PAYS_FEES
                }(
                    id,

                    currentVersion,
                    currentType,

                    roots,

                    op,
                    tokenRoot,
                    nextPoolAmount,

                    senderAddress,
                    recipient,

                    remainingGasTo,
                    deployWalletGrams,

                    nextStep.payload,
                    notifySuccess,
                    successPayload,
                    notifyCancel,
                    cancelPayload
                );
            }
        } else {
            bool isLastStep = nextSteps.length == 0;
            if (isLastStep) {
                emit PairTransferTokensV2(
                    lpVaultWallet,
                    amount,
                    roots,
                    recipient
                );
            } else {
                IDexPairOperationCallback(senderAddress).dexPairOperationCancelled{
                    value: DexGas.OPERATION_CALLBACK_BASE + 44,
                    flag: MsgFlag.SENDER_PAYS_FEES + MsgFlag.IGNORE_ERRORS,
                    bounce: false
                }(id);

                if (recipient != senderAddress) {
                    IDexPairOperationCallback(recipient).dexPairOperationCancelled{
                        value: DexGas.OPERATION_CALLBACK_BASE,
                        flag: MsgFlag.SENDER_PAYS_FEES + MsgFlag.IGNORE_ERRORS,
                        bounce: false
                    }(id);
                }
            }

            ITokenWallet(lpVaultWallet)
                .transfer{ value: 0, flag: MsgFlag.ALL_NOT_RESERVED }
                (
                    amount,
                    isLastStep ? recipient : senderAddress,
                    deployWalletGrams,
                    remainingGasTo,
                    isLastStep ? notifySuccess : notifyCancel,
                    isLastStep
                        ? PairPayload.buildSuccessPayload(op, successPayload, senderAddress)
                        : PairPayload.buildCancelPayload(op, errorCode, cancelPayload, nextSteps)
                );
        }
    }

    function burn(
        address[] _roots,
        address _lpVaultWallet,
        uint128 _amount,
        address _remainingGasTo,
        address _callbackTo,
        TvmCell _payload
    ) external override onlyPool(_roots) {
        tvm.rawReserve(
            math.max(
                DexGas.VAULT_INITIAL_BALANCE,
                address(this).balance - msg.value
            ),
            2
        );

        IBurnableTokenWallet(_lpVaultWallet).burn{ value: 0, flag: MsgFlag.ALL_NOT_RESERVED }(
            _amount,
            _remainingGasTo,
            _callbackTo,
            _payload
        );
    }

    function addLpWallet(
        address[] _roots,
        address _lpVaultWallet
    ) external override onlyPool(_roots) {
        tvm.rawReserve(DexGas.VAULT_INITIAL_BALANCE, 0);

        _lpVaultWallets[_lpVaultWallet] = true;
    }

    function addLpWalletByOwner(
        address _lpVaultWallet
    ) external override onlyOwner {
        tvm.rawReserve(
            math.max(
                DexGas.VAULT_INITIAL_BALANCE,
                address(this).balance - msg.value
            ),
            2
        );

        _lpVaultWallets[_lpVaultWallet] = true;

        _owner.transfer({ value: 0, flag: MsgFlag.ALL_NOT_RESERVED });
    }
}
