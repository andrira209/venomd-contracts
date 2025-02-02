import {toNano} from "locklift";
import {Account} from "everscale-standalone-client/nodejs";

import { displayTx, Migration } from '../utils/migration';
const migration = new Migration();

async function main() {
  const rootOwner = await migration.loadAccount('Account1', '0');
  const dexRoot = migration.loadContract('DexRoot', 'DexRoot');
  const DexAccount = await locklift.factory.getContractArtifacts('DexAccount');

  console.log(`Installing new DexAccount contract in DexRoot: ${dexRoot.address}`);
  await locklift.transactions.waitFinalized(dexRoot.methods.installOrUpdateAccountCode(
      {code: DexAccount.code}
  ).send({
    from: rootOwner.address,
    amount: toNano(1)
  }));

  const accounts_to_force_update: Account[] = [];
  await Promise.all([1, 2, 3].filter((n) => migration.exists('DexAccount' + n)).map(async (n) => {
    console.log(`Add DexAccount ${n} to upgrade`);

    const account = await migration.loadAccount('Account' + n, String(n - 1));
    accounts_to_force_update.push(account);
  }));

  await Promise.all(accounts_to_force_update.map(async (account) => {
    console.log(`Upgrading DexAccount contract: owner=${account.address}`);

    const tx = await locklift.transactions.waitFinalized(dexRoot.methods.forceUpgradeAccount(
        {
          account_owner: account.address,
          send_gas_to: account.address
        }
    ).send({
      from: rootOwner.address,
      amount: toNano(6)
    }));
    displayTx(tx);
  }));
}

main()
  .then(() => process.exit(0))
  .catch(e => {
    console.log(e);
    process.exit(1);
  });
