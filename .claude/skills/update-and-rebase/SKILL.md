---
name: update-and-rebase
description: Rebase the pixi-build-zig fork (../pixi, branch feat/pixi-build-zig) onto upstream prefix-dev/pixi main, absorb dependency bumps (rattler-build crates, pixi, conda-forge zig), re-verify the full example matrix, refresh the tracking docs, push and watch CI. Use for "rebase the fork", "update dependencies", "check for upstream updates", or a periodic refresh of the zig/pixi/rattler-build status docs.
---

# Update and rebase pixi-build-zig

Two repos are involved. This testbed (`$PIXI_PROJECT_ROOT`) drives builds;
the backend source is the sibling checkout `../pixi` (fork
`luciorq/pixi`, branch `feat/pixi-build-zig`, crate `crates/pixi_build_zig`,
remote `upstream` = `prefix-dev/pixi`).

Never commit or push on the user's behalf: stage, report, and suggest a
commit message. The only exception is the rebase itself, which rewrites the
fork branch locally; the user pushes with `--force-with-lease`.

## Phase 0 — research upstream state (parallel, read-only)

Run these as independent subagents or in parallel, then reconcile:

1. **conda-forge zig**: `pixi search zig -c conda-forge`, `pixi search
   zig_linux-64 -c conda-forge`, `pixi search zig-compiler -c conda-forge`
   for the live build number; `gh pr list --repo conda-forge/zig-feedstock
   --state all --limit 15` and `gh api repos/conda-forge/zig-feedstock/
   commits?since=<last review date>` for feedstock activity; note anything
   touching `recipe/scripts/activate.*`, `zig-cc-unix.c`, variant keys, the
   Windows triple (`x86_64-windows-msvc`), or cross-target lanes.
2. **Upstream Zig**: **Codeberg only, never GitHub** (see
   `docs/zig-upstream-is-on-codeberg.md`). Versions:
   `curl -s https://ziglang.org/download/index.json | jq 'keys'`. Tags,
   milestones, issues: `https://codeberg.org/api/v1/repos/ziglang/zig/...`.
3. **pixi**: `gh release list --repo prefix-dev/pixi --limit 5`; `gh release
   view <tag> --repo prefix-dev/pixi` for build-related items
   (`pixi publish`, `--target-platform`, run-exports, backend protocol
   `PIXI_BUILD_API_VERSION_*` in `crates/pixi_build_types/src/lib.rs`).
4. **rattler-build**: `gh release list --repo prefix-dev/rattler-build
   --limit 5`; crates.io versions of `rattler_build_core` and
   `rattler_build_recipe`; whether `crates/rattler_build_core/src/macos/
   link.rs` still has the shrink-only `can_deal_with_rpath` guard (our draft
   issue in `docs/upstream/` stays valid while it does).
5. **Draft upstream issues**: search for duplicates before the user files
   them: pixi (`gh search issues --repo prefix-dev/pixi "run-exports path"`),
   rattler-build (`"LC_RPATH"`, `"install_name_tool"`), zig
   (`https://codeberg.org/api/v1/repos/ziglang/zig/issues?state=all&q=LC_RPATH&type=issues`).

Record the findings in `docs/pixi-rattler-build-status.md` (version table
+ release deltas) and, for zig-feedstock changes, as a dated "Update" section
in `docs/conda-forge-zig-compiler.md`.

## Phase 1 — rebase the fork

```sh
cd ../pixi
git status --short                      # must be clean
# insta leaves `*.pending-snap` files after a failed snapshot run; untracked,
# so a clean status still shows them as `??`. They BLOCK rebase picks
# ("untracked working tree files would be overwritten"). Remove first:
find crates/pixi_build_zig -name '*.pending-snap' -delete
git fetch upstream main
git branch -f backup/feat-pixi-build-zig-pre-rebase-$(date +%Y%m%d) HEAD
git log --format='%h %s' upstream/main..HEAD      # the fork commits (currently 8)
git merge-tree --write-tree --name-only HEAD upstream/main | head   # preview conflicts
GIT_EDITOR=true git rebase upstream/main
```

Expected conflict: **only `Cargo.lock`** (binary-ish merge). Resolve each
occurrence by taking upstream's lock and letting cargo re-add the zig crate:

