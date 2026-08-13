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

## Known gaps / next steps

- **macOS cross with conda dylib deps**: with relocation skipped, binaries
  that link dylibs from conda host dependencies keep absolute prefix paths;
  build those on a mac, or extend rattler-build's builtin relinker to
  handle rpath addition (upstream issue candidate).
- **Debug info**: zig does not strip by default (`.pdb` on Windows,
  `debug_info` in ELF); consider a `strip` config option.
- **`build.zig.zon` dependencies**: build environments are offline; needs a
  vendoring/`--fetch` story.
- **Runtime execution of cross artifacts**: only the native binary was
  executed; qemu/wine smoke tests would close the loop.
- An example that links a conda host dependency (e.g. zlib) to exercise
  `--search-prefix` end to end.
