# nbnet architecture

nbnet executes EVM blocks on [Hotmint](https://github.com/NBnet/hotmint) and serves a subset of Ethereum JSON-RPC. Consensus, networking, the WAL, and the evidence store are Hotmint's. This repository is the application: transaction checks, revm, world state, the nonce pool, two precompiles, RPC, and the `nb` binary.

It is not a full Ethereum client, and it does not embed Substrate pallets or `hotmint-staking`.

## Crates

| Crate | Role |
|-------|------|
| `nbnet-types` | Chain config, genesis, EIP-1559/legacy decode and sender recovery, receipts |
| `nbnet-state` | `EvmState`: revm `CacheDB` over vsdb `MapxOrdRawKey`, plus an MPT (`MptCalc`) whose root is `app_hash` |
| `nbnet-txpool` | Pending vs queued pool keyed by `(sender, nonce)`, with RBF and per-sender caps |
| `nbnet-execution` | `EvmExecutor` / `SharedExecutor` implement Hotmint `Application` |
| `nbnet-precompile` | `0x0800` balances, `0x0801` staking lock |
| `nbnet-rpc` | axum JSON-RPC |
| `nbnet-node` | `nb` binary, local cluster helper, benchmark |

## Block path

1. `validate_tx` decodes the raw bytes, recovers the sender, and rejects a wrong chain id, a nonce below the account, insufficient balance, or a gas limit the block cannot hold. The priority is the effective tip.
2. The pool keeps nonces that are contiguous from the account nonce in `pending`. A gap goes to `queued` until the predecessor arrives. The same `(sender, nonce)` is replaced only by a higher tip.
3. `create_payload` packs pending transactions up to 4 MiB and the block gas limit.
4. `execute_block` runs those transactions in order through revm (`SpecId::CANCUN`) and `transact_commit`. A transaction that does not decode, or whose nonce is not the account nonce at that step, is skipped and writes nothing. A transaction that would exceed the remaining block gas is not started. A revert or halt does not keep that call's storage writes.
5. After the block, `flush_cache_to_vsdb` copies the cache into vsdb and the trie, then `state_root` becomes `EndBlockResponse.app_hash`.
6. `on_commit` stores the height and drops pool entries below the new account nonce.

Genesis allocation is a `BTreeMap`. Account leaves are big-endian `nonce(8) || balance(32) || code_hash(32)`. A `HashMap` walk must not be hashed into `app_hash`.

`BLOCKHASH` currently records `B256::ZERO` for the parent. That placeholder is not part of the account leaf.

## Precompiles

| Address | Selectors | State |
|---------|-----------|--------|
| `0x0800` balances | `balanceOf(address)` `0x70a08231`, `transfer(address,uint256)` `0xa9059cbb` | Account balances in the revm journal, so they are in the trie |
| `0x0801` staking | `delegate(address,uint256)` `0x026e402b`, `unbond(address,uint256)` `0xa5d059ca`, `getStake(address,address)` `0x82dda22d`, `totalStake(address)` `0xb273fc9a` | The token lock is a journal transfer to `0x0801` (in the trie). The delegation map is a process-local `HashMap` and is not part of `app_hash`. It is empty after a restart |

There is no `register` selector and no call into `hotmint-staking`.

## JSON-RPC

Implemented on `POST /`. Enough for basic wallets and Foundry against this chain. Not a complete Ethereum API.

| Method | Behavior |
|--------|----------|
| `eth_chainId`, `net_version`, `web3_clientVersion` | Chain id from genesis. The client version string is the hardcoded `nbnet/0.1.1` |
| `eth_blockNumber` | Committed height |
| `eth_getBalance`, `eth_getTransactionCount`, `eth_getCode`, `eth_getStorageAt` | Current executor state |
| `eth_gasPrice` | Configured base fee |
| `eth_maxPriorityFeePerGas` | Constant `1_000_000_000` |
| `eth_call` | Dry-run. Does not commit |
| `eth_estimateGas` | Dry-run, then returns `21000` when `to` is set and `100000` otherwise. Not the gas the dry-run used |
| `eth_sendRawTransaction` | Pool submit, then gossip when a network sink is attached |
| `eth_getTransactionReceipt`, `eth_getLogs` | In-memory receipts for this process. Empty after a restart |
| `eth_getTransactionByHash` | Rebuilt from the receipt. `value` is `0x0` and `gas` is gas used |
| `eth_getBlockByNumber` | Stub for the latest height: zero hash and parent, zero timestamp, null transaction entries, receipt count as the transaction count |
| `eth_getBlockByHash` | Always `null` |
| `eth_feeHistory` | Constant stub from the configured base fee |
| `eth_syncing` | Always `false` |
| `eth_accounts` | Always `[]` |

Anything else returns JSON-RPC `-32601`.

## Node

The binary is `nb`. `--home` is global and defaults to `~/.nbnet`.

```bash
nb init --home ~/.nbnet
nb node --home ~/.nbnet --rpc-addr 127.0.0.1:8545
```

`init` writes the Hotmint home (`config.toml`, `genesis.json`, keys) and `config/evm-genesis.json`. `node` loads both. Default RPC listen address is `127.0.0.1:8545`.

`crates/node/src/cluster.rs` can init several homes and start `nb --home <dir> node --rpc-addr <ip:port>` for tests and the benchmark.

## What this document used to claim

Earlier notes described a Substrate pallet port, a staking precompile at `0x0800` backed by `hotmint-staking`, a per-transaction vsdb write batch, and feature parity with a full Ethereum JSON-RPC node. None of that matches the crates. The sections above are the current behavior.
