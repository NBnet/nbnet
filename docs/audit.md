# Audit Findings

> Auto-managed by $x-review and $x-fix.

## Open

*(No open findings)*

---

## Won't Fix

### [MEDIUM] rpc: several Ethereum methods are stubs
- **Where**: `crates/rpc/src/lib.rs`
- **What**: `eth_getBlockByHash` is always null, `eth_syncing` is always false, `eth_feeHistory` and `eth_estimateGas` do not report real history or gas used, and receipts live only in process memory.
- **Reason**: This is the JSON-RPC subset the node implements. Filling those methods needs block-hash indexing and durable receipts, which are a separate feature. Documented in `docs/architecture.md`.

### [LOW] execution: BLOCKHASH records a zero parent hash
- **Where**: `EvmExecutor::execute_block`
- **What**: The parent hash passed to state is `B256::ZERO`, so contracts that call `BLOCKHASH` do not see the real parent.
- **Reason**: Every node does the same thing, so `app_hash` still agrees. Supplying the real parent requires the consensus block hash at execution time. Not a fork between honest nodes.

## Resolved — Overhaul (2026-11-16)

### [HIGH] state: storage writes did not change app_hash
- **Where**: `EvmState::flush_cache_to_vsdb`, `from_genesis`
- **Resolution**: Each storage slot is inserted into the state trie under `0x01 || address || slot`. Account keys stay 20 bytes, so the two namespaces do not collide.

### [MEDIUM] rpc: receipts were indexed by push order, not block height
- **Where**: `EvmExecutor` receipt list, `eth_getLogs`, `eth_getBlockByNumber`
- **Resolution**: Receipts are a `BTreeMap` keyed by block height.

---
