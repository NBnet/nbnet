# RPC and Node Review Patterns

## Files
- `crates/rpc/src/lib.rs` — axum `eth_*`, `net_*`, `web3_*`
- `crates/node/src/main.rs` — `nb` init/node, gossip, engine wiring
- `crates/node/src/cluster.rs` — local multi-node helper
- `crates/node/tests/e2e_rpc.rs` — RPC smoke test
- `crates/node/src/bench.rs` — throughput bench, not consensus state

## Architecture
- RPC reads balances, nonces, code, storage, receipts, and dry-run calls
  through `EvmExecutor` / `SharedExecutor`.
- The node builds `EvmState` and `EvmExecutor` from genesis, installs the
  nonce function, and passes `SharedExecutor` to Hotmint.
- Gossiped transactions are validated with `validate_tx` before they enter
  the pool. Submit from RPC uses `submit_raw_tx`.
- Consensus persistence (WAL, evidence, sync) is Hotmint's. This crate
  chooses when those Hotmint objects are opened and which app hash is
  returned.

## Critical Invariants

### INV-RPC1: Answers Match Executor State
**Check**: `eth_getBalance`, nonce, code, and storage use the state
getters. `eth_call` / `eth_estimateGas` use the dry-run path and do not
call `transact_commit`. A receipt lookup scans the executor's receipt
list.

### INV-RPC2: Gossip and RPC Share Validation
**Check**: `main.rs` does not push raw gossip bytes into the pool.
Wrong chain id and a nonce that is too low are rejected the same way as
a local submit.

### INV-RPC3: App Hash Handoff
**Check**: The hash stored for the engine is the `app_hash` from
`execute_block`, not a separately recomputed digest of a `HashMap`.
Restart loads world state from vsdb before the engine runs.

### INV-RPC4: Dry-Run Does Not Commit
**Check**: `eth_call` holds the state lock only for the read-only
execution and drops it before any `.await`. No receipt is appended.

## Common Bug Patterns

### Split State (technical-patterns.md 5.1)
The RPC server constructs a second `EvmState` that does not see the
executor's cache.

### Skipped Validation (technical-patterns.md 5.2)
The gossip task calls `txpool.submit` on bytes it did not validate.

## Review Checklist
- [ ] New RPC method documents the error for short or malformed params
- [ ] `eth_sendRawTransaction` returns the hash only after the pool accepts
- [ ] Cluster helper and e2e use the same genesis chain id they query
- [ ] Bench code is not called from `execute_block`
