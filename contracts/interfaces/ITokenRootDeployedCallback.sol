pragma ton-solidity >= 0.62.0;

interface ITokenRootDeployedCallback {
    function onTokenRootDeployed(uint32 callId, address tokenRoot) external;
}
