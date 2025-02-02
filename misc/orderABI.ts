export class OrderCallbacks {
    static Callbacks = {
        'ABI version': 2,
        header: ['time'],
        "functions" : [
            {
                name: "onOrderRootCreateSuccess",
                inputs: [
                    { name: 'id', type: 'uint64' },
                    { name: 'result',
                        components: [
                            { name: 'factory', type: 'address' },
                            { name: 'spentToken', type: 'address' },
                            { name: 'oldVersion', type: 'uint32' },
                            { name: 'newVersion', type: 'uint32' },
                            { name: 'deployer', type: 'address' },
                        ],
                        type: 'tuple' },
                ],
                outputs: []
            },
            {
                name: "onOrderRootCreateReject",
                inputs: [
                    { name: 'id', type: 'uint64' },
                ],
                outputs: []
            },
            {
                name: "onOrderCreateOrderSuccess",
                inputs: [
                    { name: 'id', type: 'uint64' },
                    { name: 'order', type: 'address'}
                ],
                outputs: []
            },
            {
                name: "onOrderCreateOrderReject",
                inputs: [
                    { name: 'id', type: 'uint64' },
                    { name: 'errorCode', type: 'uint16' },
                ],
                outputs: []
            },
            {
                name: "onOrderPartExchangeSuccess",
                inputs: [
                    { name: 'id', type: 'uint64'},
                    { name: 'owner', type: 'address'},
                    { name: 'fee', type: 'uint128' },
                    { name: 'result',
                        components: [
                            { name: 'spentToken', type: 'address'},
                            { name: 'spentAmount', type: 'uint128'},
                            { name: 'receiveToken', type: 'address'},
                            { name: 'receiveAmount', type: 'uint128'},
                            { name: 'currentSpentTokenAmount', type: 'uint128'},
                            { name: 'currentReceiveTokenAmount', type: 'uint128'},
                        ],
                        type: 'tuple'},
                ],
                outputs: []
            },
            {
                name: "onOrderStateFilled",
                inputs: [
                    { name: 'id', type: 'uint64'},
                    { name: 'owner', type: 'address'},
                    { name: 'fee', type: 'uint128' },
                    { name: 'result',
                        components: [
                            { name: 'spentToken', type: 'address' },
                            { name: 'spentAmount', type: 'uint128'},
                            { name: 'receiveToken', type: 'address'},
                            { name: 'receiveAmount', type: 'uint128'},
                        ],
                        type: 'tuple'},
                ],
                outputs: []
            },
            {
                name: "onOrderStateCancelled",
                inputs: [
                    { name: 'id', type: 'uint64'},
                    { name: 'result',
                        components: [
                            { name: 'spentToken', type: 'address' },
                            { name: 'currentSpentTokenAmount', type: 'uint128'},
                        ],
                        type: 'tuple'},
                ],
                outputs: []
            },
            {
                name: "onOrderStateCancelledReject",
                inputs: [
                  { name: 'id', type: 'uint64'},
                ],
                outputs: []
            },
            {
                name: "onOrderReject",
                inputs: [
                    { name: 'id', type: 'uint64' },
                ],
                outputs: []
            },
            {
                name: "onOrderSwapSuccess",
                inputs: [
                    { name: 'id', type: 'uint64'},
                    { name: 'result',
                        components: [
                            { name: 'owner', type: 'address' },
                            { name: 'initiator', type: 'address' },
                            { name: 'reward', type: 'uint128'},
                        ],
                        type: 'tuple' },
                ],
                outputs: []
            },
            {
                name: "onOrderSwapCancel",
                inputs: [
                    { name: 'id', type: 'uint64' },
                ],
                outputs: []
            },
            {
                name: "onMatchingCancel",
                inputs: [
                    { name: 'id', type: 'uint64' },
                ],
                outputs: []
            },
            {
                name: "onMatchingInProgress",
                inputs: [
                    { name: 'id', type: 'uint64' },
                    { name: 'result',
                        components: [
                            { name: 'mainOrder', type: 'address' },
                            { name: 'alienOrder', type: 'address' },
                            { name: 'spentToken', type: 'address' },
                            { name: 'receiveToken', type: 'address' },
                            { name: 'spentAmount', type: 'uint128' },
                            { name: 'receiveAmount', type: 'uint128' },
                            { name: 'rewardInitiator', type: 'uint128' },
                        ],
                        type: 'tuple' },
                ],
                outputs: []
            },
        ],
        data: [],
        events: [],
    } as const;
}