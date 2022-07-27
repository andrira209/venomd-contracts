pragma ton-solidity >= 0.57.0;

pragma AbiHeader time;
pragma AbiHeader expire;
pragma AbiHeader pubkey;

import "@broxus/contracts/contracts/libraries/MsgFlag.sol";
import "ton-eth-bridge-token-contracts/contracts/interfaces/ITokenWallet.sol";
import "ton-eth-bridge-token-contracts/contracts/interfaces/IBurnableByRootTokenRoot.sol";
import "ton-eth-bridge-token-contracts/contracts/interfaces/IBurnableTokenWallet.sol";
import "ton-eth-bridge-token-contracts/contracts/interfaces/IAcceptTokensTransferCallback.sol";

import "./abstract/DexPairBase.sol";

import "./interfaces/IUpgradableByRequest.sol";
import "./interfaces/IDexPair.sol";
import "./interfaces/ISuccessCallback.sol";
import "./interfaces/IDexPairOperationCallback.sol";

import "./libraries/DexPlatformTypes.sol";
import "./libraries/DexErrors.sol";
import "./libraries/Math.sol";
import "./libraries/PairPayload.sol";

import "./structures/IExchangeResult.sol";
import "./structures/IWithdrawResult.sol";

import "./DexPlatform.sol";

