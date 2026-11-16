# Execution and Precompile Review Patterns

## Files
- `crates/execution/src/executor.rs` — `EvmExecutor`, `SharedExecutor`,
  `EvmMempoolAdapter`
- `crates/types/src/tx.rs` — `decode_and_recover`, `validate_tx`,
  `effective_gas_tip`
- `crates/precompile/src/lib.rs` — `HotmintPrecompiles`, `StakingState`

## Architecture
- `EvmExecutor` implements Hotmint `Application`: `validate_tx`,
  `execute_block`, `create_payload`, `on_commit`, `query`.
- `SharedExecutor` is `Arc<EvmExecutor>` with a delegating impl so the
  engine and the RPC server share one executor.
- Each transaction builds a mainnet revm context at `SpecId::CANCUN` with
  `HotmintPrecompiles` and calls `transact_commit`.
- `create_payload` asks the pool for up to 4 MiB and `block_gas_limit`.
- Precompile `0x0800` is balances. `0x0801` is staking. Staking delegation
  records are a `HashMap` inside `SharedStakingState`.

## Critical Invariants

### INV-EX1: Execution Nonce Is Exact
Admission allows a nonce at or above the account nonce. Execution allows
only equality with the nonce at that step.
**Check**: The skip path does not push a receipt and does not call
`transact_commit`.

### INV-EX2: One Commit Path
**Check**: State changes for a transaction come from `transact_commit`.
`Revert` and `Halt` record status 0. `Err` records nothing. The gas-limit
`break` happens before the call.

### INV-EX3: App Hash After Flush
**Check**: `flush_cache_to_vsdb` then `state_root` then
`EndBlockResponse.app_hash`. `on_commit` updates the height and calls
`txpool.on_commit` with `state.get_nonce`.

### INV-EX4: Both Application Impls Match
**Check**: `SharedExecutor` forwards every method. `EvmMempoolAdapter::add_tx`
uses `submit_tx` (decode, validate, insert). `recheck` stays a no-op only
while `on_commit` is what evicts included nonces.

### INV-EX5: Precompile Side Maps Stay Off the Trie
**Check**: No `delegations.iter()` feeds the trie or a hash.
Consensus-visible balances go through revm. Addresses match the constants
in this file, not a stale sentence in `docs/architecture.md`.

## Common Bug Patterns

### Unordered Map (technical-patterns.md 1.1)
Staking `HashMap` iteration is folded into `app_hash`.

### Gas Check Too Late (technical-patterns.md 3.2)
`transact_commit` runs, then the code notices the block is over the limit.

## Review Checklist
- [ ] Chain id, signature, balance, and base fee still rejected in `validate_tx`
- [ ] Coinbase derivation did not start depending on map iteration
- [ ] `BLOCKHASH` placeholder (`B256::ZERO`) was not mixed into the trie leaf
- [ ] Receipt `status` follows Success vs Revert/Halt
