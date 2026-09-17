# pixi / pixi-build backends / rattler-build — tracking note

Reviewed 2026-09-16. Companion to `conda-forge-zig-compiler.md`; records
the upstream state the pixi-build-zig fork (`../pixi`, branch
`feat/pixi-build-zig`) is measured against.

## Version table

| component | fork (`../pixi`) | upstream pixi `main` | latest published |
|---|---|---|---|
| pixi | 0.78.0 (crate version) | 0.81.0 (tag 2026-09-15) | **0.81.0** |
| `pixi-build-api-version` | 7 | 7 (lower 7, upper 8) | 7 |
| `rattler_build_core` | 0.2.12 | 0.2.13 | **0.2.14** (2026-09-14) |
| `rattler_build_recipe` | 0.1.13 | 0.1.14 | **0.1.15** (2026-09-14) |
| `rattler_build_jinja` / `_variant_config` | 0.1.13 | 0.1.14 | 0.1.15 |
| `rattler_build_types` | 0.1.12 | 0.1.13 | — |
| `rattler_conda_types` | 0.51 | 0.52 | — |
| rattler-build CLI | — | — | **0.76.1** (2026-09-14) |

Fork base is upstream `337473f04` (2026-09-03); upstream `main` is 39
commits ahead, the fork 8 commits ahead. A dry-run merge
(`git merge-tree`) conflicts only in `Cargo.lock`.

## pixi 0.79.0 → 0.81.0 (2026-09-03 → 2026-09-15)

- **0.79.0**: `__glibc` default 2.39 on linux-riscv64 (#6914; the same
  commit bumped the rattler-build crates to core 0.2.13 / recipe 0.1.14),
  `pixi workspace dependencies`, `pixi install --script`, static MSVC CRT
  restored on Windows builds (#6919).
- **0.80.0**: conda-script only (experimental inline script metadata).
  No build changes.
- **0.81.0**: cross-compile dispatcher fixes by @hunger, all relevant to
  `pixi publish --target-platform`:
  - #6984 `PrefixPlatformMismatchError` for source build prefixes;
  - #6985/#6986 derived environments track their platform explicitly and
    nested ones stay on the **build** platform;
  - #6987 build platform shown for nested derived environments;
  - #6988 docs: a source package under `build-dependencies` is built
    natively for the build platform; under `host-`/`run-dependencies` it
    is built for the target. A package that is both published and a build
    dependency of a sibling is built twice in a cross `pixi publish`.
- Unchanged: backend protocol (v7 since 0.77.0, `conda/outputs` +
  `conda/build_v1`), `PIXI_BUILD_BACKEND_OVERRIDE` /
  `PIXI_BUILD_BACKEND_OVERRIDE_ALL`, `pixi publish`, run-exports,
  lockfile format, `[package]` schema.
- Unreleased on `main` after 0.81.0: PGO release builds only.

## Backends

- `prefix-dev/pixi-build-backends` is **archived** (read-only since
  2026-01-20). PR #412 "feat: introduce zig build-backend" was closed
  unmerged the same day ("we can use this as starting point for another
  attempt"). Branch `feat/pixi-build-zig` there is frozen at `3189d3b1`
  (2025-11-10).
- All backends live in `prefix-dev/pixi/crates/`. **No `pixi_build_zig`
  anywhere** (monorepo, conda-forge, prefix.dev channel). New first-party
  backend since our last look: `pixi_build_r` (0.1.7) — the freshest
  in-tree template for a new backend crate.
- Published versions (conda-forge == prefix.dev/pixi-build-backends):
  cmake 0.4.6, rust 0.5.6, python 0.8.6, rattler-build 0.4.6, mojo 0.2.7,
  ros 0.7.5, r 0.1.7; `pixi_build_backend` lib 0.1.7. Only ros moved in
  the window. #6862 removed the backends channel from pixi; backends
  resolve from conda-forge.
- Open PRs worth watching: #7011 (deterministic source record ordering,
  fixes #7000), #6993 (`pin-compatible` against path deps in lock check),
  #6960 (pixi-build-rust: scope cross-compile C flags), #6887 (reuse
  immutable git build artifacts).

## rattler-build 0.74.0 → 0.76.1 (2026-08-17 → 2026-09-14)

### Mach-O relinker — no change (our draft issue still valid)

`crates/rattler_build_core/src/macos/link.rs` last touched 2026-08-05
(#2718, preserve `@executable_path`-relative rpaths; already in the fork's
0.2.12). The builtin relinker still refuses any rpath addition/removal or
lengthening (`can_deal_with_rpath`) and falls back to `install_name_tool`;
`RATTLER_BUILD_BUILTIN_CODESIGN` is still opt-in. The full `arwen` crate
(which can add load commands) is published (0.0.5) but rattler-build
depends only on `arwen-codesign`. Related stale PRs: #2358
(`@loader_path` support), #2208 (code signing). No issue about
`LC_RPATH` addition exists; `docs/upstream/rattler-build-relinker-rpath-add.md`
remains unfiled and unduplicated.

Only relink-adjacent change: #2787 runs link *checks* even when
relocation is disabled (per-file guard instead of global early return).

### Crate API changes the fork will hit when bumping

- recipe 0.1.15 (#2796): `topological_sort_by_dependencies` gained a 4th
  `include_test_dependencies: bool` parameter.
- recipe 0.1.15 (#2783): `is_skipped` returns `Result<bool, ParseError>`;
  malformed `skip` expressions are hard errors.
- recipe 0.1.15 (#2813): `parse_tests` / `parse_test_item` take
  `ParseConfig`.
- core 0.2.14: `test_vars()` takes `work_dir: &Path`; `SRC_DIR` is the
  test workdir at test time; new `check_overlapping_files` /
  `check_unused_staging_files`.
- Matching upstream pixi `main` (core 0.2.13 / recipe 0.1.14) avoids all
  of the above; going to 0.2.14 / 0.1.15 does not.

### Behaviour changes

- #2784 `files: []` now packages nothing.
- #2810 `CROSSCOMPILING_EMULATOR` forwarded from the shell env and always
  part of the variant/hash when configured.
- #2802/#2804 `use_keys` / `ignore_keys` propagate to outputs and staging;
  `down_prioritize_variant` inheritance preserved.
- #2775 `__glibc` 2.39 default on linux-riscv64 (mirrors pixi #6914).
- No change to `compiler()` / `stdlib()` / `c_compiler` rendering,
  `CONDA_BUILD_SYSROOT`, `target_platform` vs `build_platform`, or
  `--target-platform`. Zero zig awareness in rattler-build. New open
  issues #2792 (`pin_compatible(compiler('c'))`) and #2791 (staging →
  inheriting output `pin_compatible`) are compiler-adjacent.

## Draft upstream issues (`docs/upstream/`) — status

| draft | duplicate upstream? | still reproduces on latest? |
|---|---|---|
| pixi run-exports path off-by-one | none found (searched 2026-09-16) | not re-tested on 0.81.0 |
| rattler-build relinker `LC_RPATH` add | none | yes, code unchanged |
| zig Mach-O `-rpath` dropped | not searched (Codeberg) | not re-tested |

## Action items

1. Rebase the fork onto upstream `main` (Cargo.lock conflict only) to pick
   up 0.81.0's cross-compile dispatcher fixes and the crate bumps to
   core 0.2.13 / recipe 0.1.14.
2. Re-test the run-exports off-by-one on pixi 0.81.0 before filing.
3. If bumping straight to recipe 0.1.15, patch the three signature
   changes above.
