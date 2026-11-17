# State Review Patterns

## Files
- `crates/state/src/state.rs` — `EvmState`, `VsdbStateDb`, trie, cache flush
- `crates/types/src/genesis.rs` — `EvmGenesis`, `GenesisAlloc`
- `crates/types/src/config.rs` — `EvmChainConfig`

## Architecture
- `VsdbStateDb` stores accounts, code, storage, and block hashes in
  `MapxOrdRawKey` maps created by `new()`. Account keys are raw address
  bytes. The storage map key is `address || slot`. The trie key for a
  slot is `0x01 || address || slot`. Startup does not reopen these maps.
- `EvmState` wraps a revm `CacheDB` plus an `MptCalc` state trie.
- `from_genesis` inserts each alloc into vsdb and the trie. Alloc is a
  `BTreeMap`.
- `state_root` copies `state_trie.root_hash()` into 32 bytes.
- Account leaves are `nonce(8) || balance(32) || code_hash(32)`, big-endian.

## Critical Invariants

### INV-ST1: Ordered Persistence
**Check**: New maps that hold consensus state are `BTreeMap` or
`MapxOrdRawKey`, not `HashMap`. Encoding is fixed-width and endian-stable.

### INV-ST2: Cache, Vsdb, and Trie Move Together
**Check**: `flush_cache_to_vsdb` writes the account, each dirty storage
slot, and the trie leaf in this process. A new setter (`set_balance`,
`set_nonce`, `insert_storage`) updates the copy execution will read.
`from_genesis` does not load a previous flush.

### INV-ST3: Getters See the Cache First
**Check**: `get_balance`, `get_nonce`, `get_code`, and `get_storage` read
`CacheDB` before vsdb. Otherwise `execute_block` validates a nonce the
in-block previous transaction already changed only in the cache, or the
reverse.

### INV-ST4: Genesis Is Deterministic
**Check**: `test_state_root_determinism` still holds. Two `from_genesis`
calls on the same alloc produce the same root. Empty code does not insert
an empty contract blob.

## Common Bug Patterns

### Flush Skipped (technical-patterns.md 1.2)
`state_root` hashes the trie from before the block.

### Default Root (technical-patterns.md 1.3)
A trie error becomes the all-zero hash for a non-empty state.

## Review Checklist
- [ ] Storage key is still address(20) || slot(32)
- [ ] Block-hash window prune does not delete a hash the trie depends on
- [ ] Config defaults still decode an older genesis file
