pragma ton-solidity >= 0.62.0;

pragma AbiHeader time;
pragma AbiHeader expire;
pragma AbiHeader pubkey;

import "../libraries/DexPlatformTypes.sol";

import "../DexPlatform.sol";

abstract contract DexContractBase  {
    TvmCell public platform_code;

    modifier onlyPlatform(
        uint8 _typeId,
        TvmCell _params
    ) {
        address expected = address(
            tvm.hash(
                _buildInitData(
                    _typeId,
                    _params
                )
            )
        );

        require(msg.sender == expected, DexErrors.NOT_PLATFORM);
        _;
    }

    modifier onlyAccount(address _accountOwner) {
        require(msg.sender == _expectedAccountAddress(_accountOwner), DexErrors.NOT_ACCOUNT);
        _;
    }

    modifier onlyPool(address[] _roots) {
        require(msg.sender == _expectedPoolAddress(_roots), DexErrors.NOT_POOL);
        _;
    }

    modifier onlyTokenVault(address _tokenRoot) {
        require(msg.sender == _expectedTokenVaultAddress(_tokenRoot), DexErrors.NOT_TOKEN_VAULT);
        _;
    }

    function _dexRoot() virtual internal view returns (address);

    function _expectedAccountAddress(address _accountOwner) internal view returns (address) {
        return address(
            tvm.hash(
                _buildInitData(
                    DexPlatformTypes.Account,
                    _buildAccountParams(_accountOwner)
                )
            )
        );
    }

    function _expectedPoolAddress(address[] _roots) internal view returns (address) {
        return address(
            tvm.hash(
                _buildInitData(
                    DexPlatformTypes.Pool,
                    _buildPairParams(_roots)
                )
            )
        );
    }

    function _expectedTokenVaultAddress(address _tokenRoot) internal view returns (address) {
        return address(
            tvm.hash(
                _buildInitData(
                    DexPlatformTypes.Vault,
                    _buildTokenVaultParams(_tokenRoot)
                )
            )
        );
    }

    function _buildAccountParams(address _accountOwner) internal pure returns (TvmCell) {
        TvmBuilder builder;

        builder.store(_accountOwner);

        return builder.toCell();
    }

    function _buildTokenVaultParams(address _tokenRoot) internal pure returns (TvmCell) {
        TvmBuilder builder;

        builder.store(_tokenRoot);

        return builder.toCell();
    }

    function _buildPairParams(address[] _roots) internal pure returns (TvmCell) {
        mapping(address => uint8) sorted;

        for (address root : _roots) {
            sorted[root] = 0;
        }

        if (_roots.length < 3) {
            TvmBuilder builder;

            for ((address key,) : sorted) {
                builder.store(key);
            }

            return builder.toCell();
        } else {
            address[] r = new address[](0);
            for ((address key,) : sorted) {
                r.push(key);
            }
            return abi.encode(r);
        }
    }

    function _buildInitData(
        uint8 _typeId,
        TvmCell _params
    ) internal view returns (TvmCell) {
        return tvm.buildStateInit({
            contr: DexPlatform,
            varInit: {
                root: _dexRoot(),
                type_id: _typeId,
                params: _params
            },
            pubkey: 0,
            code: platform_code
        });
    }
}
