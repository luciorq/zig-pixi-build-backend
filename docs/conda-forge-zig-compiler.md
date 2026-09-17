# zig as `${{ compiler() }}` on conda-forge — state of the world

Reviewed 2026-09-05 against zig-feedstock main (0.16.0, build 16 in
`recipe.yaml`, build 15 published) and the live conda-forge channel.
Re-checked 2026-09-16: build 17 published (2026-09-15), build 18 open as
the declared last 0.16.0 build; see "Update 2026-09-16" at the end.

> **Zig upstream is on Codeberg, not GitHub.** Every `github.com/ziglang/*`
> repository is a frozen leftover of the 2025-11-26 migration. Use
> https://codeberg.org/ziglang and https://ziglang.org/download/index.json.
> Details and API pointers: [`zig-upstream-is-on-codeberg.md`](zig-upstream-is-on-codeberg.md).

## Package architecture (since 0.16.0 build ~14/15)

The feedstock produces a full conda compiler-package family, structurally
parallel to gcc's:

| output | role |
|---|---|
| `zig_impl_<platform>` | the real toolchain: `bin/<triplet>-zig` + `lib/zig` std/libc trees |
| `zig_<target>` | "compiler package": activation scripts + a compiled **wrapper multiplexer** installed as `<triplet>-zig-{cc,cxx,ar,ranlib,asm,rc,lld,windres,force-load-cc,force-load-cxx}` |
| `zig` | user-facing meta: `bin/zig` symlink to the triplet binary |
| `zig-compiler` | toolchain metapackage: `zig` (+ `lld`/`llvm-tools` on macOS) |

The wrapper multiplexer is a compiled C program (not shell) that
translates GCC-style invocations for zig: `--target=`, `-march=`/`-mtune=`
mapping, `-Wl,` translations, `-print-sysroot`/`-print-multiarch`,
`CONDA_BUILD_SYSROOT`, `MACOSX_DEPLOYMENT_TARGET`, MinGW/MSVC library name
resolution, and glibc-versioned triples.

**Activation contract**: `zig_<target>`'s activate script exports `ZIG`,
`ZIG_CC`, `ZIG_CXX`, `ZIG_AR`, `ZIG_RANLIB`, `ZIG_ASM`, `ZIG_RC`,
`ZIG_LLD` (+ force-load variants) and pre-sets a HOME-based
`ZIG_GLOBAL_CACHE_DIR` fallback. It does **not** export `CC`/`CXX` —
recipes bridge explicitly (see below).

## Cross-compiler coverage (live packages, 0.16.0)

Cross packages are **same-OS-family only** (`xc_valid` in the recipe):

| build subdir | `zig_<target>` packages present |
|---|---|
| linux-64 | linux-64, linux-aarch64, linux-ppc64le, linux-riscv64, linux-s390x |
| win-64 | win-64, win-arm64, win-32 |
| osx-arm64 | osx-arm64, osx-64 |

Special cases (as of build 16): ppc64le routes linking through
`gcc_impl`/`binutils_impl` (LLD lacks PowerPC64 relocations); riscv64 pins
glibc 2.27 floor. **Build 17 dropped the ppc64le gcc/binutils routing
patches** in favour of a `dl_iterate_phdr` patch plus native bootstrap
(see the 2026-09-16 update).

## Target-triple policy

`zig_triplet` in the recipe derives from conda-forge's **pinning**
(`c_stdlib_version` → glibc suffix), e.g. `x86_64-linux-gnu.<glibc>`,
`aarch64-macos.<ver>-none` — and notably **`x86_64-windows-msvc`**:
conda-forge chose the MSVC ABI for Windows, where pixi-build-zig defaults
to `-gnu` (MinGW). An ecosystem divergence to track.

## `compiler('c')` integration status

- **Not** in global `conda-forge-pinning` — no `c_compiler: zig` default
  anywhere.
- **Live per-feedstock**, today, for platforms without a conventional
  toolchain:
  - `sbcl-feedstock`: `c_compiler: zig` (+ `c_compiler_version: 0.15.2`)
    on linux-riscv64-class platforms **and win-arm64**
  - `aiomqtt-feedstock`: same for linux-riscv64-class
- The naming contract is what makes this work: `${{ compiler('c') }}`
  renders `<c_compiler>_<target_platform>` → `zig_linux-riscv64` etc.,
  which exist.
