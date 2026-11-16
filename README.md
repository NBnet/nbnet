# nbnet

[![License: GPL-3.0](https://img.shields.io/badge/License-GPL--3.0-blue.svg)](LICENSE)
[![Rust](https://img.shields.io/badge/Rust-2024_edition-orange.svg)](https://www.rust-lang.org/)

**EVM block execution on [Hotmint](https://github.com/NBnet/hotmint) consensus.**

nbnet runs [revm](https://github.com/bluealloy/revm) as a Hotmint `Application` and serves a subset of Ethereum JSON-RPC. It is not a full Ethereum client. The consensus state machine, P2P, and WAL stay in Hotmint. See [docs/architecture.md](docs/architecture.md) for what the RPC and precompiles actually do.

---

## Architecture

```
                     ┌─────────────────────┐
                     │   JSON-RPC (8545)   │
                     │  eth_* web3_* net_* │
                     └──────────┬──────────┘
                                │
                     ┌──────────▼──────────┐
                     │    EvmExecutor      │
                     │ (Application trait) │
                     └──┬────┬────┬────────┘
                        │    │    │
              ┌─────────┘    │    └──────────┐
              │              │               │
        ┌─────▼─────┐  ┌─────▼─────┐  ┌─────▼──────┐
        │  TxPool   │  │   State   │  │ Precompiles │
        │ (mempool) │  │  (vsdb)   │  │  staking/   │
        └───────────┘  └─────┬─────┘  │  balances   │
                             │        └─────────────┘
                       ┌─────▼─────┐
                       │   revm    │
                       └───────────┘

    ┌────────────────────────────────────────┐
    │     Hotmint (HotStuff-2 consensus)     │
    └────────────────────────────────────────┘
```

## Crates

| Crate | Description |
|:------|:------------|
| `nbnet-types` | EVM type definitions: `EvmChainConfig`, transactions, receipts |
| `nbnet-state` | vsdb-backed EVM world state (`revm::Database` impl) |
| `nbnet-txpool` | Ethereum mempool with `(sender, nonce)` semantics and RBF |
| `nbnet-precompile` | `0x0800` balances and `0x0801` staking lock. The delegation map is in-process, not `hotmint-staking` |
| `nbnet-execution` | `EvmExecutor` implementing the Hotmint `Application` trait |
| `nbnet-rpc` | Ethereum JSON-RPC server (axum-based) |
| `nbnet-node` | Node binary `nb` and benchmark binary `bench-nbnet` |

## Quick Start

```bash
# Initialize node
nb init --home ~/.nbnet

# Start node
nb node --home ~/.nbnet

# Start node with custom RPC address
nb node --home ~/.nbnet --rpc-addr 0.0.0.0:8545
```

The RPC server speaks the methods listed in [docs/architecture.md](docs/architecture.md). Basic MetaMask and Foundry calls work against that subset. Block-by-hash, fee history, sync status, and receipt persistence do not match a full Ethereum node.

## Building

```bash
make build        # build workspace
make test         # run tests
make bench-nbnet  # run throughput benchmark
```

## Dependencies

- [hotmint](https://crates.io/crates/hotmint) — HotStuff-2 BFT consensus engine
- [vsdb](https://crates.io/crates/vsdb) — pure-Rust versioned key-value storage
- [alloy](https://github.com/alloy-rs/alloy) — Ethereum primitives and transaction types
- [revm](https://crates.io/crates/revm) — EVM execution

## License

GPL-3.0-only
