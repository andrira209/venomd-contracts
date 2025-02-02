import { toNano } from 'locklift';
import { Migration, Constants, EMPTY_TVM_CELL } from '../utils/migration';

import { Command } from 'commander';
const program = new Command();
import { BigNumber } from 'bignumber.js';
BigNumber.config({ EXPONENTIAL_AT: 257 });

async function main() {
  const migration = new Migration();

  const rootOwner = await migration.loadAccount('Account1', '0');

  program
    .allowUnknownOption()
    .option('-m, --mints <mints>', 'mint params')
    .option('-t, --to <to>', 'mint params');

  program.parse(process.argv);

  const options = program.opts();

  const mints = options.mints
    ? JSON.parse(options.mints)
    : [
        {
          amount: 20000,
          token: 'foo',
        },
      ];

  const to =
    options.to ||
    '0:0000000000000000000000000000000000000000000000000000000000000000';

  for (const mint of mints) {
    const token = Constants.tokens[mint.token];
    const amount = new BigNumber(mint.amount)
      .shiftedBy(token.decimals)
      .toFixed();

    const tokenRoot = migration.loadContract(
      token.upgradeable ? 'TokenRootUpgradeable' : 'TokenRoot',
      token.symbol + 'Root',
    );

    await tokenRoot.methods
      .mint({
        amount: amount,
        recipient: to,
        deployWalletValue: toNano(0.2),
        remainingGasTo: rootOwner.address,
        notify: false,
        payload: EMPTY_TVM_CELL,
      })
      .send({
        from: rootOwner.address,
        amount: toNano(0.5),
      });
  }
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.log(e);
    process.exit(1);
  });
