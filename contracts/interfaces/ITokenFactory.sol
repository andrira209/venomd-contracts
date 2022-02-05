pragma ton-solidity >= 0.57.0;

import "../../node_modules/ton-eth-bridge-token-contracts/contracts/interfaces/ITokenRoot.sol";

interface ITokenFactory {
    function createToken(
        uint32 callId,
        bytes name,
        bytes symbol,
        uint8 decimals,
        address initialSupplyTo,
        uint128 initialSupply,
        uint128 deployWalletValue,
        bool mintDisabled,
        bool burnByRootDisabled,
        bool burnPaused,
        address remainingGasTo
    ) external;
}
