# zig as `${{ compiler() }}` on conda-forge — state of the world

Reviewed 2026-09-05 against zig-feedstock main (0.16.0, build 16 in
`recipe.yaml`, build 15 published) and the live conda-forge channel.

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

Special cases: ppc64le routes linking through `gcc_impl`/`binutils_impl`
(LLD lacks PowerPC64 relocations); riscv64 pins glibc 2.27 floor.

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
- Rapid iteration: builds 13→16 within days; build-17 PR open; a `zig_dev`
  label carries 0.17.0 prereleases.
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