- The missing half is bridged in the recipe body:
  `export CC="${ZIG_CC}"` (one line in sbcl's build.sh).

## Roadmap signals

- Open experimental PR #175: **"ZIG-based LLVM (self-dependent zig)"** —
  the feedstock building its own LLVM with zig (self-hosting; directly
  overlaps flang-pixi's stage-1 `llvm-zig`).
- Rapid iteration: builds 13→17 within two weeks; build-18 PR open (#188,
  "last planned build for 0.16.0"); a `zig_dev` label carries 0.17.0
  prereleases.
- Maintainers: MementoRC (driving), xmnlab, **tdejager** (prefix.dev;
  author of the original pixi-build-zig PR) — the conda-forge and
  pixi-build efforts share people.

## Interactions with pixi-build-zig (verified 2026-09-03/05)

- The backend's contract (`zig build` + explicit `-Dtarget`/`-Dcpu`,
  `CC="zig cc …"`) works unchanged through both the plain binary and the
  wrappers.
- The activation's `ZIG_GLOBAL_CACHE_DIR` pre-set defeated the backend's
  conditional cache default; fixed by exporting unconditionally
  (fork commit "export zig cache dirs unconditionally").
- The conda wrappers cannot replace the backend's cross story: they exist
  same-OS-family only, while raw `zig cc -target` crosses OS boundaries
  (our linux→win/osx artifacts run on real hardware in CI).

## Update 2026-09-16

Delta against the 2026-09-05 review. Everything not listed here is
unchanged (wrapper design, activation contract and exported variables,
`CC`/`CXX` not exported, MSVC Windows triple, same-OS-family cross
matrix, maintainers, PR #175 still draft).

### zig-feedstock

- **Build 17 published 2026-09-15** on every subdir (linux-64
  `zig-0.16.0-hcf03e5e_17`, `zig_linux-64 hb5c597f_17`,
  `zig_impl_linux-64 h0addc32_17`, `zig-compiler habf4d11_17`), via PR #176
  "MNT: v0.16.0 17 fine tuning" (30 commits). Hash-affecting changes:
  - variant key renamed `cross_target_platform_` → `xtarget_` across all
    `.ci_support` lanes;
  - `zig_compiler` / `zig_compiler_version` variant keys **removed** from
    `recipe/variants.yaml`.
  - ppc64le: the gcc/binutils link-routing patches and `_lld_bundle.sh`
    were dropped in favour of a `dl_iterate_phdr` patch plus a native
    bootstrap script; `zig-cc-unix.c` shim reworked but same design.
  - dev-test now reads `ZIG_GLOBAL_CACHE_DIR` instead of parsing `zig env`
    (confirms the env var is the contract the feedstock relies on).
- **PR #188 "MNT: v0.16.0 18 ppc64le bootstrap"** open (2026-09-15),
  body says "Last planned build for 0.16.0". Bootstraps ppc64le from the
  published `zig_impl_linux-aarch64`; splits `build.sh` into helper
  scripts. Not yet published.
- **`dev` branch (0.17.0)**: daily `zig master` snapshot bumps
  (now `2127+e90365cd5`, PR #187 → `2131+d08989840` open); LLVM 22.1.6
  (main is 21.1.8). PR #182 fixed Windows ARM64 executable and wrapper
  packaging, and `dev` now hosts **native win-arm64** lanes
  (`win_arm64_xtarget_win-{32,64,arm64}`). Only on the `zig_dev` label;
  no 0.17.x on `main`, and win-arm64 on 0.16.0 is still cross-built
  from win-64.
- Issue #179 (seed win-arm64 from the official Zig archive instead of a
  source build) closed as not planned.
- Activation scripts untouched since 2026-05-26.

### Ecosystem adoption — flat

- Still absent from `conda-forge-pinning`, every CFEP, and
  conda-forge.github.io.
- Still exactly two `c_compiler: zig` feedstocks (sbcl, aiomqtt), both
  still pinned to `c_compiler_version: 0.15.2`, neither bumped to 0.16.0.
- In flight, same author (MementoRC): `ocaml-feedstock` PR #103
  "[experimental] FEA: Add win zig port", `admin-requests` #2335 "ADD: zig
  win-arm64" and #2338 "ADD: ocaml win-arm64", conda-smithy #2688
  (binfmt_misc on linux-aarch64 runners). All open.
- `ncdu-feedstock` uses `zig >=0.15.2,<0.16` as a plain build dependency
  (upstream ncdu is written in Zig); merged 2026-09-05.

### Upstream ziglang/zig

- **GitHub is not upstream**: ziglang/zig moved to Codeberg 2025-11-26 and
  every `github.com/ziglang/*` repo is frozen or archived; the GitHub
  releases API stops at 0.15.1. Poll
  `https://ziglang.org/download/index.json` or codeberg.org/ziglang/zig.
  See [`zig-upstream-is-on-codeberg.md`](zig-upstream-is-on-codeberg.md).
- No 0.16.x point release; 0.16.0 (2026-04-13) remains latest stable.
  0.17.0 has no date (master `0.17.0-dev.2131`, milestone 24 open issues).
- Master changes relevant to the backend:
  - `--global-cache-dir` was **removed from `zig fetch` and `zig build`**
    (2026-08-04/05): "must be set with an env var now". `ZIG_GLOBAL_CACHE_DIR`
    is the supported mechanism (and still a flag for `zig cc` /
    `build-exe`). Our unconditional export is the right shape for 0.17.
  - `zig cc` now passes CPU model/features to the assembler (PR #36383,
    2026-08-05) — affects `-march`/`-mcpu` cross builds.
  - glibc 2.44, Linux headers 7.2, macOS SDK 27.0 headers on master.
  - No change to the Windows MSVC-vs-GNU default. LLVM/LLD removal is
    post-0.17.

### Implications for pixi-build-zig

- Nothing in build 17 changes the backend contract. The removed
  `zig_compiler*` variant keys only mattered to recipes rendering
  `${{ compiler('zig') }}`-style variants, which we do not use.
- For 0.17 readiness: any code path that passes `--global-cache-dir` to
  `zig build` or `zig fetch` will break; rely on `ZIG_GLOBAL_CACHE_DIR`
  only (already the case after the "export zig cache dirs
  unconditionally" change, but worth a grep before bumping the
  `zig = "0.16.*"` pin in the examples).
- The MSVC/GNU Windows divergence persists; still an open ecosystem
  question, not something the feedstock is moving on.
