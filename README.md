# nbnet

[![License: GPL-3.0](https://img.shields.io/badge/License-GPL--3.0-blue.svg)](LICENSE)
[![Rust](https://img.shields.io/badge/Rust-2024_edition-orange.svg)](https://www.rust-lang.org/)

**An EVM-compatible blockchain built on [Hotmint](https://github.com/rust-util-collections/hotmint) consensus.**

nbnet pairs the [revm](https://github.com/bluealloy/revm) execution engine with Hotmint's HotStuff-2 BFT consensus to deliver a fully Ethereum-compatible chain — with no C/C++ dependencies in the critical path.

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
| `nbnet-precompile` | Custom precompiles bridging EVM to Hotmint staking/balances |
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

The JSON-RPC endpoint is compatible with MetaMask, Foundry, Hardhat, and Web3.js.

## Building

```bash
make build        # build workspace
make test         # run tests
make bench-nbnet  # run throughput benchmark
```

## Dependencies

- [hotmint](https://crates.io/crates/hotmint) — HotStuff-2 BFT consensus engine
- [revm](https://crates.io/crates/revm) — EVM execution
- [vsdb](https://crates.io/crates/vsdb) — pure-Rust versioned key-value storage
- [alloy](https://github.com/alloy-rs/alloy) — Ethereum primitives and transaction types

## License

GPL-3.0-only
