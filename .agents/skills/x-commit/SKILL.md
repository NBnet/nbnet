---
name: x-commit
description: Self-review all uncommitted nbnet changes, fix every finding, format, bump the patch version, and create a local commit. Use only when the user explicitly invokes $x-commit.
---

# nbnet Self-Reviewing Commit

Resolve repository paths from the Git root; Markdown links are relative to
this file. Read invocation arguments from the user prompt.

This explicit invocation authorizes reviewing the uncommitted diff, fixing
findings, and creating one local commit. It does not authorize pushing,
tagging, or modifying other repositories.

## Setup

Read first:
[technical-patterns.md](../../../docs/ai/technical-patterns.md),
[review-core.md](../../../docs/ai/review-core.md), and
[false-positive-guide.md](../../../docs/ai/false-positive-guide.md).

## Execution Protocol

### 1. Deep Self-Review

1. Record a baseline (`git status --short`, `git rev-parse HEAD`), then run
   `git diff HEAD` to collect all uncommitted changes.
2. If the diff is empty, report "nothing to commit" and stop.
3. Identify ALL affected subsystems via the path table in
   [x-review](../x-review/SKILL.md) and read the matching guide under
   `docs/ai/patterns/` for each.
4. Perform the full regression analysis from `review-core.md`:
   - **Classify** each change (app hash, execution, validation, pool,
     precompile, persistence, RPC, locks).
   - **Invariant check** — ordered trie inputs, exact execution nonce,
     single `transact_commit` path, flush before `state_root`.
   - **Boundary conditions** — nonce gap, RBF, revert, gas limit, empty
     genesis, two equal roots.
   - **Failure paths** — bad bytes inside a block, commit error, short RPC
     input.
   - **Concurrency** — state mutex or `parking_lot` guard across `.await`.
5. Check cross-cutting concerns: `EvmExecutor` vs `SharedExecutor`, genesis
   serde defaults, RPC answers matching executor state.
6. Enforce style rules: no `#[allow(...)]`, no new `unsafe`, doc-code
   alignment.
7. Audit any added `unsafe` block. There should be none.
8. Refute every finding against `false-positive-guide.md` — retain only
   findings with concrete evidence.

### 2. Fix All Findings

For EVERY confirmed finding (CRITICAL, HIGH, MEDIUM, or LOW):

1. Fix completely — no TODOs, no "fix later", no partial fixes.
2. Re-run `git diff HEAD` and repeat the review on the new diff.
3. Fix any new findings introduced by the fixes. Iterate until clean.
4. Report the final list of fixes applied.

### 3. Format

Run `make fmt`, then `make lint`. Run `make test` when execution, state,
the pool, or RPC changed.

### 4. Bump Patch Version — MANDATORY

1. Run `git diff HEAD --name-only` — if it lists any `.rs` file, a version
   bump is required. Skip only if every changed file is non-code (`.md`,
   version-only `.toml`, etc.).
2. Read `version = "X.Y.Z"` under `[workspace.package]` in the root
   `Cargo.toml`.
3. Compute `NEW = X.Y.(Z+1)` (e.g., `0.1.0` → `0.1.1`).
4. Set that `version = "NEW"` under `[workspace.package]`. Member crates
   use `version.workspace = true`; do not write a version into them.
5. Verify by grepping the root file for the NEW version string; fix any
   mismatch before continuing.

### 5. Commit

1. Run `git diff HEAD --stat` and `git log -5 --oneline` for scope and
   commit style.
2. Draft a message following the repo's existing style (type prefix:
   `fix:`, `feat:`, `docs:`, `refactor:`, `chore:`). Summarize the "why",
   keep the subject to one line, add a body for multi-subsystem work.
3. Stage specific files with `git add` (not `-A`).
4. Commit with a HEREDOC — **no co-author line**:

```
git commit -m "$(cat <<'EOF'
<commit message here>
EOF
)"
```

5. Run `git status` to verify the commit succeeded.

Do not push, tag, amend, or rewrite history.

## Output Format

```
## Self-Review Commit Summary

**Reviewed**: <number of files changed>
**Subsystems**: <list>
**Findings**: <N found, N fixed> (or "0 — clean")
**Commit**: <short hash> <subject line>
```
