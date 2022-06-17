pragma ton-solidity >= 0.57.0;

library DexErrors {
    uint16 constant TODO = 777;

    uint16 constant NOT_MY_OWNER                     = 100;
    uint16 constant NOT_ROOT                         = 101;
    uint16 constant NOT_PENDING_OWNER                = 102;
    uint16 constant VALUE_TOO_LOW                    = 103;
    uint16 constant NOT_PLATFORM                     = 104;
    uint16 constant NOT_ACCOUNT                      = 105;
    uint16 constant NOT_PAIR                         = 106;
    uint16 constant PLATFORM_CODE_EMPTY              = 107;
    uint16 constant PLATFORM_CODE_NON_EMPTY          = 108;
    uint16 constant ACCOUNT_CODE_EMPTY               = 109;
    uint16 constant PAIR_CODE_EMPTY                  = 110;
    uint16 constant INVALID_ADDRESS                  = 111;
    uint16 constant NOT_TOKEN_ROOT                   = 112;
    uint16 constant NOT_LP_TOKEN_ROOT                = 113;
    uint16 constant NOT_ACTIVE                       = 114;
    uint16 constant NOT_VAULT                        = 115;
    uint16 constant AMOUNT_TOO_LOW                   = 116;
    uint16 constant UNKNOWN_TOKEN_ROOT               = 117;
    uint16 constant NOT_ENOUGH_FUNDS                 = 118;
    uint16 constant INVALID_CALLBACK                 = 119;
    uint16 constant INVALID_CALLBACK_SENDER          = 120;
    uint16 constant WRONG_PAIR                       = 121;
    uint16 constant ANOTHER_WITHDRAWAL_IN_PROGRESS   = 122;
    uint16 constant LOW_EXCHANGE_RATE                = 123;
    uint16 constant NOT_LP_PENDING_CONTRACT          = 124;
    uint16 constant NOT_TOKEN_FACTORY                = 125;
    uint16 constant NOT_EXPECTED_TOKEN               = 126;
    uint16 constant WRONG_LIQUIDITY                  = 127;
    uint16 constant WRONG_RECIPIENT                  = 128;
    uint16 constant WRONG_PAIR_VERSION               = 129;
    uint16 constant OPERATION_ALREADY_IN_PROGRESS    = 130;
    uint16 constant WRONG_FEE_PARAMS                 = 131;
    uint16 constant NOT_BENEFICIARY                  = 132;
    uint16 constant UNSUPPORTED_POOL_TYPE            = 133;
    uint16 constant WRONG_AMOUNT                     = 134;
    uint16 constant WRONG_TOKEN_ROOT                 = 135;

    /// @dev The timestamp must be positive
    uint16 constant NON_POSITIVE_TIMESTAMP           = 136;

    /// @dev fromTimestamp must be lower or equal to the toTimestamp
    uint16 constant FROM_IS_BIGGER_THAN_TO           = 137;

    /// @dev Oracle was already initialized
    uint16 constant ALREADY_INITIALIZED              = 138;

    /// @dev Oracle is not initialized
    uint16 constant NOT_INITIALIZED                  = 139;

    /// @dev Caller must be owner of the pair
    uint16 constant CALLER_IS_NOT_OWNER              = 140;

    /// @dev A new cardinality must be bigger than previous
    uint16 constant LOWER_OR_EQUAL_CARDINALITY       = 141;
}
