# zig-pixi-build-backend

Testbed for **`pixi-build-zig`** — a [pixi build backend](https://pixi.prefix.dev/latest/build/backends/)
for projects using the Zig build system, with **cross-compilation as the core
feature**. The backend itself lives on the
[`feat/pixi-build-zig` branch of the luciorq/pixi fork](https://github.com/luciorq/pixi/tree/feat/pixi-build-zig)
(`crates/pixi_build_zig`), picking up where
[prefix-dev/pixi-build-backends#412](https://github.com/prefix-dev/pixi-build-backends/pull/412)
left off. This repo holds example packages and the scripts that prove the
backend works before anything goes upstream.

## What the backend does

For a package whose `build.zig` follows the `b.standardTargetOptions` /
`b.standardOptimizeOption` convention, the generated build script is:

```sh
export ZIG_GLOBAL_CACHE_DIR="${ZIG_GLOBAL_CACHE_DIR:-$SRC_DIR/.zig-global-cache}"
export ZIG_LOCAL_CACHE_DIR="${ZIG_LOCAL_CACHE_DIR:-$SRC_DIR/.zig-local-cache}"

export CC="zig cc -target x86_64-linux-gnu.2.28 -mcpu=baseline"
export CXX="zig c++ -target x86_64-linux-gnu.2.28 -mcpu=baseline"
export AR="zig ar"
export RANLIB="zig ranlib"
export CC_FOR_BUILD="zig cc"
export CXX_FOR_BUILD="zig c++"

mkdir -p "$PREFIX"
zig build --build-file .../build.zig --prefix "$PREFIX" --search-prefix "$PREFIX" \
    -Dtarget=x86_64-linux-gnu.2.28 -Dcpu=baseline -Doptimize=ReleaseFast
```

- `-Dtarget` is always explicit, derived from the conda target platform, so a
  cross build takes the exact same path as a native one.
- `-Dcpu=baseline` keeps packages runnable on any machine of the target
  architecture; glibc is pinned (`.2.28`) to match the conda-forge sysroot.
- `CC`/`CXX`/`AR`/`RANLIB` route anything the build spawns through zig's C
  toolchain for the same target (`CC_FOR_BUILD` stays untargeted for cross
  builds).
- Windows targets install into the conda-conventional `Library\` prefix even
  when cross-compiled from unix.

## Verified so far (2026-08-13, linux-64 build machine)

| target | result | artifact |
|---|---|---|
| linux-64 (native) | ✅ builds, runs | `bin/hello-zig` — ELF x86-64, ReleaseFast |
| linux-aarch64 (cross) | ✅ builds | `bin/hello-zig` — ELF aarch64 |
| win-64 (cross) | ✅ builds | `Library/bin/hello-zig.exe` — PE32+ x86-64 |
| osx-arm64 (cross) | ✅ builds | `bin/hello-zig` — Mach-O arm64, ad-hoc code signature |
| osx-64 (cross) | ✅ builds | `bin/hello-zig` — Mach-O x86_64 |

No toolchain other than conda-forge `zig` is involved in any row.

The macOS rows work because the backend disables rattler-build's binary
relocation when cross-compiling for macOS from a non-mac machine:
rattler-build's Mach-O post-processing needs `install_name_tool`/`codesign`
(macOS-only; its builtin relinker cannot add the default `lib/` rpath), and
zig links and ad-hoc-signs its artifacts itself. The `binary-relocation`
config option overrides this in either direction.

The hello-zig example also demonstrates zon-based metadata: its
`[package]` table declares no name or version — the backend reads them
from `build.zig.zon` (`.name`/`.version`), the way the Rust backend reads
Cargo.toml. The package is `hello_zig-0.2.0-*.conda` (zon names are zig
identifiers, so no hyphens); zlib-zig keeps explicit `[package]` metadata
to cover the declared mode.

### examples/zlib-zig — conda host dependencies

A zig executable whose C part `#include <zlib.h>`s and links libz, both
resolved from the conda host environment through the backend's
`--search-prefix`. Verified (same build machine):

| target | result | linkage |
|---|---|---|
| linux-64 (native) | ✅ builds, runs in the pixi env | `NEEDED libz.so.1`, `RPATH $ORIGIN/../lib`, glibc symbols ≤ 2.28 |
| linux-aarch64 (cross) | ✅ builds | same, aarch64 |
| win-64 (cross) | ✅ builds | imports `zlib.dll`, `Library/bin/` layout |
| osx-arm64 / osx-64 (cross) | ✅ builds | libz linked **statically** (see below), only `/usr/lib/libSystem` loaded, signed |

Two findings baked into the example:

- conda-forge names the import library `zlib` on Windows and `z` elsewhere;
  `build.zig` picks per target.
- **zig 0.16's Mach-O linker drops `-rpath`**: no `LC_RPATH` is emitted even
  by a minimal `zig cc -target aarch64-macos -Wl,-rpath,...` link (ELF
  targets keep theirs; zig uses LLD for ELF/COFF but its own self-hosted
  linker for Mach-O — upstream zig issue candidate). Combined with
  relocation being skipped on cross builds, a dynamic libz would be
  unresolvable at runtime on macOS, so the example links libz statically
  there (`preferred_link_mode = .static`) — the conda host env ships
  `libz.a`. This mirrors what r-zig-pixi found independently: its build
  leaves "all Mach-O rpath/codesign surgery" to a post-build script.

### examples/zon-dep-zig — build.zig.zon dependencies

An executable importing a module from a **vendored path dependency**
(`.greeter = .{ .path = "vendor/greeter" }`) — fully offline and hermetic,
the recommended way to consume zig packages in conda build environments.
Its `[package]` table is empty too (metadata from zon). Verified: native
build + run, win-64 cross.

URL dependencies were also tested empirically: the build environment is
not network-sandboxed, so `zig build` fetches them during the build
(content still pinned by the zon `hash`). Works, but makes the build
depend on the URL being reachable — vendor for reproducibility.

### examples/greet-zig — shared-library producer → consumer

`libgreet` is a zig-built **shared library** package (`lib/libgreet.so`,
`include/greet.h`; on Windows `Library/bin/greet.dll` +
`Library/lib/greet.lib` — zig produces the conda-conventional layout by
itself). `greet-cli` links it as a **path host-dependency**: pixi builds the
producer through the backend first, the consumer links it via
`--search-prefix`, and both publish jointly as a self-contained set
(`publish = true` + workspace-level `pixi publish`). Verified: native
build + run (`hello from libgreet on x86_64-linux`, `RPATH $ORIGIN/../lib`,
`SONAME libgreet.so`), win-64 cross of the whole chain.

Found along the way: pixi's `[package.run-exports]` propagates a source
path with one extra `../` for path packages, so the consumer declares an
explicit run-dependency instead — see
`docs/upstream/pixi-run-exports-path.md` for the full analysis.

## Usage

The backend is not published to any channel yet, so builds point pixi at a
locally built binary via `PIXI_BUILD_BACKEND_OVERRIDE`:

```sh
pixi run build-backend          # cargo build -p pixi-build-zig in ../pixi
pixi run build-hello            # native build of examples/hello-zig
pixi run cross-hello-aarch64    # cross builds from this machine
pixi run cross-hello-win64
pixi run verify                 # extract dist/*.conda, report binary formats
```

Requires the fork checkout at `../pixi` (branch `feat/pixi-build-zig`).

## CI

`.github/workflows/matrix.yml` rebuilds the backend from the fork branch,
builds the full ten-artifact matrix on one linux runner, checks every
binary's format and layout, then **executes** the cross-built artifacts
where it can: natively in a pixi env on linux, under qemu for
linux-aarch64, on a real macOS arm64 runner (which also validates zig's
ad-hoc code signature — macOS kills invalidly signed binaries), and on a
Windows runner with `zlib.dll` provided via `pixi exec`.

## Known gaps / next steps

- **macOS cross with conda dylib deps**: with relocation skipped, binaries
  that link dylibs from conda host dependencies keep absolute prefix paths;
  build those on a mac, or extend rattler-build's builtin relinker to
  handle rpath addition (upstream issue candidate).
- **Debug info**: zig does not strip by default (`.pdb` on Windows,
  `debug_info` in ELF); consider a `strip` config option.
- **`build.zig.zon` dependencies**: build environments are offline; needs a
  vendoring/`--fetch` story.
- **zig Mach-O linker `-rpath`**: report the dropped `LC_RPATH` upstream to
  ziglang (minimal repro in the README section above).