/// @title DEX Pair
/// @notice Constant product formulae DEX pair
contract DexPair is DexPairBase {
    // Cant be deployed directly
    constructor() public {
        revert();
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////////////
    // Build payloads

    function buildExchangePayload(
        uint64 id,
        uint128 deploy_wallet_grams,
        uint128 expected_amount
    ) external pure returns (TvmCell) {
        return PairPayload.buildExchangePayload(
            id,
            deploy_wallet_grams,
            expected_amount
        );
    }

    function buildDepositLiquidityPayload(
        uint64 id,
        uint128 deploy_wallet_grams
    ) external pure returns (TvmCell) {
        return PairPayload.buildDepositLiquidityPayload(
            id,
            deploy_wallet_grams
        );
    }

    function buildWithdrawLiquidityPayload(
        uint64 id,
        uint128 deploy_wallet_grams
    ) external pure returns (TvmCell) {
        return PairPayload.buildWithdrawLiquidityPayload(
            id,
            deploy_wallet_grams
        );
    }

    function buildCrossPairExchangePayload(
        uint64 id,
        uint128 deploy_wallet_grams,
        uint128 expected_amount,
        TokenOperation[] steps
    ) external returns (TvmCell) {
        return PairPayload.buildCrossPairExchangePayload(
            id,
            deploy_wallet_grams,
            expected_amount,
            steps
        );
    }

    function buildCrossPairExchangePayloadV2(
        uint64 _id,
        uint128 _deployWalletGrams,
        uint128 _expectedAmount,
        address _outcoming,
        ExchangeStep[] _steps
    ) external returns (TvmCell) {
        address[] pairs;

        // Calculate pairs' addresses by token roots
        for (uint i = 0; i < _steps.length; i++) {
            pairs.push(_expectedPairAddress(_steps[i].roots));
        }

        return PairPayload.buildCrossPairExchangePayloadV2(
            _id,
            _deployWalletGrams,
            _expectedAmount,
            _outcoming,
            _steps,
            pairs
        );
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////////////
    // Deposit liquidity

    function expectedDepositLiquidity(
        uint128 left_amount,
        uint128 right_amount,
        bool auto_change
    ) override external view responsible returns (DepositLiquidityResult) {
        uint128 lpReserve = _typeToReserves[DexReserveType.LP][0];

        (DepositLiquidityResult result,,) = Math.calculateExpectedDepositLiquidity(
            left_amount,
            right_amount,
            auto_change,
            _typeToReserves[DexReserveType.POOL][0],
            _typeToReserves[DexReserveType.POOL][1],
            lpReserve,
            _fee
        );

        return {
            value: 0,
            bounce: false,
            flag: MsgFlag.REMAINING_GAS
        } result;
    }

    function depositLiquidity(
        uint64 _callId,
        TokenOperation[] _operations,
        address _expectedLpRoot,
        uint128 _minimumLpAmount,
        bool _autoChange,
        address _accountOwner,
        uint32,
        address _remainingGasTo
    ) override external onlyActive onlyAccount(_accountOwner) {
        address lp = _typeToRootAddresses[DexAddressType.LP][0];
        address leftTokenRoot = _typeToRootAddresses[DexAddressType.RESERVE][0];
        address rightTokenRoot = _typeToRootAddresses[DexAddressType.RESERVE][1];
        uint128 lpReserve = _typeToReserves[DexReserveType.LP][0];
        uint128 leftReserve = _typeToReserves[DexReserveType.POOL][0];
        uint128 rightReserve = _typeToReserves[DexReserveType.POOL][1];

        require(_expectedLpRoot == lp, DexErrors.NOT_LP_TOKEN_ROOT);
        require(lpReserve != 0 || (_operations[0].amount > 0 && _operations[1].amount > 0), DexErrors.WRONG_LIQUIDITY);
        require(
            (_operations[0].amount > 0 && _operations[1].amount > 0) ||
            (_autoChange && (_operations[0].amount + _operations[1].amount > 0)),
            DexErrors.AMOUNT_TOO_LOW
        );

        tvm.rawReserve(DexGas.PAIR_INITIAL_BALANCE, 0);

        (
            DepositLiquidityResult result,
            uint128 step2PoolFee,
            uint128 step2BeneficiaryFee
        ) = Math.calculateExpectedDepositLiquidity(
            _operations[0].amount,
            _operations[1].amount,
            _autoChange,
            leftReserve,
            rightReserve,
            lpReserve,
            _fee
        );

        require(result.step_1_lp_reward + result.step_3_lp_reward >= _minimumLpAmount, DexErrors.WRONG_LIQUIDITY);

        if (lpReserve == 0) {
            _typeToReserves[DexReserveType.POOL][0] = _operations[0].amount;
            _typeToReserves[DexReserveType.POOL][1] = _operations[1].amount;
        } else {
            if (_autoChange) {
                _typeToReserves[DexReserveType.POOL][0] += _operations[0].amount;
                _typeToReserves[DexReserveType.POOL][1] += _operations[1].amount;

                if (result.step_2_right_to_left) {
                    require(result.step_2_received <= _typeToReserves[DexReserveType.POOL][0] + result.step_1_left_deposit, DexErrors.NOT_ENOUGH_FUNDS);

                    _typeToReserves[DexReserveType.POOL][1] -= step2BeneficiaryFee;
                    _typeToReserves[DexReserveType.FEE][1] += step2BeneficiaryFee;
                } else if (result.step_2_left_to_right) {
                    require(result.step_2_received <= _typeToReserves[DexReserveType.POOL][1] + result.step_1_right_deposit, DexErrors.NOT_ENOUGH_FUNDS);

                    _typeToReserves[DexReserveType.POOL][0] -= step2BeneficiaryFee;
                    _typeToReserves[DexReserveType.FEE][0] += step2BeneficiaryFee;
                }

                _exchangeBase(
                    _callId,
                    true,
                    result.step_2_left_to_right ? 0 : 1,
                    result.step_2_left_to_right ? 1 : 0,
                    0,
                    0,
                    0,
                    0,
                    _accountOwner,
                    _remainingGasTo
                );
            } else {
                _typeToReserves[DexReserveType.POOL][0] += result.step_1_left_deposit;
                _typeToReserves[DexReserveType.POOL][1] += result.step_1_right_deposit;

                if (result.step_1_left_deposit < _operations[0].amount) {
                    IDexAccount(msg.sender)
                        .internalPairTransfer{ value: DexGas.INTERNAL_PAIR_TRANSFER_VALUE, flag: MsgFlag.SENDER_PAYS_FEES }
                        (
                            _operations[0].amount - result.step_1_left_deposit,
                            leftTokenRoot,
                            leftTokenRoot,
                            rightTokenRoot,
                            _remainingGasTo
                        );
                }

                if (result.step_1_right_deposit < _operations[1].amount) {
                    IDexAccount(msg.sender)
                        .internalPairTransfer{ value: DexGas.INTERNAL_PAIR_TRANSFER_VALUE, flag: MsgFlag.SENDER_PAYS_FEES }
                        (
                            _operations[1].amount - result.step_1_right_deposit,
                            rightTokenRoot,
                            leftTokenRoot,
                            rightTokenRoot,
                            _remainingGasTo
                        );
                }
            }
        }

        _depositLiquidityBase(
            _callId,
            true,
            result,
            _accountOwner
        );

        TvmCell empty;

        ITokenRoot(lp)
            .mint{
                value: DexGas.DEPLOY_MINT_VALUE_BASE + DexGas.DEPLOY_EMPTY_WALLET_GRAMS,
                flag: MsgFlag.SENDER_PAYS_FEES
            }(
                result.step_1_lp_reward + result.step_3_lp_reward,
                _accountOwner,
                DexGas.DEPLOY_EMPTY_WALLET_GRAMS,
                _remainingGasTo,
                _remainingGasTo == _accountOwner,
                empty
            );

        ISuccessCallback(msg.sender)
            .successCallback{ value: 0, flag: MsgFlag.ALL_NOT_RESERVED }
            (_callId);
    }

    /// @dev Internal deposit liquidity common part
    /// @param _callId ID of the call
    /// @param _isViaAccount Whether or not call was made from DEX account
    /// @param _result Calculated liquidity deposit steps
    /// @param _senderAddress Address of the sender
    function _depositLiquidityBase(
        uint64 _callId,
        bool _isViaAccount,
        DepositLiquidityResult _result,
        address _senderAddress
    ) private {
        address leftTokenRoot = _typeToRootAddresses[DexAddressType.RESERVE][0];
        address rightTokenRoot = _typeToRootAddresses[DexAddressType.RESERVE][1];
        _typeToReserves[DexReserveType.LP][0] += _result.step_1_lp_reward + _result.step_3_lp_reward;

        _sync();

        if (_result.step_1_lp_reward > 0) {
            TokenOperation[] step1Operations;

            step1Operations.push(
                TokenOperation(
                    _result.step_1_left_deposit,
                    leftTokenRoot
                )
            );

            step1Operations.push(
                TokenOperation(
                    _result.step_1_right_deposit,
                    rightTokenRoot
                )
            );

            emit DepositLiquidity(
                _senderAddress,
                _senderAddress,
                step1Operations,
                _result.step_1_lp_reward
            );
        }

        if (_result.step_3_lp_reward > 0) {
            TokenOperation[] step3Operations;

            step3Operations.push(
                TokenOperation(
                    _result.step_3_left_deposit,
                    leftTokenRoot
                )
            );

            step3Operations.push(
                TokenOperation(
                    _result.step_3_right_deposit,
                    rightTokenRoot
                )
            );

            emit DepositLiquidity(
                _senderAddress,
                _senderAddress,
                step3Operations,
                _result.step_3_lp_reward
            );
        }

        IDexPairOperationCallback(_senderAddress)
            .dexPairDepositLiquiditySuccess{
                value: DexGas.OPERATION_CALLBACK_BASE + 2,
                flag: MsgFlag.SENDER_PAYS_FEES + MsgFlag.IGNORE_ERRORS,
                bounce: false
            }(
                _callId,
                _isViaAccount,
                _result
            );
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////////////
    // Withdraw liquidity

    function _withdrawLiquidityBase(
        uint128 _lpAmount,
        address _sender
    ) private returns (TokenOperation[]) {
        uint128 lpReserve = _typeToReserves[DexReserveType.LP][0];

        uint128 leftBackAmount =  math.muldiv(
            _typeToReserves[DexReserveType.POOL][0],
            _lpAmount,
            lpReserve
        );

        uint128 rightBackAmount = math.muldiv(
            _typeToReserves[DexReserveType.POOL][1],
            _lpAmount,
            lpReserve
        );

        // Update reserves
        _typeToReserves[DexReserveType.POOL][0] -= leftBackAmount;
        _typeToReserves[DexReserveType.POOL][1] -= rightBackAmount;
        _typeToReserves[DexReserveType.LP][0] -= _lpAmount;

        // Save operations
        TokenOperation[] operations = new TokenOperation[](0);

        operations.push(
            TokenOperation(
                leftBackAmount,
                _typeToRootAddresses[DexAddressType.RESERVE][0]
            )
        );

        operations.push(
            TokenOperation(
                rightBackAmount,
                _typeToRootAddresses[DexAddressType.RESERVE][1]
            )
        );

        // Emit event
        emit WithdrawLiquidity(
            _sender,
            _sender,
            _lpAmount,
            operations
        );

        return operations;
    }

    function expectedWithdrawLiquidity(
        uint128 lp_amount
    ) override external view responsible returns (
        uint128 expected_left_amount,
        uint128 expected_right_amount
    ) {
        uint128 lpReserve = _typeToReserves[DexReserveType.LP][0];

        uint128 leftBackAmount = math.muldiv(
            _typeToReserves[DexReserveType.POOL][0],
            lp_amount,
            lpReserve
        );

        uint128 rightBackAmount = math.muldiv(
            _typeToReserves[DexReserveType.POOL][1],
            lp_amount,
            lpReserve
        );

        return {
            value: 0,
            bounce: false,
            flag: MsgFlag.REMAINING_GAS
        } (
            leftBackAmount,
            rightBackAmount
        );
    }

    function withdrawLiquidity(
        uint64 _callId,
        uint128 _lpAmount,
        address _expectedLpRoot,
        TokenOperation[] _expected,
        address _accountOwner,
        uint32,
        address _remainingGasTo
    ) override external onlyActive onlyAccount(_accountOwner) {
        address lp = _typeToRootAddresses[DexAddressType.LP][0];
        address vault = _typeToRootAddresses[DexAddressType.VAULT][0];

        require(_expectedLpRoot == lp, DexErrors.NOT_LP_TOKEN_ROOT);
        tvm.rawReserve(DexGas.PAIR_INITIAL_BALANCE, 0);

        TvmCell empty;

        _withdrawBase(
            _callId,
            true,
            _lpAmount,
            _accountOwner,
            _remainingGasTo,
            0,
            false,
            empty
        );

        IBurnableByRootTokenRoot(lp)
            .burnTokens{ value: DexGas.BURN_VALUE, flag: MsgFlag.SENDER_PAYS_FEES }
            (
                _lpAmount,
                vault,
                _remainingGasTo,
                address.makeAddrStd(0, 0),
                empty
            );

        ISuccessCallback(msg.sender)
            .successCallback{ value: 0, flag: MsgFlag.ALL_NOT_RESERVED }
            (_callId);
    }

    /// @dev Internal withdraw liquidity common part
    /// @param _callId ID of the call
    /// @param _isViaAccount Whether or not call was made from DEX account
    /// @param _lpAmount Amount of LP tokens to withdraw
    /// @param _senderAddress Address of the sender
    /// @param _remainingGasTo Receiver of the remaining gas
    /// @param _deployWalletGrams Amount for a new wallet deploy
    /// @param _notifySuccess Whether or not notify sender about success withdrawal
    /// @param _successPayload Payload for success callback
    function _withdrawBase(
        uint64 _callId,
        bool _isViaAccount,
        uint128 _lpAmount,
        address _senderAddress,
        address _remainingGasTo,
        uint128 _deployWalletGrams,
        bool _notifySuccess,
        TvmCell _successPayload
    ) private {
        TokenOperation[] operations = _withdrawLiquidityBase(_lpAmount, _senderAddress);

        _sync();

        IDexPairOperationCallback(_senderAddress)
            .dexPairWithdrawSuccess{
                value: DexGas.OPERATION_CALLBACK_BASE + 3,
                flag: MsgFlag.SENDER_PAYS_FEES + MsgFlag.IGNORE_ERRORS,
                bounce: false
            }(
                _callId,
                _isViaAccount,
                IWithdrawResult.WithdrawResult(
                    _lpAmount,
                    operations[0].amount,
                    operations[1].amount
                )
            );

        for (TokenOperation op : operations) {
            if (op.amount >= 0) {
                if (_isViaAccount) {
                    IDexAccount(msg.sender)
                        .internalPairTransfer{ value: DexGas.INTERNAL_PAIR_TRANSFER_VALUE, flag: MsgFlag.SENDER_PAYS_FEES }
                        (
                            op.amount,
                            op.root,
                            _typeToRootAddresses[DexAddressType.RESERVE][0],
                            _typeToRootAddresses[DexAddressType.RESERVE][1],
                            _remainingGasTo
                        );
                } else {
                    address vault = _typeToRootAddresses[DexAddressType.VAULT][0];

                    IDexVault(vault)
                        .transfer{
                            value: DexGas.VAULT_TRANSFER_BASE_VALUE_V2 + _deployWalletGrams,
                            flag: MsgFlag.SENDER_PAYS_FEES
                        }(
                            op.amount,
                            op.root,
                            _typeToWalletAddresses[DexAddressType.VAULT][op.root == _typeToRootAddresses[DexAddressType.RESERVE][0] ? 0 : 1],
                            _senderAddress,
                            _deployWalletGrams,
                            _notifySuccess,
                            _successPayload,
                            op.root,
                            _typeToRootAddresses[DexAddressType.RESERVE][op.root == _typeToRootAddresses[DexAddressType.RESERVE][0] ? 1 : 0],
                            _currentVersion,
                            _remainingGasTo
                        );
                }
            }
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////////////
    // Exchange

    function expectedExchange(
        uint128 amount,
        address spent_token_root
    ) override external view responsible returns (
        uint128 expected_amount,
        uint128 expected_fee
    ) {
        uint8 spentTokenIndex = spent_token_root == _typeToRootAddresses[DexAddressType.RESERVE][0] ? 0 : 1;
        uint8 receiveTokenIndex = spent_token_root == _typeToRootAddresses[DexAddressType.RESERVE][0] ? 1 : 0;

        if (
            spent_token_root == _typeToRootAddresses[DexAddressType.RESERVE][0] ||
            spent_token_root == _typeToRootAddresses[DexAddressType.RESERVE][1]
        ) {
            (
                uint128 amount,
                uint128 poolFee,
                uint128 beneficiaryFee
            ) = Math.calculateExpectedExchange(
                amount,
                _typeToReserves[DexReserveType.POOL][spentTokenIndex],
                _typeToReserves[DexReserveType.POOL][receiveTokenIndex],
                _fee
            );

            return {
                value: 0,
                bounce: false,
                flag: MsgFlag.REMAINING_GAS
            } (
                amount,
                poolFee + beneficiaryFee
            );
        } else {
            revert(DexErrors.NOT_TOKEN_ROOT);
        }
    }

    function expectedSpendAmount(
        uint128 receive_amount,
        address receive_token_root
    ) override external view responsible returns (
        uint128 expected_amount,
        uint128 expected_fee
    ) {
        uint8 spentTokenIndex = receive_token_root == _typeToRootAddresses[DexAddressType.RESERVE][1] ? 0 : 1;
        uint8 receiveTokenIndex = receive_token_root == _typeToRootAddresses[DexAddressType.RESERVE][1] ? 1 : 0;

        if (
            receive_token_root == _typeToRootAddresses[DexAddressType.RESERVE][0] ||
            receive_token_root == _typeToRootAddresses[DexAddressType.RESERVE][1]
        ) {
            return {
                value: 0,
                bounce: false,
                flag: MsgFlag.REMAINING_GAS
            } Math.calculateExpectedSpendAmount(
                receive_amount,
                _typeToReserves[DexReserveType.POOL][spentTokenIndex],
                _typeToReserves[DexReserveType.POOL][receiveTokenIndex],
                _fee
            );
        } else {
            revert(DexErrors.NOT_TOKEN_ROOT);
        }
    }

    function exchange(
        uint64 _callId,
        uint128 _spentAmount,
        address _spentTokenRoot,
        address _receiveTokenRoot,
        uint128 _expectedAmount,
        address _accountOwner,
        uint32,
        address _remainingGasTo
    ) override external onlyActive onlyAccount(_accountOwner) {
        if (
            (_spentTokenRoot == _typeToRootAddresses[DexAddressType.RESERVE][0] && _receiveTokenRoot == _typeToRootAddresses[DexAddressType.RESERVE][1]) ||
            (_spentTokenRoot == _typeToRootAddresses[DexAddressType.RESERVE][1] && _receiveTokenRoot == _typeToRootAddresses[DexAddressType.RESERVE][0])
        ) {
            uint8 spentTokenIndex = _spentTokenRoot == _typeToRootAddresses[DexAddressType.RESERVE][0] ? 0 : 1;
            uint8 receiveTokenIndex = _spentTokenRoot == _typeToRootAddresses[DexAddressType.RESERVE][0] ? 1 : 0;

            (
                uint128 amount,
                uint128 poolFee,
                uint128 beneficiaryFee
            ) = Math.calculateExpectedExchange(
                _spentAmount,
                _typeToReserves[DexReserveType.POOL][spentTokenIndex],
                _typeToReserves[DexReserveType.POOL][receiveTokenIndex],
                _fee
            );

            require(amount <= _typeToReserves[DexReserveType.POOL][receiveTokenIndex], DexErrors.NOT_ENOUGH_FUNDS);
            require(amount >= _expectedAmount, DexErrors.LOW_EXCHANGE_RATE);
            require(amount > 0, DexErrors.AMOUNT_TOO_LOW);
            require(poolFee > 0 || _fee.pool_numerator == 0, DexErrors.AMOUNT_TOO_LOW);
            require(beneficiaryFee > 0 || _fee.beneficiary_numerator == 0, DexErrors.AMOUNT_TOO_LOW);

            tvm.rawReserve(DexGas.PAIR_INITIAL_BALANCE, 0);

            _exchangeBase(
                _callId,
                true,
                spentTokenIndex,
                receiveTokenIndex,
                _spentAmount,
                beneficiaryFee,
                poolFee,
                amount,
                _accountOwner,
                _remainingGasTo
            );

            IDexAccount(msg.sender)
                .internalPairTransfer{ value: DexGas.INTERNAL_PAIR_TRANSFER_VALUE, flag: MsgFlag.SENDER_PAYS_FEES }
                (
                    amount,
                    _typeToRootAddresses[DexAddressType.RESERVE][receiveTokenIndex],
                    _typeToRootAddresses[DexAddressType.RESERVE][spentTokenIndex],
                    _typeToRootAddresses[DexAddressType.RESERVE][receiveTokenIndex],
                    _remainingGasTo
                );

            ISuccessCallback(msg.sender)
                .successCallback{ value: 0, flag: MsgFlag.ALL_NOT_RESERVED }
                (_callId);
        } else {
            revert(DexErrors.NOT_TOKEN_ROOT);
        }
    }

    /// @dev Internal exchange common part
    /// @param _callId ID of the call
    /// @param _isViaAccount Whether or not call was made from DEX account
    /// @param _spentAmount Amount for exchange
    /// @param _beneficiaryFee Calculated fee for beneficiary
    /// @param _poolFee Calculated fee for liquidity providers
    /// @param _amount Amount to exchange
    /// @param _senderAddress Address of the sender
    /// @param _remainingGasTo Receiver of the remaining gas
    function _exchangeBase(
        uint64 _callId,
        bool _isViaAccount,
        uint8 spentTokenIndex,
        uint8 receiveTokenIndex,
        uint128 _spentAmount,
        uint128 _beneficiaryFee,
        uint128 _poolFee,
        uint128 _amount,
        address _senderAddress,
        address _remainingGasTo
    ) private {
        // Update reserves
        _typeToReserves[DexReserveType.POOL][spentTokenIndex] += _spentAmount - _beneficiaryFee;
        _typeToReserves[DexReserveType.POOL][receiveTokenIndex] -= _amount;

        // Update accumulated fees
        if (_beneficiaryFee > 0) {
            _typeToReserves[DexReserveType.FEE][spentTokenIndex] += _beneficiaryFee;

            _processBeneficiaryFees(false, _remainingGasTo);
        }

        ExchangeFee[] fees;

        fees.push(
            ExchangeFee(
                _typeToRootAddresses[DexAddressType.RESERVE][spentTokenIndex],
                _poolFee,
                _beneficiaryFee,
                _fee.beneficiary
            )
        );

        // Emit event
        emit Exchange(
            _senderAddress,
            _senderAddress,
            _typeToRootAddresses[DexAddressType.RESERVE][spentTokenIndex],
            _spentAmount,
            _typeToRootAddresses[DexAddressType.RESERVE][receiveTokenIndex],
            _amount,
            fees
        );

        _sync();

        IDexPairOperationCallback(_senderAddress)
            .dexPairExchangeSuccess{
                value: DexGas.OPERATION_CALLBACK_BASE + 1,
                flag: MsgFlag.SENDER_PAYS_FEES + MsgFlag.IGNORE_ERRORS,
                bounce: false
            }(
                _callId,
                _isViaAccount,
                IExchangeResult.ExchangeResult(
                    true,
                    _spentAmount,
                    _poolFee + _beneficiaryFee,
                    _amount
                )
            );
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////////////
    // Cross-pair exchange

    function crossPoolExchange(
        uint64 _id,
        uint32,
        uint8,
        address[] _prevPoolTokenRoots,
        address _spentTokenRoot,
        uint128 _spentAmount,
        address _senderAddress,
        address _remainingGasTo,
        uint128 _deployWalletGrams,
        TvmCell _payload,
        bool _notifySuccess,
        TvmCell _successPayload,
        bool _notifyCancel,
        TvmCell _cancelPayload
    ) override external onlyPair(_prevPoolTokenRoots) onlyActive notSelfCall {
        tvm.rawReserve(DexGas.PAIR_INITIAL_BALANCE, 0);

        (
            uint128 expectedAmount,
            address nextPairOrTokenRoot,
            address outcoming,
            bool hasNextPayload,
            TvmCell nextPayload
        ) = PairPayload.decodeCrossPoolExchangePayload(_payload);

        uint8 spentTokenIndex = _spentTokenRoot == _typeToRootAddresses[DexAddressType.RESERVE][0] ? 0 : 1;
        uint8 receiveTokenIndex = _spentTokenRoot == _typeToRootAddresses[DexAddressType.RESERVE][0] ? 1 : 0;
        address vault = _typeToRootAddresses[DexAddressType.VAULT][0];

        if (
            _spentTokenRoot == _typeToRootAddresses[DexAddressType.RESERVE][0] ||
            _spentTokenRoot == _typeToRootAddresses[DexAddressType.RESERVE][1]
        ) {
            (
                uint128 amount,
                uint128 poolFee,
                uint128 beneficiaryFee
            ) = Math.calculateExpectedExchange(
                _spentAmount,
                _typeToReserves[DexReserveType.POOL][spentTokenIndex],
                _typeToReserves[DexReserveType.POOL][receiveTokenIndex],
                _fee
            );

            if (
                amount <= _typeToReserves[DexReserveType.POOL][receiveTokenIndex] &&
                amount >= expectedAmount &&
                amount > 0 &&
                (poolFee > 0 || _fee.pool_numerator == 0) &&
                (beneficiaryFee > 0 || _fee.beneficiary_numerator == 0)
            ) {
                _exchangeBase(
                    _id,
                    false,
                    spentTokenIndex,
                    receiveTokenIndex,
                    _spentAmount,
                    beneficiaryFee,
                    poolFee,
                    amount,
                    _senderAddress,
                    _remainingGasTo
                );

                address nextPair;

                if (outcoming.value != 0) {
                    nextPair = nextPairOrTokenRoot;
                } else {
                    nextPair = _expectedPairAddress([
                        _typeToRootAddresses[DexAddressType.RESERVE][receiveTokenIndex],
                        nextPairOrTokenRoot
                    ]);
                }

                if (
                    nextPair != address(this) &&
                    hasNextPayload &&
                    nextPayload.toSlice().bits() >= 128 &&
                    msg.value >= DexGas.DIRECT_PAIR_OP_MIN_VALUE_V2
                ) {
                    IDexPair(nextPair)
                        .crossPoolExchange{ value: 0, flag: MsgFlag.ALL_NOT_RESERVED }
                        (
                            _id,
                            _currentVersion,
                            DexPoolTypes.CONSTANT_PRODUCT,
                            _tokenRoots(),
                            _typeToRootAddresses[DexAddressType.RESERVE][receiveTokenIndex],
                            amount,
                            _senderAddress,
                            _remainingGasTo,
                            _deployWalletGrams,
                            nextPayload,
                            _notifySuccess,
                            _successPayload,
                            _notifyCancel,
                            _cancelPayload
                        );
                } else {
                    IDexVault(vault)
                        .transfer{ value: 0, flag: MsgFlag.ALL_NOT_RESERVED }
                        (
                            amount,
                            _typeToRootAddresses[DexAddressType.RESERVE][receiveTokenIndex],
                            _typeToWalletAddresses[DexAddressType.VAULT][receiveTokenIndex],
                            _senderAddress,
                            _deployWalletGrams,
                            true,
                            _successPayload,
                            _typeToRootAddresses[DexAddressType.RESERVE][spentTokenIndex],
                            _typeToRootAddresses[DexAddressType.RESERVE][receiveTokenIndex],
                            _currentVersion,
                            _remainingGasTo
                        );
                }
            } else {
                IDexPairOperationCallback(_senderAddress)
                    .dexPairOperationCancelled{
                        value: DexGas.OPERATION_CALLBACK_BASE + 44,
                        flag: MsgFlag.SENDER_PAYS_FEES + MsgFlag.IGNORE_ERRORS,
                        bounce: false
                    }(_id);

                IDexVault(vault)
                    .transfer{ value: 0, flag: MsgFlag.ALL_NOT_RESERVED }
                    (
                        _spentAmount,
                        _spentTokenRoot,
                        _typeToWalletAddresses[DexAddressType.VAULT][spentTokenIndex],
                        _senderAddress,
                        _deployWalletGrams,
                        true,
                        _cancelPayload,
                        _typeToRootAddresses[DexAddressType.RESERVE][spentTokenIndex],
                        _typeToRootAddresses[DexAddressType.RESERVE][receiveTokenIndex],
                        _currentVersion,
                        _remainingGasTo
                    );
            }
        } else {
            revert(DexErrors.NOT_TOKEN_ROOT);
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////////////
    // Callbacks

    function onAcceptTokensTransfer(
        address _tokenRoot,
        uint128 _tokensAmount,
        address _senderAddress,
        address _senderWallet,
        address _remainingGasTo,
        TvmCell _payload
    ) override external {
        tvm.rawReserve(DexGas.PAIR_INITIAL_BALANCE, 0);

        (
            bool isValid,
            uint64 id,
            uint8 op,
            uint128 deployWalletGrams,
            uint128 expectedAmount,
            address nextPairOrTokenRoot,
            address outcoming,
            bool hasRef3,
            TvmCell ref3,
            bool notifySuccess,
            TvmCell successPayload,
            bool notifyCancel,
            TvmCell cancelPayload
        ) = PairPayload.decodeOnAcceptTokensTransferPayload(_payload);

        TvmCell empty;

        bool needCancel = !_active || !isValid || _typeToReserves[DexReserveType.LP][0] == 0;

        if (!needCancel) {
            address lp = _typeToRootAddresses[DexAddressType.LP][0];
            address vault = _typeToRootAddresses[DexAddressType.VAULT][0];

            if (
                (_tokenRoot == _typeToRootAddresses[DexAddressType.RESERVE][0] || _tokenRoot == _typeToRootAddresses[DexAddressType.RESERVE][1]) &&
                (msg.sender == _typeToWalletAddresses[DexAddressType.RESERVE][0] || msg.sender == _typeToWalletAddresses[DexAddressType.RESERVE][1]) &&
                msg.value >= DexGas.DIRECT_PAIR_OP_MIN_VALUE_V2 + deployWalletGrams
            ) {
                uint8 spentTokenIndex = _tokenRoot == _typeToRootAddresses[DexAddressType.RESERVE][0] ? 0 : 1;
                uint8 receiveTokenIndex = _tokenRoot == _typeToRootAddresses[DexAddressType.RESERVE][0] ? 1 : 0;
                uint128 lpReserve = _typeToReserves[DexReserveType.LP][0];

                if (op == DexOperationTypes.EXCHANGE) {
                    (
                        uint128 amount,
                        uint128 poolFee,
                        uint128 beneficiaryFee
                    ) = Math.calculateExpectedExchange(
                        _tokensAmount,
                        _typeToReserves[DexReserveType.POOL][spentTokenIndex],
                        _typeToReserves[DexReserveType.POOL][receiveTokenIndex],
                        _fee
                    );

                    if (
                        amount <= _typeToReserves[DexReserveType.POOL][receiveTokenIndex] &&
                        amount >= expectedAmount &&
                        amount > 0 &&
                        (poolFee > 0 || _fee.pool_numerator == 0) &&
                        (beneficiaryFee > 0 || _fee.beneficiary_numerator == 0)
                    ) {
                        _exchangeBase(
                            id,
                            false,
                            spentTokenIndex,
                            receiveTokenIndex,
                            _tokensAmount,
                            beneficiaryFee,
                            poolFee,
                            amount,
                            _senderAddress,
                            _remainingGasTo
                        );

                        ITokenWallet(msg.sender)
                            .transfer{ value: DexGas.TRANSFER_TOKENS_VALUE, flag: MsgFlag.SENDER_PAYS_FEES }
                            (
                                _tokensAmount,
                                vault,
                                0,
                                _remainingGasTo,
                                false,
                                empty
                            );

                        IDexVault(vault)
                            .transfer{ value: 0, flag: MsgFlag.ALL_NOT_RESERVED }
                            (
                                amount,
                                _typeToRootAddresses[DexAddressType.RESERVE][receiveTokenIndex],
                                _typeToWalletAddresses[DexAddressType.VAULT][receiveTokenIndex],
                                _senderAddress,
                                deployWalletGrams,
                                notifySuccess,
                                successPayload,
                                _typeToRootAddresses[DexAddressType.RESERVE][spentTokenIndex],
                                _typeToRootAddresses[DexAddressType.RESERVE][receiveTokenIndex],
                                _currentVersion,
                                _remainingGasTo
                            );
                    } else {
                        needCancel = true;
                    }
                } else if (op == DexOperationTypes.DEPOSIT_LIQUIDITY) {
                    (
                        DepositLiquidityResult r,
                        uint128 step2PoolFee,
                        uint128 step2BeneficiaryFee
                    ) = Math.calculateExpectedDepositLiquidity(
                        _tokensAmount,
                        0,
                        true,
                        _typeToReserves[DexReserveType.POOL][spentTokenIndex],
                        _typeToReserves[DexReserveType.POOL][receiveTokenIndex],
                        lpReserve,
                        _fee
                    );

                    if (
                        r.step_3_lp_reward > 0 &&
                        r.step_2_received <= _typeToReserves[DexReserveType.POOL][receiveTokenIndex] &&
                        r.step_2_received > 0 &&
                        (step2PoolFee > 0 || _fee.pool_numerator == 0) &&
                        (step2BeneficiaryFee > 0 || _fee.beneficiary_numerator == 0)
                    ) {
                        _exchangeBase(
                            id,
                            false,
                            spentTokenIndex,
                            receiveTokenIndex,
                            _tokensAmount,
                            step2BeneficiaryFee,
                            step2PoolFee,
                            0,
                            _senderAddress,
                            _remainingGasTo
                        );

                        _depositLiquidityBase(
                            id,
                            false,
                            r,
                            _senderAddress
                        );

                        ITokenWallet(msg.sender)
                            .transfer{ value: DexGas.TRANSFER_TOKENS_VALUE, flag: MsgFlag.SENDER_PAYS_FEES }
                            (
                                _tokensAmount,
                                vault,
                                0,
                                _remainingGasTo,
                                false,
                                empty
                            );

                        ITokenRoot(lp)
                            .mint{ value: 0, flag: MsgFlag.ALL_NOT_RESERVED }
                            (
                                r.step_3_lp_reward,
                                _senderAddress,
                                deployWalletGrams,
                                _remainingGasTo,
                                notifySuccess,
                                successPayload
                            );
                    } else {
                        needCancel = true;
                    }
                } else if (
                    op == DexOperationTypes.CROSS_PAIR_EXCHANGE &&
                    notifySuccess &&
                    successPayload.toSlice().bits() >= 128
                ) {
                    (
                        uint128 amount,
                        uint128 poolFee,
                        uint128 beneficiaryFee
                    ) = Math.calculateExpectedExchange(
                        _tokensAmount,
                        _typeToReserves[DexReserveType.POOL][spentTokenIndex],
                        _typeToReserves[DexReserveType.POOL][receiveTokenIndex],
                        _fee
                    );

                    address nextPair;

                    if (outcoming.value != 0) {
                        nextPair = nextPairOrTokenRoot;
                    } else {
                        nextPair = _expectedPairAddress([
                            _typeToRootAddresses[DexAddressType.RESERVE][receiveTokenIndex],
                            nextPairOrTokenRoot
                        ]);
                    }

                    if (
                        amount <= _typeToReserves[DexReserveType.POOL][receiveTokenIndex] &&
                        amount >= expectedAmount &&
                        amount > 0 &&
                        (poolFee > 0 || _fee.pool_numerator == 0) &&
                        (beneficiaryFee > 0 || _fee.beneficiary_numerator == 0) &&
                        nextPair != address(this)
                    ) {
                        _exchangeBase(
                            id,
                            false,
                            spentTokenIndex,
                            receiveTokenIndex,
                            _tokensAmount,
                            beneficiaryFee,
                            poolFee,
                            amount,
                            _senderAddress,
                            _remainingGasTo
                        );

                        ITokenWallet(msg.sender)
                            .transfer{ value: DexGas.TRANSFER_TOKENS_VALUE, flag: MsgFlag.SENDER_PAYS_FEES }
                            (
                                _tokensAmount,
                                vault,
                                0,
                                _remainingGasTo,
                                false,
                                empty
                            );

                        IDexPair(nextPair)
                            .crossPoolExchange{ value: 0, flag: MsgFlag.ALL_NOT_RESERVED }
                            (
                                id,
                                _currentVersion,
                                DexPoolTypes.CONSTANT_PRODUCT,
                                _tokenRoots(),
                                _typeToRootAddresses[DexAddressType.RESERVE][receiveTokenIndex],
                                amount,
                                _senderAddress,
                                _remainingGasTo,
                                deployWalletGrams,
                                successPayload,    // actually it is next_payload
                                notifyCancel,      // actually it is notify_success
                                cancelPayload,     // actually it is success_payload
                                hasRef3,            // actually it is notify_success
                                ref3                // actually it is cancel_payload
                            );
                    } else {
                        needCancel = true;
                    }
                } else {
                    needCancel = true;
                }
            } else if (
                op == DexOperationTypes.WITHDRAW_LIQUIDITY &&
                _tokenRoot == lp &&
                msg.sender == _typeToWalletAddresses[DexAddressType.LP][0] &&
                msg.value >= DexGas.DIRECT_PAIR_OP_MIN_VALUE_V2 + 2 * deployWalletGrams
            ) {
                _withdrawBase(
                    id,
                    false,
                    _tokensAmount,
                    _senderAddress,
                    _remainingGasTo,
                    deployWalletGrams,
                    notifySuccess,
                    successPayload
                );

                IBurnableTokenWallet(msg.sender)
                    .burn{ value: 0, flag: MsgFlag.ALL_NOT_RESERVED }
                    (
                        _tokensAmount,
                        _remainingGasTo,
                        address.makeAddrStd(0, 0),
                        empty
                    );
            } else {
                needCancel = true;
            }
        }

        if (needCancel) {
            IDexPairOperationCallback(_senderAddress)
                .dexPairOperationCancelled{
                    value: DexGas.OPERATION_CALLBACK_BASE + 44,
                    flag: MsgFlag.SENDER_PAYS_FEES + MsgFlag.IGNORE_ERRORS,
                    bounce: false
                }(id);

            ITokenWallet(msg.sender)
                .transferToWallet{ value: 0, flag: MsgFlag.ALL_NOT_RESERVED }
                (
                    _tokensAmount,
                    _senderWallet,
                    _remainingGasTo,
                    notifyCancel,
                    cancelPayload
                );
        }
    }
}
