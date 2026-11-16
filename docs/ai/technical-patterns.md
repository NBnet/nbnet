# nbnet Technical Bug Patterns

Catalog of bug categories in this EVM application. Load it before a review
or a fix. Consensus-protocol bugs in the `hotmint` dependency are out of
scope unless nbnet feeds them bad bytes.

---

## Category 1: App-Hash Determinism

### 1.1 Unordered Map Hashed Into State

**Pattern**: Account, storage, or genesis data is walked from a `HashMap`
into the trie, the leaf encoder, or any digest returned as `app_hash`.
**Where**: `EvmState::state_root`, `flush_cache_to_vsdb`,
`EvmState::from_genesis`, `encode_account_leaf`.
**Impact**: Two nodes commit different hashes for the same block and
Hotmint halts or forks.
**Check**: Genesis alloc is a `BTreeMap`. Persistent maps are
`MapxOrdRawKey`. Leaf bytes are big-endian nonce, balance, and code hash,
in that order. `HashMap` in `StakingState` is not part of the trie.

### 1.2 Trie Updated Before or Without the Cache Flush

**Pattern**: `state_root` runs before `flush_cache_to_vsdb`, or a write
path updates only the cache or only vsdb.
**Where**: `EvmExecutor::execute_block`, `EvmState::flush_cache_to_vsdb`.
**Impact**: `app_hash` misses the block, or a restart loads balances the
last hash did not commit.
**Check**: Flush walks cached accounts into vsdb and the trie, then
`state_root` reads `state_trie.root_hash()`. Genesis inserts both.

### 1.3 Default Root Treated as Real

**Pattern**: `root_hash()` failing becomes `[0u8; 32]` and is still
returned as a successful `app_hash` for a non-empty trie.
**Where**: `EvmState::state_root`.
**Impact**: An empty hash is committed for a state that is not empty.
**Check**: `unwrap_or_default` is only acceptable when the trie is
genuinely empty. A non-empty failure must not look like a valid root.

---

## Category 2: Nonce and Admission

### 2.1 Nonce Below Account Accepted

**Pattern**: `validate_tx` uses `>` instead of `<`, or the executor does
not re-check nonce against the state at execution time.
**Where**: `nbnet_types::tx::validate_tx`, `EvmExecutor::validate_tx`,
`EvmExecutor::execute_block`.
**Impact**: A replayed transaction runs again, or a future nonce runs
early and shifts every later nonce.
**Check**: Admission rejects `tx_nonce < account_nonce`. Execution skips
unless `tx_nonce == expected_nonce` at that position in the block.

### 2.2 Gapped Nonce Packed

**Pattern**: The pool inserts any `tx_nonce > current` straight into
`pending`, or `collect_payload` reads `queued`.
**Where**: `EvmTxPool` insert and `collect_payload`.
**Impact**: A block contains a hole. Execution skips it, the sender's
later transactions stall, or a hole is executed.
**Check**: Pending means contiguous from the account nonce. Queued holds
the rest. Promotion runs after insert and inside `on_commit`.

### 2.3 RBF Replaces a Better Transaction

**Pattern**: Same `(sender, nonce)` is replaced by a lower tip, or the
old transaction stays beside the new one.
**Where**: `EvmTxPool` replace logic.
**Impact**: The payer's replacement is ignored, or both are packed and
the second fails the nonce check after the first succeeded.
**Check**: Replacement requires a strictly higher tip. One slot per
`(sender, nonce)`.

---

## Category 3: Execution Atomicity

### 3.1 Revert or Halt Leaves Storage Writes

**Pattern**: State is written before `transact_commit` returns, or a
`Revert` / `Halt` arm still applies a balance or storage delta by hand.
**Where**: `EvmExecutor::execute_block`.
**Impact**: A failed call still moves value. The next node's revm journal
disagrees.
**Check**: The only commit path is `transact_commit`. On `Err`, there is
no receipt and no extra write. On `Revert` or `Halt`, status is 0 and
the call's writes are not applied on top of the journal.

### 3.2 Gas Check After the Transaction Ran

**Pattern**: `cumulative_gas_used + tx_gas > block_gas_limit` is tested
after `transact_commit`.
**Where**: the gas check in `execute_block`.
**Impact**: A transaction that does not fit still changes state, then the
loop `break`s.
**Check**: The check uses `saturating_add` and `break`s before
`transact_commit`.

### 3.3 SharedExecutor Drifts

**Pattern**: A new `Application` method is implemented on `EvmExecutor`
and not delegated by `SharedExecutor`, or the reverse.
**Where**: `crates/execution/src/executor.rs`.
**Impact**: The node binary and the RPC server observe different
execution.
**Check**: Every `SharedExecutor` method calls the same method on the
inner `EvmExecutor`.

---

## Category 4: Precompiles

### 4.1 Staking HashMap Becomes Consensus State

**Pattern**: `StakingState.delegations` is iterated into a hash, a
receipt, or the trie.
**Where**: `crates/precompile/src/lib.rs`.
**Impact**: Iteration order differs per process, so `app_hash` forks.
Restart drops delegations that the hash committed.
**Check**: Delegation totals stay off the trie unless they move into an
ordered structure that is flushed with the rest of the state. Addresses
stay `0x0800` (balances) and `0x0801` (staking).

### 4.2 Precompile Debits a Balance the Trie Does Not See

**Pattern**: A write selector subtracts `U256` in `StakingState` or a
side map and does not go through the revm journal.
**Where**: precompile call handler.
**Impact**: RPC balance and `app_hash` disagree with the staking total.
**Check**: Consensus-visible token movement is an account balance or
storage slot in `EvmState`.

---

## Category 5: RPC and Node Wiring

### 5.1 RPC Answers From a Different State Than Execution

**Pattern**: A handler keeps its own balance map, or reads the trie while
`execute_block` is defined to answer from the cache first.
**Where**: `crates/rpc`, `EvmExecutor::query`.
**Impact**: `eth_getBalance` does not match the next block's pre-state.
**Check**: Balance, nonce, code, and storage reads use `EvmState` getters.
Transaction lookup uses the receipt the executor stored.

### 5.2 Gossip Validation Skips `validate_tx`

**Pattern**: The node inserts gossip bytes into the pool without
`Application::validate_tx`.
**Where**: `crates/node/src/main.rs`.
**Impact**: A transaction the block executor would skip occupies payload
space, or a wrong-chain-id transaction is packed.
**Check**: Both the RPC submit path and the gossip path decode and
validate before the pool accepts the bytes.

---

## Category 6: Concurrency

### 6.1 State Mutex Held Across `.await`

**Pattern**: `self.state.lock()` (or the pool lock, or a `parking_lot`
guard in the node) is live when the function awaits.
**Where**: executor, RPC handlers, node tasks.
**Impact**: The consensus task and the RPC task deadlock.
**Check**: Guards are dropped before any `.await`. Poison recovery via
`into_inner` stays local to the lock statement.
