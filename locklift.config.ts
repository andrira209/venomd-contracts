import { LockliftConfig, lockliftChai } from 'locklift';
import { FactorySource } from './build/factorySource';
import 'locklift-verifier';

import { Deployments } from 'locklift-deploy';

import chai from 'chai';
chai.use(lockliftChai);

declare global {
  // eslint-disable-next-line @typescript-eslint/ban-ts-comment
  // @ts-ignore
  const locklift: import('locklift').Locklift<FactorySource>;
}

declare module 'locklift' {
  // eslint-disable-next-line @typescript-eslint/ban-ts-comment
  // @ts-ignore
  export interface Locklift {
    deployments: Deployments<FactorySource>;
  }
}

const LOCAL_NETWORK_ENDPOINT = 'http://localhost:80/graphql';

// const LOCAL_NETWORK_ENDPOINT =
//   'https://evernode-no-limits.fairyfromalfeya.com/graphql';

const config: LockliftConfig = {
  compiler: {
    version: '0.62.0',
    externalContracts: {
      precompiled: ['DexPlatform', 'OrderRootPlatform', 'OrderPlatform'],
      'node_modules/tip3/build': [
        'TokenRootUpgradeable',
        'TokenWalletUpgradeable',
        'TokenWalletPlatform',
      ],
      'node_modules/ever-wever/everscale/build': [],
    },
  },
  linker: { version: '0.15.48' },
  verifier: {
    verifierVersion: 'latest', // contract verifier binary, see https://github.com/broxus/everscan-verify/releases
    apiKey: '',
    secretKey: '',
    // license: "AGPL-3.0-or-later", <- this is default value and can be overrided
  },
  networks: {
    local: {
      connection: {
        id: 1337,
        group: 'localnet',
        type: 'graphql',
        data: {
          endpoints: [LOCAL_NETWORK_ENDPOINT],
          latencyDetectionInterval: 1000,
          local: true,
        },
      },
      giver: {
        address:
          '0:ece57bcc6c530283becbbd8a3b24d3c5987cdddc3c8b7b33be6e4a6312490415',
        key: '172af540e43a524763dd53b26a066d472a97c4de37d5498170564510608250c3',
      },
      tracing: { endpoint: LOCAL_NETWORK_ENDPOINT },
      keys: {
        phrase:
          'action inject penalty envelope rabbit element slim tornado dinner pizza off blood',
        amount: 20,
      },
    },
    test: {
      // Specify connection settings for https://github.com/broxus/everscale-standalone-client/
      connection: {
        id: 0,
        group: 'testnet',
        type: 'graphql',
        data: {
          endpoints: [process.env.TESTNET_GQL_ENDPOINT],
          latencyDetectionInterval: 1000,
          local: false,
        },
      },
      // This giver is default local-node giverV2
      giver: {
        address: process.env.TESTNET_GIVER_ADDRESS ?? '',
        phrase: process.env.TESTNET_GIVER_SEED ?? '',
        accountId: 0,
      },
      tracing: {
        endpoint: process.env.TESTNET_GQL_ENDPOINT ?? '',
      },

      keys: {
        phrase: process.env.TESTNET_SEED_PHRASE ?? '',
        amount: 20,
      },
    },
    main: {
      connection: 'mainnetJrpc',
      giver: {
        address: process.env.MAIN_GIVER_ADDRESS ?? '',
        phrase: process.env.MAIN_GIVER_SEED ?? '',
        accountId: 0,
      },
      keys: {
        phrase: process.env.MAIN_SEED_PHRASE ?? '',
        amount: 20,
      },
    },
  },
  mocha: { timeout: 2000000 },
};

export default config;
