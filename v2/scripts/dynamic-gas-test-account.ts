import {Migration, displayTx, EMPTY_TVM_CELL, Constants} from '../utils/migration';
import {Address, toNano, zeroAddress} from "locklift";

const deposits = [
    { tokenId: 'foo', amount: '100000000000000000000000' },
    { tokenId: 'bar', amount: '100000000000000000000000' },
    { tokenId: 'qwe', amount: '100000000000000000000000' },
    { tokenId: 'tst', amount: '100000000000000000000000' },
    { tokenId: 'coin', amount: '100000000000000000000000' },
];

async function main() {
    const migration = new Migration();
    const mainAccount = await migration.loadAccount('Account1', '0');
    const additionalAccount = await migration.loadAccount('Account3', '2');
    const owner = await migration.loadAccount('Account2', '1');

    const dexAccountN = migration.loadContract('DexAccount', 'DexAccount' + 2);
    const dexPool = migration.loadContract('DexStablePool', 'DexPoolFooBarQwe');
    const poolLpRoot = migration.loadContract('TokenRootUpgradeable', 'FooBarQweLpRoot');
    const pairBarCoinLpRoot = migration.loadContract('TokenRootUpgradeable', 'BarCoinLpRoot');
    const pairTstBarLpRoot = migration.loadContract('TokenRootUpgradeable', 'TstBarLpRoot');
    const FooBarQweLpTstLpRoot = migration.loadContract('TokenRootUpgradeable', 'FooBarQweLpTstLpRoot');
    const dexRoot = migration.loadContract('DexRoot', 'DexRoot');
    const dexVault = migration.loadContract('DexVault', 'DexVault');

    const token_roots = [];
    const symbols = [];
    for (const deposit of deposits) {
        const symbol = Constants.tokens[deposit.tokenId].symbol;
        symbols.push(symbol);
        token_roots.push(migration.loadContract(
            'TokenRootUpgradeable',
            symbol + 'Root'
        ).address);
    }

    let fee = {
        "denominator": "1000000",
        "pool_numerator": "0",
        "beneficiary_numerator": "5000",
        "referrer_numerator": "5000",
        "beneficiary": additionalAccount.address,
        "threshold": [
            [
                token_roots[0],
                "500000000000"
            ],
            [
                token_roots[1],
                "500000000000"
            ],
            [
                token_roots[2],
                "500000000000"
            ]
        ],
        "referrer_threshold": []
    }

    // await dexVault.methods.setReferralProgramParams({params: {
    //         projectId: 0,
    //         projectAddress: new Address('0:262c8f1f919c7b7c23dfd6afc419e83be84b90689631b63e9bada61624789df0'),
    //         systemAddress: new Address('0:887e8e9d03d3d8d9769aebcdb58c7966f83511d663fef014891215d37f89a200')
    //     }}).send({
    //     from: mainAccount.address,
    //     amount: toNano(1),
    // });

    await dexRoot.methods.setPairFeeParams({
        _roots: token_roots.slice(0, 3),
        _params: fee,
        _remainingGasTo: mainAccount.address
    }).send({
        from: mainAccount.address,
        amount: toNano(1.5),
    });

    fee = {
        "denominator": "1000000",
        "pool_numerator": "0",
        "beneficiary_numerator": "5000",
        "referrer_numerator": "5000",
        "beneficiary": additionalAccount.address,
        "threshold": [
            [
                token_roots[1],
                "500000000000"
            ],
            [
                token_roots[4],
                "500000000000"
            ],
        ],
        "referrer_threshold": []
    }

    await dexRoot.methods.setPairFeeParams({
        _roots: [token_roots[1], token_roots[4]],
        _params: fee,
        _remainingGasTo: mainAccount.address
    }).send({
        from: mainAccount.address,
        amount: toNano(1.5),
    });

    await dexAccountN.methods.addPool({_roots: token_roots.slice(0, 3)}).send({
        from: owner.address,
        amount: toNano(4),
    });

    await dexAccountN.methods.addPool({_roots: [token_roots[1], token_roots[4]]}).send({
        from: owner.address,
        amount: toNano(4),
    });

    fee = {
        "denominator": "1000000",
        "pool_numerator": "0",
        "beneficiary_numerator": "5000",
        "referrer_numerator": "5000",
        "beneficiary": additionalAccount.address,
        "threshold": [
            [
                token_roots[1],
                "500000000000"
            ],
            [
                token_roots[3],
                "500000000000"
            ],
        ],
        "referrer_threshold": []
    }

    await dexRoot.methods.setPairFeeParams({
        _roots: [token_roots[1], token_roots[3]],
        _params: fee,
        _remainingGasTo: mainAccount.address
    }).send({
        from: mainAccount.address,
        amount: toNano(1.5),
    });

    await dexAccountN.methods.addPool({_roots: [token_roots[1], token_roots[3]]}).send({
        from: owner.address,
        amount: toNano(4),
    });

    fee = {
        "denominator": "1000000",
        "pool_numerator": "0",
        "beneficiary_numerator": "5000",
        "referrer_numerator": "5000",
        "beneficiary": additionalAccount.address,
        "threshold": [
            [
                token_roots[3],
                "500000000000"
            ],
            [
                poolLpRoot.address,
                "500"
            ],
        ],
        "referrer_threshold": []
    }

    await dexRoot.methods.setPairFeeParams({
        _roots: [token_roots[3], poolLpRoot.address],
        _params: fee,
        _remainingGasTo: mainAccount.address
    }).send({
        from: mainAccount.address,
        amount: toNano(1.5),
    });

    await dexAccountN.methods.addPool({_roots: [token_roots[3], poolLpRoot.address]}).send({
        from: owner.address,
        amount: toNano(4),
    });

    for (let i = 0; i < deposits.length; ++i) {
        const symbol = symbols[i];
        const accountWallet = migration.loadContract(
            'TokenWalletUpgradeable',
            symbol + 'Wallet' + 2
        );

        const tx = await accountWallet.methods.transfer({
            amount: deposits[i].amount,
            recipient: dexAccountN.address,
            deployWalletValue: 100000000,
            remainingGasTo: owner.address,
            notify: true,
            payload: EMPTY_TVM_CELL,
            // @ts-ignore
        }).send({
            from: owner.address,
            amount: toNano(2),
        });
        displayTx(tx);
    }

    // initial deposit
    let tx = await dexAccountN.methods.depositLiquidityV2({
        _callId: 123,
        _operations: [{amount: '10000000000000000000000', root: token_roots[0]},{amount: '10000000000000000000000', root: token_roots[1]},{amount: '10000000000000000000000', root: token_roots[2]}],
        _expected: {amount: '0', root: poolLpRoot.address},
        _autoChange: false,
        _remainingGasTo: owner.address,
        _referrer: owner.address
    }).send({
        from: owner.address,
        amount: toNano(4),
    });
    displayTx(tx);

    tx = await dexAccountN.methods.depositLiquidityV2({
        _callId: 123,
        _operations: [{amount: '10000000000000000000000', root: token_roots[1]},{amount: '10000000000000000000000', root: token_roots[4]}],
        _expected: {amount: '0', root: pairBarCoinLpRoot.address},
        _autoChange: false,
        _remainingGasTo: owner.address,
        _referrer: owner.address
    }).send({
        from: owner.address,
        amount: toNano(4),
    });
    displayTx(tx);

    tx = await dexAccountN.methods.depositLiquidityV2({
        _callId: 123,
        _operations: [{amount: '1000000000000000000000', root: token_roots[1]},{amount: '1000000000000000000000', root: token_roots[3]}],
        _expected: {amount: '0', root: pairTstBarLpRoot.address},
        _autoChange: false,
        _remainingGasTo: owner.address,
        _referrer: owner.address
    }).send({
        from: owner.address,
        amount: toNano(4),
    });
    displayTx(tx);

    const accountWallet = await locklift.factory.getDeployedContract('TokenWalletUpgradeable', (await poolLpRoot.methods
        .walletOf({
            answerId: 0,
            walletOwner: owner.address,
        })
        .call()).value0);

    await accountWallet.methods.transfer({
        amount: '1000000000000',
        recipient: dexAccountN.address,
        deployWalletValue: 100000000,
        remainingGasTo: owner.address,
        notify: true,
        payload: EMPTY_TVM_CELL,
        // @ts-ignore
    }).send({
        from: owner.address,
        amount: toNano(2),
    });
    displayTx(tx);


    tx = await dexAccountN.methods.depositLiquidityV2({
        _callId: 123,
        _operations: [{amount: '1000000000000', root: poolLpRoot.address},{amount: '10000000000000000000000', root: token_roots[3]}],
        _expected: {amount: '0', root: FooBarQweLpTstLpRoot.address},
        _autoChange: false,
        _remainingGasTo: owner.address,
        _referrer: owner.address
    }).send({
        from: owner.address,
        amount: toNano(4),
    });
    displayTx(tx);

    // let { traceTree } = await locklift.tracing.trace(dexAccountN.methods.withdraw({
    //         call_id: 123,
    //         amount: '10000000000000',
    //         token_root: token_roots[0],
    //         recipient_address: owner.address,
    //         deploy_wallet_grams: '100000000',
    //         send_gas_to: dexRoot.address
    //     }).send({
    //         from: owner.address,
    //         amount: toNano(1.5),
    //     })
    // );

    // let { traceTree } = await locklift.tracing.trace(dexAccountN.methods.transfer({
    //         call_id: 123,
    //         amount: '10000000000000',
    //         token_root: token_roots[0],
    //         recipient: owner.address,
    //         willing_to_deploy: true,
    //         send_gas_to: dexRoot.address
    // }).send({
    //         from: owner.address,
    //         amount: toNano(1),
    //     })
    // );

    // let { traceTree } = await locklift.tracing.trace(dexAccountN.methods.depositLiquidityV2({
    //         _callId: 123,
    //         _operations: [{amount: '100000000000000000000', root: token_roots[0]},{amount: '0', root: token_roots[1]},{amount: '0', root: token_roots[2]}],
    //         _expected: {amount: '0', root: poolLpRoot.address},
    //         _autoChange: true,
    //         _remainingGasTo: owner.address,
    //         _referrer: zeroAddress
    // }).send({
    //         from: owner.address,
    //         amount: toNano(2.5),
    //     })
    // );

    // let { traceTree } = await locklift.tracing.trace(dexAccountN.methods.exchangeV2({
    //         _callId: 123,
    //         _operation: {amount: '10000000000000', root: token_roots[0]},
    //         _expected: {amount: '0', root: token_roots[1]},
    //         _roots: token_roots,
    //         _remainingGasTo: owner.address
    // }).send({
    //         from: owner.address,
    //         amount: toNano(4),
    //     })
    // );

    // let { traceTree } = await locklift.tracing.trace(dexAccountN.methods.withdrawLiquidityV2({
    //         _callId: 123,
    //         _operation: {amount: '100000000000', root: poolLpRoot.address},
    //         _expected: [{amount: '0', root: token_roots[0]},{amount: '0', root: token_roots[1]},{amount: '0', root: token_roots[2]}],
    //         _remainingGasTo: owner.address
    //     }).send({
    //         from: owner.address,
    //         amount: toNano(4),
    //     })
    // );

    // let { traceTree } = await locklift.tracing.trace(dexAccountN.methods.withdrawLiquidityOneCoin({
    //         _callId: 123,
    //         _roots: token_roots,
    //         _operation: {amount: '100000000000', root: poolLpRoot.address},
    //         _expected: {amount: '0', root: token_roots[2]},
    //         _remainingGasTo: owner.address
    //     }).send({
    //         from: owner.address,
    //         amount: toNano(4),
    //     })
    // );

    // let { traceTree } = await locklift.tracing.trace(dexRoot.methods.forceUpgradeAccount({
    //         account_owner: additionalAccount.address,
    //         send_gas_to: mainAccount.address
    //     }).send({
    //         from: mainAccount.address,
    //         amount: toNano(6),
    //     })
    // );
    //
    // let { traceTree } = await locklift.tracing.trace(dexRoot.methods.upgradeTokenVault({
    //         _tokenRoot: token_roots[0],
    //         _remainingGasTo: mainAccount.address
    //     }).send({
    //         from: mainAccount.address,
    //         amount: toNano(6),
    //     })
    // );

    // let { traceTree } = await locklift.tracing.trace(dexRoot.methods.upgrade({
    //         code: await locklift.factory.getContractArtifacts('DexRoot').code,
    //     }).send({
    //         from: mainAccount.address,
    //         amount: toNano(6),
    //     })
    // );

    // let { traceTree } = await locklift.tracing.trace(dexVault.methods.upgrade({
    //         code: await locklift.factory.getContractArtifacts('DexVault').code,
    //     }).send({
    //         from: mainAccount.address,
    //         amount: toNano(6),
    //     })
    // );
    //
    // await traceTree?.beautyPrint();
    //
    // console.log("balanceChangeInfo");
    //
    // for(let addr in traceTree?.balanceChangeInfo) {
    //     console.log(addr + ": " + traceTree?.balanceChangeInfo[addr].balanceDiff.shiftedBy(-9).toString());
    // }
}

main()
    .then(() => process.exit(0))
    .catch((e) => {
        console.log(e);
        process.exit(1);
    });
