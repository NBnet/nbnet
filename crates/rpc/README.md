# nbnet-rpc

Ethereum JSON-RPC subset for nbnet, served by [axum](https://crates.io/crates/axum) on `POST /`.

The method table, including stubs, is [docs/architecture.md](../../docs/architecture.md#json-rpc). In short:

- State queries (`eth_getBalance`, nonce, code, storage) read the live executor.
- `eth_call` is a dry-run and does not commit.
- `eth_estimateGas` dry-runs, then returns `21000` or `100000`. It does not return the gas the dry-run used.
- `eth_sendRawTransaction` submits to the pool and gossips when a `NetworkSink` is attached.
- Receipts and logs come from the in-memory receipt list. They do not survive a restart.
- `eth_getBlockByHash` is always `null`. `eth_getBlockByNumber`, `eth_feeHistory`, and `eth_syncing` are stubs.

## License

GPL-3.0-only
