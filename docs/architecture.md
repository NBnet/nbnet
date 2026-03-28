# nbnet Architecture

> Extracted from the [Hotmint](https://github.com/NBnet/hotmint) security audit & roadmap.
> Covers the EVM-specific design decisions, component mapping, and production gap analysis.

---

## 1. Technology Stack Evaluation: Substrate (Frontier/SputnikVM) vs Reth (revm/alloy)

| Evaluation Dimension | Substrate Ecosystem (Frontier/SputnikVM) | Reth Ecosystem (revm/alloy) | Conclusion |
|----------------------|-------------------------------------|----------------------|------|
| Design Era | 2019–2020, bound to `no_std` + Wasm constraints | 2022–present, native `std` environment, modern API | 🏆 Reth |
| Execution Performance | Moderate (memory allocation bottleneck) | Industry benchmark (Paradigm/OP Stack/Arbitrum have all migrated to revm) | 🏆 Reth |
| Underlying Types | `sp-core` / `primitive-types` + SCALE encoding | `alloy-primitives` (high-performance U256/Address) + `alloy-rlp` | 🏆 Reth |
| Substrate Component Compatibility | Very high (Precompile natively interoperates with pallet-balances, etc.) | Low (requires custom bridging) | 🏆 Substrate |
| AI Porting Difficulty | High (must strip `#[pallet]` macros + Wasm boundary) | Very low (pure Rust library, implement `Database` trait with ~4 methods to integrate with vsdb) | 🏆 Reth |

**Conclusion: Hybrid Approach** — EVM execution layer embraces the Reth ecosystem (revm + alloy), while the native economic system and governance model retain AI-ported Substrate Pallets. The two are bridged through Custom Precompiles.

---

## 2. Architecture Component Mapping

| Substrate / Frontier Component | nbnet Target Architecture | Core Responsibility |
|:---|:---|:---|
| `pallet-timestamp` | `nbnet::Timestamp` | Provides current block time for the EVM `block.timestamp` opcode |
| `pallet-balances` | `nbnet::Balances` | Manages native token, handles Gas deduction and native transfers (AI-ported from Substrate) |
| `pallet-evm` (SputnikVM) | ~~Not used~~ → `revm` crate | Direct revm integration, implement `revm::Database` trait for vsdb |
| `pallet-ethereum` | `alloy-rlp` + `alloy-primitives` | Ethereum RLP transaction decoding (EIP-1559/EIP-2930), `ecrecover` signature recovery |
| `fc-rpc` (Frontier RPC) | `nbnet-rpc` (axum) | Standard `eth_*` JSON-RPC interface, MetaMask-compatible |
| Substrate Storage Trie | `vsdb::MapxOrd` & `Mapx` | Account Nonce/Balance, EVM Code (contract bytecode), EVM Storage (contract state) |
| `pallet-staking` | `nbnet::Staking` (AI-ported) | DPoS staking/validator election/slashing (native layer, exposed to EVM via Precompile) |

---

## 3. Implementation Roadmap (5 Phases)

**Phase 1: Underlying Native Economic System (AI-Ported from Substrate)** ✅
- ~~Use AI to port `pallet-balances` to vsdb~~ → `nbnet-state` (`EvmState`): vsdb-backed account balance, nonce, code, storage
- ~~Introduce `U256` safe arithmetic~~ → via `alloy-primitives::U256`
- ~~Build EVM world state structure~~ → `EvmState` with vsdb `CacheDB` adapter for revm
- ~~Implement `Timestamp` and `BlockContext`~~ → `BlockContext` carries height, gas_limit, coinbase, timestamp

**Phase 2: Introduce Reth Core Primitives (Alloy)** ✅
- ~~Introduce `alloy-primitives`, `alloy-rlp`~~ → `nbnet-types` crate
- ~~`validate_tx`: RLP decode → ecrecover → ChainID → Nonce → Balance~~ → `tx::decode_and_recover()` + `tx::validate_tx()`
- ~~Cryptography~~ → `k256` crate for secp256k1 ECDSA recovery

**Phase 3: Integrate the Leading Execution Engine (Revm)** ✅
- ~~Implement `revm::Database` trait for vsdb~~ → `EvmState` provides `CacheDB` for revm
- ~~`execute_block`: revm → batch-write~~ → `EvmExecutor::execute_block()` in `nbnet-execution`
- ~~Gas settlement~~ → max fee deducted pre-execution, refund after, proposer reward
- ~~Events and logs~~ → `EvmReceipt` with logs persisted per block
- ~~app_hash determinism~~ → `BTreeMap` + vsdb `MapxOrd` for state root

**Phase 4: Cross-Layer Bridging (Precompile Interoperability)** ✅
- ~~Implement `revm::Precompile` interface~~ → `nbnet-precompile` crate
- ~~Address `0x0800` → Staking module~~ → `SharedStakingState` bridging EVM to `hotmint-staking`

**Phase 5: Expose Web3 API (Alloy/Reth RPC)** ✅
- ~~Build HTTP server~~ → `nbnet-rpc` (axum-based)
- ~~Standard Ethereum APIs~~ → `eth_chainId`, `eth_blockNumber`, `eth_getBalance`, `eth_getTransactionCount`, `eth_getCode`, `eth_getStorageAt`, `eth_gasPrice`, `eth_estimateGas`, `eth_sendRawTransaction`, `eth_getBlockByNumber`, `eth_feeHistory`, `eth_syncing`, `net_version`, `web3_clientVersion`
- ~~Compatible with MetaMask, Hardhat, Foundry~~ → basic compatibility achieved

---

## 4. Key Risks and Pitfalls

1. **State Reversion Consistency:** When an EVM transaction reverts or runs out of Gas, state changes must be rolled back while preserving Gas deduction. Approach: create a transient snapshot via vsdb Write Batch before each transaction; discard on failure, commit on success.
2. **Mempool RBF and Ethereum Nonce Conflicts:** Ethereum nonces are strictly incrementing; `validate_tx` must verify `nonce >= account_nonce`, and the mempool needs `(sender, nonce)` deduplication and RBF replacement logic.
3. **App Hash Determinism:** `HashMap` traversal is unordered, which causes `app_hash` inconsistency between nodes, leading to chain fork and halt. Strictly use `BTreeMap` / `vsdb::MapxOrd` with ordered traversal.

---

## 5. Production Gap Analysis (v0.8 baseline)

> All identified production gaps have been resolved. nbnet has feature parity with the standard hotmint-node for consensus infrastructure, and implements all essential Ethereum JSON-RPC methods.

### 5.1 Completed Features

| Feature | Implementation | Crate |
|:--------|:--------------|:------|
| EVM execution via revm | `EvmExecutor` implements `Application` trait | `nbnet-execution` |
| EIP-1559 transaction pool | `EvmTxPool` with sender/nonce ordering, RBF, tip priority | `nbnet-txpool` |
| Pluggable mempool | `MempoolAdapter` trait, `EvmMempoolAdapter` wraps `EvmTxPool` | `hotmint-mempool`, `nbnet-execution` |
| Transaction gossip | `NetworkSink::broadcast_tx()` on RPC submit + gossip receive loop | `hotmint-consensus`, `nbnet-rpc`, `nbnet-node` |
| Nonce-fn wiring | `EvmExecutor::setup_nonce_fn()` connects txpool to committed state | `nbnet-execution` |
| Ethereum JSON-RPC | 22 methods (eth_*, net_*, web3_*) via axum | `nbnet-rpc` |
| Staking precompile | `0x0800` → `hotmint-staking` via `SharedStakingState` | `nbnet-precompile` |
| Cluster management | `init_evm_cluster()`, `start_evm_nodes()`, `kill_stale_nodes()` | `nbnet-node`, `hotmint-mgmt` |
| TPS benchmark | Nonce-confirmed on-chain throughput measurement | `nbnet-node` (`bench-nbnet`) |
| State persistence | vsdb-backed EVM state with MPT state root | `nbnet-state` |

### 5.2 Node Infrastructure — All Resolved

| # | Gap | Resolution |
|---|:----|:-----------|
| E-1 | Fullnode mode | Nodes not in genesis auto-detect as fullnode (`ValidatorId(u64::MAX)` sentinel) |
| E-2 | Block sync on startup | `sync_to_tip()` runs from peers before consensus starts |
| E-3 | Sync responder | Returns real height/view/epoch via `ConsensusStatus` watch channel |
| E-4 | `init` subcommand | `nb init --home ...` generates keys + config + evm-genesis.json |
| E-5 | Graceful shutdown | `tokio::select!` supervisor with ctrl_c + SIGTERM handlers |
| E-6 | WAL | `ConsensusWal::open()` for crash-safe commit recovery |
| E-7 | Evidence store | `PersistentEvidenceStore::open()` for equivocation proof persistence |
| E-8 | CLI overrides | `--rpc-addr`, `--p2p-laddr` override config.toml values |
| E-9 | Config respect | `serve_rpc`, `serve_sync` flags control server startup |

### 5.3 Ethereum JSON-RPC — All Resolved

| # | Method | Implementation |
|---|:-------|:---------------|
| R-1 | `eth_call` | Dry-run EVM execution via `EvmExecutor::eth_call()` (read-only `transact_one`) |
| R-2 | `eth_getTransactionReceipt` | Full receipt: status, gasUsed, logs, effectiveGasPrice, contractAddress |
| R-3 | `eth_getTransactionByHash` | Tx lookup from receipt data (hash, from, to, blockNumber) |
| R-4 | `eth_getLogs` | Filter logs by address and topic across all blocks |
| R-5 | `eth_getBlockByNumber` | Block with real height and transaction count |
| R-6 | `eth_estimateGas` | Dry-run execution via `eth_call` for gas estimation |