```sh
git checkout --ours Cargo.lock          # during a rebase, --ours == upstream/main
cargo metadata --format-version 1 >/dev/null   # NOT --offline: it fails on new upstream deps
git add Cargo.lock
GIT_EDITOR=true git rebase --continue
```

Repeat until `Successfully rebased`. A compile error after the rebase (not a
conflict) usually means a rattler type rename: 2026-10-01 `Platform` became
`Subdir` (`Subdir::current()` is `Option`, upstream uses
`.unwrap_or(Subdir::NoArch)`); mirror `crates/pixi_build_rust` on
upstream. Any conflict outside `Cargo.lock` means
upstream changed the backend framework (`crates/pixi_build_backend`,
`rattler_build_recipe` API); stop and resolve by hand, mirroring what
`crates/pixi_build_rust` or `crates/pixi_build_cmake` do on upstream.

Post-rebase invariants to check and report:

```sh
git diff upstream/main -- Cargo.toml            # must be empty
git diff upstream/main --stat -- Cargo.lock     # only additions
git diff upstream/main -- Cargo.lock | grep -E '^[-+]name = '   # only "pixi-build-zig"
grep -A1 -E '^name = "(rattler_build_core|rattler_build_recipe|rattler_conda_types)"$' Cargo.lock | grep -E '^(name|version)' | paste - -
git log -3 --format='%h %G? %s'                 # G/U = still signed; N = user must re-sign
```

`commit.gpgsign` is on and the rebase normally re-signs; if `%G?` prints
`N`, tell the user to re-run `git rebase -f upstream/main` with gpg primed.

## Phase 2 — bump crates beyond upstream (only if asked)

Upstream pixi usually trails crates.io by one rattler-build release. Staying
on upstream's pins is the default and needs no code changes. If the user
wants the latest `rattler_build_recipe`/`rattler_build_core`, known
breaking signatures to patch in `crates/pixi_build_zig/src/main.rs` (check
`docs/pixi-rattler-build-status.md` for the current list):
`topological_sort_by_dependencies` extra `include_test_dependencies` arg,
`is_skipped` returning `Result`, `parse_tests(node, ParseConfig)`,
`test_vars(.., work_dir)`.

## Phase 3 — build, test, full matrix

Run **sequentially, in the foreground** where possible: this machine's
harness kills background tasks under memory pressure, and pixi installs are
memory-hungry. Foreground commands may take up to 10 minutes each.

```sh
cd ../pixi && cargo build -p pixi-build-zig && cargo test -p pixi-build-zig   # 40 tests
cd "$PIXI_PROJECT_ROOT"
SCRATCH=<session scratchpad directory>   # never /tmp
mv dist "$SCRATCH/dist-prev-$(date +%Y%m%d)" 2>/dev/null; mkdir -p dist   # keep old hashes to compare
pixi run cross-hello-all        # 5 platforms
pixi run cross-zlib-all         # 5 platforms
pixi run build-zon-dep && pixi run cross-zon-dep-win64
pixi run build-greet   && pixi run cross-greet-win64
ls dist | wc -l                 # expect 16
bash scripts/verify-artifacts.sh | tee "$SCRATCH/verify.out"
```

Apply the same greps CI uses on `verify.out` (from
`.github/workflows/matrix.yml`, step "Verify artifact layouts"): the seven
`Library/...` Windows paths, `ELF 64-bit LSB executable, ARM aarch64`,
`Mach-O 64-bit arm64`, `Mach-O 64-bit x86_64`, `PE32+ executable`.

Then the demos, one at a time, each grepping its expected line:

| task | expected |
|---|---|
| `pixi run demo-zlib` | `zlib .* on x86_64-linux` |
| `pixi run demo-zon-dep` | `greetings from a zon dependency on x86_64-linux` |
| `pixi run demo-greet` | `hello from libgreet on x86_64-linux` |

Then the upstream-zig comparison (fetches the sha-verified official
tarball into `.cache/upstream-zig/`, builds the linux-64 examples with it,
diffs `NEEDED`/size against `dist/`):

```sh
pixi run -q bash scripts/compare-upstream-zig.sh
```

