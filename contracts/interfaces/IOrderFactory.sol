pragma ton-solidity >=0.62.0;

import "../structures/IOrderFeeParams.sol";

interface IOrderFactory is IOrderFeeParams {
    
    event RequestedOwnerTransfer(
        address oldOwner, 
        address newOwner
    );
    
    event OwnerTransferAccepted(
        address oldOwner,
        address newOwner
    );
    event OrderFeesParamsUpdated(OrderFeeParams params);
    event OrderRootCodeUpgraded(uint32 oldVersion, uint32 newVersion);
    event OrderCodeUpgraded(uint32 oldVersion, uint32 newVersion);
    event OrderClosedCodeUpgraded(uint32 oldVersion, uint32 newVersion);
    event PlatformCodeUpgraded();
    event CreateOrderRoot(
        address order,
        address token
    );
    event CreateOrderRootReject(address token);
    event OrderFactoryUpgrade(uint32 oldVersion, uint32 newVersion);

    function createOrderRoot(
        address token,
        uint64 callbackId
    ) external;

    function setFeeParams(OrderFeeParams params) external;
    function setRootFeeParams(OrderFeeParams params, address root) external;
    function setOrderFeeParams(OrderFeeParams params, address order) external;
    function withdrawFee(address orderRoot, uint128 amount, address recipient, address rm_gas_to) external;
    function getFeeParams() external view responsible returns (OrderFeeParams);

    function getExpectedAddressOrderRoot(address token)
		external
		view
		responsible
		returns (address);

    function onOrderRootDeployed(
        address orderRoot,
        address token,
        address sendGasTo
    ) external;

    function upgrade(
        TvmCell newCode, 
        uint32 newVersion,
        address sendGasTo
    ) external;
}
