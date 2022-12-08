pragma ton-solidity >=0.57.0;


interface IOrderRoot {
	event CreateOrder(
		address order,
		address spentToken,
		uint128 spentAmount,
		address receiveToken,
		uint128 expectedAmount
	);
	event OrderRootCodeUpgraded(uint32 newVersion);

	function getVersion() external view responsible returns(uint32);
	function getSpentToken() external view responsible returns (address);
	function getFactory() external view responsible returns (address);
	function expectedAddressOrder(
		address root,
		address factory,
		address owner,
		address spentToken,
		address receiveToken,
		uint64 timeTx,
		uint64 nowTx
	) external view responsible returns (address);
	function upgrade(TvmCell _code, uint32 _newVersion, address _sendGasTo, uint64 callbackId) external;
}