The only expected difference is `only-conda={libdl libm libresolv librt
libutil}` on dynamically linked binaries (conda-forge's `--no-as-needed`
patch). Anything `only-upstream`, or libc++/libstdc++/libunwind appearing
only on the conda side, is a regression to investigate against
`docs/conda-forge-zig-compiler.md` ("Feedstock patches"). When the zig
feedstock ships a new build, re-run this before trusting the matrix.

**New-zig readiness** (when ziglang.org lists a newer stable than the
examples' pin, or before bumping the pin): rerun the comparison against
that version — it downloads and sha-verifies the official tarball and
reports any example that no longer compiles:

```sh
UPSTREAM_ZIG_VERSION=<new version> pixi run -q bash scripts/compare-upstream-zig.sh
```

Fix examples so they compile on BOTH the conda-forge version and the new
one (conda-forge lags upstream by weeks). Known 0.17 traps: `a ** n` array
multiplication removed; a missing `--search-prefix` directory fails on
every version (the backend's script does `mkdir -p`, ad-hoc `zig build`
calls must too); the first `zig build` against an empty global cache
compiles the build system (~100 s), so point `ZIG_GLOBAL_CACHE_DIR` at a
reusable directory when timing things.

Not reproducible locally (no `qemu-aarch64` installed): the aarch64
execution step, and the macOS/Windows execution jobs. CI covers them.

Build hashes in `dist/` should match the previous run unless the zig build
or backend recipe changed; a hash change is worth explaining in the report.

Confirm `git status --short` shows no example `pixi.lock` drift; if a new
pixi rewrote the lockfiles, stage them and say so.

## Phase 4 — docs consistency

Update and stage (do not commit):

- `docs/pixi-rattler-build-status.md`: fork column of the version table,
  "Fork rebased <date> onto <sha>" line, action-item checkboxes.
- `docs/conda-forge-zig-compiler.md`: dated update section if the feedstock
  moved; keep earlier claims but annotate them ("as of build N").
- `README.md` "Verified so far": a re-verification paragraph with date,
  upstream sha, crate versions, zig build; fix any "Known gaps" bullet the
  work made stale.
- Memory: append a `RE-REBASED <date>` line to the `pixi-build-zig-location`
  memory note (upstream sha, crate versions, backup ref, test count).

Check that the backend doc's "Full example" is still byte-identical to the
drift-test manifest (both must change together; any new config option goes
into both, with a non-default value and an assertion in
`scripts/check-options-example.sh`):

```sh
diff <(awk '/^### Full example/{f=1} f&&/^```toml/{c=1;next} f&&c&&/^```/{exit} f&&c' \
        ../pixi/docs/build/backends/pixi-build-zig.md) examples/options-zig/pixi.toml \
  && echo "doc snippet == examples/options-zig/pixi.toml"
pixi run demo-options     # every option's effect asserted, linux-64 native
```

Grep both repos for stale claims the findings invalidate, e.g.
`grep -rn -iE 'github\.com/ziglang|global-cache-dir' README.md docs ../pixi/crates/pixi_build_zig ../pixi/docs/build/backends/pixi-build-zig.md`.

## Phase 5 — hand-off and CI

Report: rebase summary (commits absorbed/replayed, conflicts), version
before/after table, test/matrix/verify/demo results, docs touched, and:

1. `cd ../pixi && git push --force-with-lease` (user).
2. Commit the testbed (user); suggest a message.

After the user pushes, watch the testbed run in the **foreground**
(background watchers get killed):

```sh
gh run list --repo luciorq/zig-pixi-build-backend --limit 3
timeout 590 gh run watch <run-id> --repo luciorq/zig-pixi-build-backend --exit-status --interval 30
gh run view <run-id> --repo luciorq/zig-pixi-build-backend --json status,conclusion,jobs \
  --jq '"\(.status) \(.conclusion)", (.jobs[] | "\(.conclusion // .status)\t\(.name)")'
```

Expect three green jobs: `build matrix (linux-64)`, `execute on macOS
arm64`, `execute on Windows x64`. A lockfile change makes the first run
~2 min slower (cold rust-cache). If a run fails with **empty logs**, the
runner ran out of disk: read the check-run annotations
(`gh api repos/luciorq/zig-pixi-build-backend/check-runs/<job-id>/annotations`).
Record the green run id in the memory note.
