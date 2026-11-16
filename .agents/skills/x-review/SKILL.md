---
name: x-review
description: Review an nbnet diff, commit range, or the full codebase for app-hash determinism, nonce handling, execution atomicity, and RPC consistency, updating docs/audit.md only. Use only when the user explicitly invokes $x-review, or as the review phase of $x-overhaul.
---

# nbnet Deep Regression Review

Resolve repository paths from the Git root; Markdown links are relative to
this file. Read invocation arguments from the user prompt.

High-signal review. Code is read-only; `docs/audit.md` is the only write
allowed. A standalone review ends with findings and registry changes; it
does not commit, push, or deploy, and does not authorize code repairs.
Use [x-fix](../x-fix/SKILL.md) to resolve recorded findings,
[x-commit](../x-commit/SKILL.md) for self-reviewing commits, and
[x-overhaul](../x-overhaul/SKILL.md) for the full review-fix-commit pipeline.

Consensus quorum, pacemaker, and vote rules belong to the hotmint
repository. Review them here only where nbnet chooses the bytes it hands
to Hotmint.

## Setup

Read first:
[technical-patterns.md](../../../docs/ai/technical-patterns.md),
[review-core.md](../../../docs/ai/review-core.md), and
[false-positive-guide.md](../../../docs/ai/false-positive-guide.md).
For each affected subsystem, map changed files to the table below and read
the matching guide under [patterns/](../../../docs/ai/patterns/).

| Path | Subsystem | Guide |
|------|-----------|-------|
| `crates/execution/`, `crates/precompile/`, `crates/types/src/tx.rs` | execution | `execution.md` |
| `crates/state/`, `crates/types/src/genesis.rs`, `crates/types/src/config.rs` | state | `state.md` |
| `crates/txpool/` | tx pool | `txpool.md` |
| `crates/rpc/`, `crates/node/` | RPC and node | `rpc.md` |

## Input

Accept at most one review scope supplied in the user's request:

| Input | Scope | How |
|-------|-------|-----|
| *(empty)* | Latest commit | `git diff HEAD~1`, `git log -1` |
| `N` (integer) | Last N commits | `git diff HEAD~N`, `git log -N --oneline` |
| `all` | Full codebase audit | Full Audit Protocol below |
| `<commit hash>` | Specific commit | `git diff <hash>~1 <hash>` |
| `<hash1>..<hash2>` | Commit range | `git diff <hash1> <hash2>` |

For diff-based scopes, proceed to the Execution Protocol. For `all`, use the
Full Audit Protocol. Reject anything else; never guess a scope.

## Execution Protocol

### 1. Context & Classification

1. Record a worktree baseline (`git status --short`, `git rev-parse HEAD`).
2. Read the full diff; identify ALL affected subsystems via the table above.
3. Read the corresponding pattern guide for each affected subsystem.
4. Classify each change per the review-core methodology (app hash,
   execution, validation, pool, precompile, persistence, RPC, locks).

### 2. Deep Regression Analysis

For each HIGH or CRITICAL classified change:

- Read at least 50 lines of surrounding context.
- Trace callers of a changed `Application` method, pool operation, or
  state getter.
- Check determinism, nonce equality at execution, revert atomicity, and
  flush-before-root.
- Boundary conditions: empty block, nonce gap, same-nonce RBF, wrong
  chain id, revert, block gas one over the limit, two nodes with the
  same genesis.
- Failure paths: decode error inside a block, `transact_commit` `Err`,
  RPC params shorter than the address.

Cross-reference every candidate with `technical-patterns.md` and try to
refute it with `false-positive-guide.md`; keep only concrete evidence.

### 3. Cross-Cutting Analysis

- Crash window: between `transact_commit` and `flush_cache_to_vsdb`.
  Do not claim this repo fsyncs Hotmint votes.
- Both `Application` impls: `EvmExecutor` and `SharedExecutor`.
- API compatibility: RPC method names, genesis serde defaults, payload
  caps.

### 4. Code Style Enforcement

- No lint suppression (`#[allow(...)]` is forbidden). `make lint` uses
  `-D warnings`.
- No new `unsafe`. The workspace has none.
- Doc-code alignment: `AGENTS.md`, `README.md`, `docs/architecture.md`,
  `docs/ai/review-core.md`, this skill's full-audit table, and
  `docs/ai/patterns/`. Precompile addresses in the architecture doc must
  match the constants (`0x0800` balances, `0x0801` staking). The code wins
  when they disagree; report the drift when a change touches either side.

### 5. Unsafe Code Audit

There is no `unsafe` in this workspace. A new `unsafe` block is a finding
until it has a `SAFETY` comment and a reason that safe Rust cannot express.

### 6. Audit Registry (docs/audit.md)

1. Read `docs/audit.md` (create if absent).
2. **Prune**: verify each `## Open` entry against the current codebase;
   remove entries that are 100% fixed.
3. **Merge**: add new findings under `## Open`, deduplicating against
   existing entries, sorted CRITICAL → HIGH → MEDIUM → LOW.
4. **Preserve**: leave all `## Won't Fix` entries untouched.

File format:

```markdown
# Audit Findings

> Auto-managed by $x-review and $x-fix.

## Open

### [SEVERITY] subsystem: one-line summary
- **Where**: file:line_range
- **What**: description
- **Why**: invariant/pattern violated
- **Suggested fix**: how to fix

---

## Won't Fix

### [SEVERITY] subsystem: one-line summary
- **Where**: file:line_range
- **What**: description
- **Reason**: why this cannot or should not be fixed
```

## Output Format

```
## Review Summary

**Commit**: <hash> <subject>
**Subsystems**: <list>
**Risk Level**: CRITICAL / HIGH / MEDIUM / LOW

## Findings

### [SEVERITY] subsystem: one-line summary

**Where**: file:line_range
**What**: Description
**Why**: Invariant/pattern violated (cite technical-patterns.md)
**Fix**: Suggested fix

## No Issues Found

(list areas checked)
```

---

## Full Audit Protocol (`all` scope)

Audit all source files, not just uncommitted changes (~4.4K LOC including
tests). Partition the repository by subsystem; if delegation is available
and authorized, launch one read-only reviewer per subsystem group and keep
ownership disjoint.

| Subsystem | Paths | Pattern Guide |
|-----------|-------|---------------|
| execution and precompiles | `crates/execution/`, `crates/precompile/`, `crates/types/src/tx.rs` | `execution.md` |
| state and genesis | `crates/state/`, `crates/types/src/genesis.rs`, `crates/types/src/config.rs`, `crates/types/src/receipt.rs` | `state.md` |
| tx pool | `crates/txpool/` | `txpool.md` |
| RPC and node | `crates/rpc/`, `crates/node/` | `rpc.md` |

Each reviewer reads all source files in its group, loads the pattern guide,
and performs deep analysis (determinism, nonce, revert, flush, locks).
Aggregate and deduplicate findings, then update `docs/audit.md` per the
Audit Registry step.

Report:

```
## Full Audit Report

**Scope**: All crates (~4.4K LOC including tests)
**Subsystems Audited**: <list>
**Total Findings**: N (X critical, Y high, Z medium, W low)

## Findings
(sorted by severity, grouped by subsystem)

## Clean Areas
(subsystems with no findings — list what was checked)
```
