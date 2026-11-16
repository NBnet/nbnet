# Working on nbnet

nbnet is an EVM chain on Hotmint (HotStuff-2). Consensus, networking, and
the WAL live in the `hotmint` crates. This repository is the application:
Ethereum transaction checks, the revm executor, vsdb world state, the
nonce-aware tx pool, precompiles, JSON-RPC, and the `nb` node binary.

A safety bug here is a fork or a halt: two honest nodes compute different
`app_hash` values, a transaction lands at the wrong nonce, or a revert
leaves state behind. Do not re-litigate Hotmint's quorum rules in this
repo. Do check every place nbnet feeds Hotmint an `app_hash`, a payload,
or a validation result.

## AI workflows

This file is the shared agent entrypoint. Reusable workflows live in
`.agents/skills/` and require explicit invocation; ordinary requests do
not implicitly authorize commits:

- `$x-review`: deep regression review of a diff, N commits, a hash/range, or
  `all`. Updates [docs/audit.md](docs/audit.md); does not commit.
- `$x-fix`: resolve the `docs/audit.md` backlog, self-review, and commit.
- `$x-commit`: self-review uncommitted changes, fix, format, bump the patch
  version, and commit.
- `$x-overhaul`: full codebase audit → fix → commit pipeline.

Shared guides live under [docs/ai/](docs/ai/):
`technical-patterns.md` (cataloged EVM-application bug patterns),
`review-core.md` (systematic review methodology),
`false-positive-guide.md` (rules for filtering spurious findings), and
`patterns/` (execution, state, txpool, RPC/node).

## Layout

```
crates/types/        # chain config, genesis, tx decode/recover, receipts
crates/state/        # EvmState, VsdbStateDb, state trie
crates/txpool/       # (sender, nonce) pool, RBF, pending vs queued
crates/execution/    # EvmExecutor: Application + payload builder
crates/precompile/   # 0x0800 balances, 0x0801 staking
crates/rpc/          # eth_* / net_* / web3_* over axum
crates/node/         # `nb` binary, cluster helpers, e2e
```

About 4.4K lines of Rust, including tests. `docs/architecture.md` is the
design history; when it disagrees with the crates, the code wins.

## Build & test

```bash
make fmt          # cargo fmt --all
make lint         # cargo clippy --workspace --all-targets -- -D warnings
make test         # cargo test --workspace
make build        # cargo build --workspace
```

Member crates take `version.workspace = true` from `[workspace.package]`
in the root `Cargo.toml`.

## Conventions

- No `#[allow(...)]`. Clippy warnings are errors.
- No `unsafe`. This workspace has none.
- State that contributes to `app_hash` is ordered: `BTreeMap`,
  `vsdb::MapxOrd` / `MapxOrdRawKey`, or the state trie. A `HashMap` walk
  must not be hashed.
- `std::sync::Mutex` poisoning is recovered with `into_inner` so one
  panicked holder does not halt the node. That recovery is not itself a
  bug. Holding the state mutex across `.await` is.
- `EvmExecutor` and `SharedExecutor` both implement `Application` and must
  stay in lockstep.
- Public RPC or execution behavior changes must update `README.md`,
  `docs/architecture.md` when it describes that behavior, and the matching
  guide under `docs/ai/patterns/`.
- Keep repository documentation, instructions, and commit messages in
  English. Respond to the user in their language.
