# Tx Pool Review Patterns

## Files
- `crates/txpool/src/lib.rs` — `EvmTxPool`, `SenderQueue`, `on_commit`,
  `collect_payload`

## Architecture
- One `SenderQueue` per sender address.
- `pending` is a nonce-ordered map of transactions contiguous from the
  account nonce. `queued` holds the rest.
- The account nonce comes from `nonce_fn`, installed by
  `EvmExecutor::setup_nonce_fn` and passed again to `on_commit`.
- Replacement is per `(sender, nonce)` and requires a tip at least
  `replacement_bump_pct` above the current one (default 10).
- `collect_payload` takes the lowest pending nonce of each sender, then
  applies the byte cap and the gas cap. Included transactions are removed
  before the function returns.

## Critical Invariants

### INV-TP1: Contiguous Pending
**Check**: Insert into `pending` only when `tx_nonce == current_nonce` or
`pending` already holds `tx_nonce - 1`. Otherwise the transaction goes to
`queued`. `promote_queued_static` moves the contiguous prefix after an
insert and after commit.

### INV-TP2: Commit Evicts Below the New Nonce
**Check**: `on_commit` removes pending and queued entries with
`nonce < nonce_fn(sender)` and then promotes. It does not remove a future
nonce the block did not include.

### INV-TP3: Payload Is Pending Only
**Check**: `collect_payload` iterates `pending`. Caps are the configured
max bytes (the executor passes 4 MiB) and the block gas limit. A
transaction that does not fit is not included and is not dropped from the
pool.

### INV-TP4: One Transaction Per Slot
**Check**: A tip below `existing * (100 + bump) / 100` does not replace.
A tip that clears that bar removes the previous bytes. The default bump
is 10.

## Common Bug Patterns

### Gapped Nonce Packed (technical-patterns.md 2.2)
`collect_payload` starts reading `queued`.

### RBF Keeps Both (technical-patterns.md 2.3)
`insert` does not overwrite the existing nonce key.

## Review Checklist
- [ ] Missing `nonce_fn` does not treat every nonce as 0 in a way that
      packs a gapped transaction after genesis nonce has moved
- [ ] `submit_tx` still decodes and validates before insert
- [ ] Tests cover gap promotion and same-nonce replacement
