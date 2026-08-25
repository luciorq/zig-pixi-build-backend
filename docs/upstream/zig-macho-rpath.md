# Draft issue for ziglang/zig — Mach-O linker silently drops `-rpath` (no `LC_RPATH` emitted)

Status: DRAFT, not yet filed. Evidence gathered 2026-08-13/14 on linux-64
with conda-forge zig 0.16.0.

## Title

self-hosted Mach-O linker does not emit `LC_RPATH` for `-rpath` (all
optimize modes, `zig cc` and `zig build-exe`)

## Summary

When targeting macOS, the linker accepts `-rpath` (via `zig build-exe
-rpath`, `zig cc -Wl,-rpath,...`, or `std.Build.Module.addRPathSpecial`)
without error, but the produced Mach-O contains no `LC_RPATH` load command.
The same invocation targeting ELF (linked by LLD) emits the expected
`DT_RUNPATH`, so this is specific to the self-hosted Mach-O linker.

## Reproduction (from a linux-64 host, zig 0.16.0)

Minimal C case:

```sh
$ echo 'int main(void){return 0;}' > t.c
$ zig cc -target aarch64-macos -o t-mac t.c -Wl,-rpath,@loader_path/../lib
$ # otool -l t-mac | grep -A2 LC_RPATH   (on a mac)
$ # -> no LC_RPATH present (verified by parsing load commands directly)
```

Zig case, showing the optimize mode is irrelevant:

```sh
$ printf 'pub fn main() void {}\n' > t.zig
$ for mode in Debug ReleaseSafe ReleaseFast; do
    zig build-exe t.zig -target aarch64-macos -O $mode \
        -rpath @loader_path/../lib --name t-$mode
  done
# LC_RPATH count in every produced binary: 0
```

Control (same flags, ELF target — rpath survives):

```sh
$ zig cc -target x86_64-linux-gnu.2.28 -o t-elf t.c '-Wl,-rpath,$ORIGIN/../lib'
$ readelf -d t-elf | grep RUNPATH
 0x000000000000001d (RUNPATH)            Library runpath: [$ORIGIN/../lib]
```

Build-system case: `mod.addRPathSpecial("@loader_path/../lib")` on the root
module of an executable — `std.Build.Step.Compile` does forward it as
`-rpath @loader_path/../lib` (verified in
`std/Build/Module.zig` `appendZigProcessFlags`), and the binary still has
no `LC_RPATH`, so the drop happens inside the linker, not the build system.

A load-command dump of an affected binary that links a dylib via `@rpath`
(so the rpath is definitely "used"):

```
LC_LOAD_DYLIB: @rpath/libz.1.dylib
LC_LOAD_DYLIB: /usr/lib/libSystem.B.dylib
LC_CODE_SIGNATURE: present
(no LC_RPATH)
```

## Expected

An `LC_RPATH` load command per `-rpath` argument, as ld64 and lld-macho
produce.

## Impact

Cross-compiled macOS binaries cannot resolve dylib dependencies whose
install names use `@rpath/...` — which is the convention for relocatable
package ecosystems (conda/conda-forge, Homebrew). In the conda case,
packaged dylibs have `@rpath/libfoo.dylib` install names and the consuming
binary is expected to carry `LC_RPATH @loader_path/../lib`; with zig that
rpath silently vanishes, so the binary builds and signs fine but dies at
dyld time. Workarounds in use: linking such dependencies statically, or
post-processing with `install_name_tool` on a mac.

## Notes

- Only tested cross (linux-64 build machine → `aarch64-macos` /
  `x86_64-macos` targets). Worth confirming on a native macOS host, though
  the linker code path should be the same.
- Everything else about the produced binaries is healthy: they execute on
  real Apple Silicon (ad-hoc `LC_CODE_SIGNATURE` accepted by macOS
  signature enforcement — verified in CI on a macos-15 arm64 runner).
