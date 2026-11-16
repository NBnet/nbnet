# nbnet Review Core Methodology

This document defines the systematic review protocol for nbnet changes.

---

## Phase 1: Context Gathering

Before analyzing any change, gather context:

1. **Read the diff.**
2. **Identify affected subsystems**:
   - `crates/types/` → tx decode, validation, genesis, receipts
   - `crates/state/` → vsdb world state and the state trie
   - `crates/execution/` → `Application` impl, payload builder
   - `crates/precompile/` → `0x0800` balances, `0x0801` staking
   - `crates/txpool/` → nonce pool
   - `crates/rpc/` → JSON-RPC
   - `crates/node/` → binary wiring, cluster, e2e
3. **Load** the matching file under `docs/ai/patterns/`.
4. **Check both `Application` impls** when execution changes:
   `EvmExecutor` and `SharedExecutor`.
5. **Leave hotmint's consensus crate alone** unless the diff changes how
   nbnet calls it.

## Phase 2: Change Classification

| Category | Description | Risk Level |
|----------|-------------|------------|
| App hash | Trie update, encoding, map ordering | CRITICAL |
| Execution | `execute_block`, revert, gas, nonce | CRITICAL |
| Validation | chain id, signature recover, balance, nonce | CRITICAL |
| Tx pool | pending/queued, RBF, `on_commit` | HIGH |
| Precompile | balances or staking side effects | HIGH |
| Persistence | `flush_cache_to_vsdb`, genesis insert | HIGH |
| RPC | answers that disagree with executor state | HIGH |
| Concurrency | state mutex, pool lock, `.await` | HIGH |
| Node wiring | gossip validate, payload, shutdown | MEDIUM |
| Documentation | README or architecture drift | LOW |
| Tests | unit or e2e | LOW |

## Phase 3: Regression Analysis

For each HIGH or CRITICAL change:

### 3.1 Invariant Check

**Determinism.** `app_hash` is `EvmState::state_root()`, the trie root.
Account leaves are `nonce(8) || balance(32) || code_hash(32)`. Genesis
allocation is a `BTreeMap`. Storage keys are address || slot. A `HashMap`
or `HashSet` must not be iterated into the trie or into any bytes that
are hashed for consensus.

**Nonce.** `validate_tx` rejects `tx.nonce < account_nonce`. The pool
places `tx.nonce == current` or `current`'s immediate successor-chain into
`pending`, and everything further into `queued`. `execute_block` skips a
transaction whose nonce is not exactly the account nonce at that moment.
`on_commit` drops nonces below the post-block account nonce and promotes
queued transactions that are now contiguous.

**Execution.** Transactions in a block are executed in order. A decode
failure or nonce mismatch skips that transaction with no state write and
no success receipt. A transaction that would exceed `block_gas_limit` stops
the block before it runs. `transact_commit` is the only state transition.
A revert or halt must not leave that call's storage writes behind.
Receipts record status, gas, and logs from the execution result. The
in-memory receipt list is not the trie.

**Flush.** `flush_cache_to_vsdb` runs after the block's transactions and
before `state_root`, so the trie sees the cache. Genesis inserts go to
vsdb and the trie together.

**Precompiles.** `0x0800` is balances and `0x0801` is staking
(`BALANCES_ADDR`, `STAKING_ADDR`). Staking amounts live in a `HashMap`
behind `SharedStakingState`, not in the trie. A consensus-visible balance
change has to go through the revm journal / account trie. Do not hash the
`HashMap`.

**RPC.** A success result for a transaction, balance, nonce, code, or
storage slot must come from executor or state data. Do not synthesize a
receipt the executor did not record.

**Locks.** The state `Mutex` is held for validation, execution, and
queries. It must not be held across `.await`. Pool structures are updated
under their own lock. `parking_lot` in the node crate follows the same
rule.

### 3.2 Boundary Conditions

- Empty block. First block (height 0). Single genesis account.
- Nonce 0, nonce equal to account, nonce one ahead, nonce far ahead,
  nonce below account.
- Same `(sender, nonce)` with a higher tip (RBF) and with a lower tip.
- Value plus gas cost above balance. Wrong chain id. Bad signature.
- Contract create (`to` is `None`) and call. Revert and halt.
- Block gas exactly equal to the next transaction, and one over.
- Two nodes applying the same genesis: `state_root` matches
  (`test_state_root_determinism`).
- Restart: trie accounts survive; in-memory receipts and staking
  delegations do not. A change that needs them after restart must persist
  them in order.

### 3.3 Failure Paths

- `decode_and_recover` fails inside a block: skip, continue.
- `transact_commit` returns `Err`: no receipt, no partial journal.
- Pool `on_commit` runs even when the block contained only skipped
  transactions, using the nonce function from committed state.
- RPC method unknown or short input: empty or error, not another account's
  data.

### 3.4 Concurrency

`validate_tx` and the gossip path can run while `execute_block` wants the
state mutex. That serialization is intentional. Report a new `.await` under
the state guard, a pool update outside its lock, or `SharedExecutor` and
`EvmExecutor` disagreeing on a method.

## Phase 4: Cross-Cutting Concerns

### 4.1 Crash Window

`kill -9` after `transact_commit` and before `flush_cache_to_vsdb` can
leave the cache ahead of vsdb. A change to that order must say which copy
wins on restart. The Hotmint WAL is outside this repo; do not claim nbnet
fsyncs consensus votes.

### 4.2 Determinism and Performance

Hashing or sorting on the execution path is a finding when it can change
`app_hash` or when it walks a `HashMap`. An extra clone on an RPC query
is not, unless it sits in `execute_block`.

### 4.3 API Contract

JSON-RPC method names and the `Application` methods are the contract.
`SharedExecutor` must delegate every method it implements. New config
fields need defaults so old `evm-genesis.json` files still decode.

### 4.4 Code Style

Violations are LOW:
- No `#[allow(...)]`.
- No new `unsafe`.
- Doc-code alignment: `AGENTS.md`, `README.md`, `docs/architecture.md`,
  `docs/ai/review-core.md`, `.agents/skills/x-review/SKILL.md`, and
  `docs/ai/patterns/`. Precompile addresses in the architecture doc must
  match `BALANCES_ADDR` (`0x0800`) and `STAKING_ADDR` (`0x0801`).

## Phase 5: Reporting

```
[SEVERITY] subsystem: one-line summary

WHERE: file:line_range
WHAT: Description of the issue
WHY: Invariant or pattern from technical-patterns.md
FIX: Suggested fix, or the question that blocks one
```

- **CRITICAL**: nondeterministic `app_hash`, reverted write persisted,
  nonce executed out of order, signature not recovered
- **HIGH**: pool packs a gapped nonce, flush skipped, RPC lies, lock
  across `.await`
- **MEDIUM**: receipt or log field wrong, error path skips `on_commit`
- **LOW**: docs, clarity
- **INFO**: observation, not a bug

Only report findings with concrete evidence. Consult
[false-positive-guide.md](false-positive-guide.md) before finalizing.
