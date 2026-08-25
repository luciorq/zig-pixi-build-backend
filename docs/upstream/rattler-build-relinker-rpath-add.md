# Draft issue for prefix-dev/rattler-build — builtin Mach-O relinker cannot add `LC_RPATH`, breaking macOS cross-builds on non-mac hosts

Status: DRAFT, not yet filed. Evidence gathered 2026-08-13/14 against
`rattler_build_core` 0.2.10 (as embedded in `pixi_build_backend` in the
prefix-dev/pixi monorepo).

## Title

builtin Mach-O relinker: support adding load commands (`LC_RPATH`) so
macOS cross-builds do not require `install_name_tool`

## Summary

Cross-compiling a package *for* macOS *from* a linux (or Windows) build
machine fails in post-processing with:

```
Relinking "<binary>" (install_name_tool)
Error:   × failed to find `install_name_tool` (cannot find binary path)
```

even for a self-contained binary with no prefix references at all. The
builtin (pure-Rust) Mach-O relinker exists and handles in-place rewrites,
and `RATTLER_BUILD_BUILTIN_CODESIGN=1` provides pure-Rust re-signing — the
one missing piece is *adding* a load command, which the default rpath
policy needs on every Mach-O binary.

## Mechanism (rattler_build_core 0.2.10)

1. `post_process/relink.rs::relink` runs for every binary when
   `binary_relocation` is enabled (the default).
2. `dynamic_linking.rpaths` defaults to `["lib/"]`; for a Mach-O binary
   that does not already carry that rpath, `macos/link.rs::MachO::relink`
   computes an rpath **addition** (`change_rpath: None -> Some(...)`).
3. The builtin relinker refuses anything but same-or-shrinking in-place
   edits:

   ```rust
   // macos/link.rs
   let can_deal_with_rpath = changes.change_rpath.iter().all(|(old, new)| {
       old.is_some() && new.is_some() && old_len >= new_len
   });
   if !can_deal_with_rpath { return Err(RelinkError::BuiltinRelinkFailed); }
   ```

4. The fallback shells out to `install_name_tool`
   (`macos/link.rs::install_name_tool`), which only exists on macOS, so the
   build fails on a linux host.

Because zig/clang-produced cross binaries typically carry **no** rpaths,
step 2 triggers for essentially every cross-built Mach-O — making this the
single blocker for fully-working macOS cross-builds (codesigning is already
solved by `RATTLER_BUILD_BUILTIN_CODESIGN`, which works: relinked binaries
re-signed in pure Rust run fine on Apple Silicon).

## Reproduction

Any `pixi build --target-platform osx-arm64` (or direct rattler-build
cross build) of a recipe producing a Mach-O binary, on a linux machine
without `install_name_tool`. Observed with a plain zig executable whose
only load commands were `/usr/lib/libSystem.B.dylib` + an ad-hoc
`LC_CODE_SIGNATURE`.

## Suggested fix

Teach the builtin relinker to add `LC_RPATH` load commands. Mach-O leaves
padding between the end of the load commands and the first section for
exactly this purpose — it is how `install_name_tool -add_rpath` itself
works (when the padding is insufficient it errors; `-headerpad` /
`-headerpad_max_install_names` at link time enlarges it). Sketch:

- compute free space: `sizeofcmds` vs offset of the first section in
  `__TEXT`;
- if the new `rpath_command` (cmdsize = 12 + padded path) fits, append it,
  bump `ncmds`/`sizeofcmds` in the header, zero the gap;
- else fall back to `install_name_tool` as today (a mac host), or fail
  with a clear message mentioning headerpad.

Deletion support could work the same way in reverse (compact + decrement),
which would remove the other `install_name_tool` dependency.

## Workarounds in use today

- `pixi-build-zig` (in development) sets `binary_relocation: false` when
  cross-compiling for macOS from a non-mac machine — correct for
  self-contained binaries, but forfeits relocation for binaries that
  reference host-prefix dylibs.
- Statically linking conda host libraries on macOS targets.

## Related

- rattler-build docs already cover the codesign half:
  https://rattler-build.prefix.dev/dev/compilers/#builtin-codesigning-for-macos-cross-compilation
- A zig-side bug compounds the situation (zig's Mach-O linker drops
  `-rpath` entirely), tracked separately — but the rattler-build fix is
  independently valuable for all compilers.
