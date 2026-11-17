# nbnet False Positive Guide

Before reporting any finding, check it against this guide.

---

## FP-1: Hotmint Consensus Internals

**Pattern**: Reporting a quorum, pacemaker, or vote-collector bug and
citing nbnet because it depends on `hotmint`.
**Rule**: Those invariants belong to the hotmint review. Report an nbnet
finding only where this repo builds the `app_hash`, selects transactions,
validates them, or answers RPC from local state.

## FP-2: Rust Ownership Already Prevents It

**Pattern**: Reporting memory unsafety in safe Rust.
**Rule**: This workspace has no `unsafe`. Report memory unsafety only for
a newly added `unsafe` block, and require a `SAFETY` comment.

## FP-3: Mutex Poison Recovery

**Pattern**: Reporting `unwrap_or_else(|e| e.into_inner())` on
`std::sync::Mutex`.
**Rule**: A poisoned state or receipt lock must not halt block execution.
Report it only when the recovery skips a write the caller still treats as
done, or when the guard is held across `.await`.

## FP-4: Invalid Transactions Skipped Inside a Block

**Pattern**: Reporting that `execute_block` `continue`s on a decode error
or a nonce mismatch.
**Rule**: A bad transaction must not abort the whole block or change state.
Report it only if the skip still leaves a partial write, if a mismatched
nonce is executed, or if a skipped transaction is given a success receipt.

## FP-5: Queued Transactions Are Not Pending

**Pattern**: Reporting that a transaction with a nonce gap is not packed.
**Rule**: The pool keeps gapped nonces in `queued` until the predecessor
exists. Report it only if a gapped nonce is packed, or if filling the gap
does not promote the successor.

## FP-6: In-Memory Receipts and Staking Map

**Pattern**: Reporting that receipts or `StakingState` disappear on process
restart.
**Rule**: Receipts live in a `Mutex<BTreeMap<u64, Vec<EvmReceipt>>>` keyed
by height. Staking delegations live in a `HashMap` on `SharedStakingState`.
Neither is the trie. Startup also rebuilds account maps and the trie from
genesis, so "state did not reload" matches the current node. Report a
restart loss when a change starts treating receipts or the staking map as
the source of `app_hash`, or when it claims the previous trie is restored.
Report a `HashMap` if its iteration order is hashed.

## FP-7: Zero Parent Hash Is the Current BLOCKHASH Placeholder

**Pattern**: Reporting that `record_block_hash` is called with `B256::ZERO`.
**Rule**: That placeholder is already the behavior. File a finding only
when a change claims `BLOCKHASH` returns the real parent, or when the zero
hash is mixed into `app_hash`.

## FP-8: Unwrap on Known-Valid State

**Pattern**: Reporting `unwrap()` as a panic.
**Rule**: Check for a concrete production input. Test code may unwrap.
`state_root` uses `unwrap_or_default` on a missing trie root; report that
only if the default becomes a successful root for a non-empty trie.

## FP-9: Clippy `-D warnings` Would Catch It

**Pattern**: Reporting lint-level issues.
**Rule**: `make lint` is `cargo clippy --workspace --all-targets -- -D warnings`.
Focus on semantic bugs.

## FP-10: "Consider" Without a Concrete Downside

**Pattern**: Advisory suggestions with no trigger.
**Rule**: Every finding needs a concrete transaction, block, or RPC call
and a concrete outcome (different `app_hash`, nonce stuck, reverted write
persisted, RPC reports a tx the node did not execute).

## FP-11: Test and Bench Code

**Pattern**: Holding `crates/node/src/bench.rs`, e2e tests, or unit tests
to production RPC completeness.
**Rule**: Report test code only when the assertion is wrong or the e2e
locks in a dangerous default (wrong chain id, skipped nonce check).

## FP-12: Gas Limit Break Stops the Block

**Pattern**: Reporting that `execute_block` `break`s when the next
transaction does not fit in `block_gas_limit`.
**Rule**: Later transactions in that block are not executed. Report it
only if the break happens after a partial commit of the transaction that
did not fit, or if earlier successful transactions are rolled back too.
