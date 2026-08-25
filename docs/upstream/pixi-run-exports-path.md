# Draft issue for prefix-dev/pixi — `[package.run-exports]` with path source packages resolves one directory too high

Status: DRAFT, not yet filed. Evidence gathered 2026-08-25 against pixi
0.76.2 (workspace features exercised through a pixi-build backend; the
behavior is in pixi itself, not the backend).

## Title

run-exports from a path source package propagate a source path with one
extra `../`, breaking consumer resolution

## Summary

When a path source package declares `[package.run-exports]` (any spec form
tried: `name = "*"` or `name = { path = "." }`), consumers that
host-depend on it fail to resolve the propagated run dependency: the
source path pixi stores for it points one directory too high.

## Reproduction

Workspace with a library package and a consumer:

```
greet-zig/
  pixi.toml            # workspace, [dependencies] greet-cli = { path = "greet-cli" }
  greet-cli/pixi.toml  # [package], host-dependencies libgreet = { path = "../libgreet" }
  libgreet/pixi.toml   # [package], [package.run-exports.weak] libgreet = { path = "." }
```

`pixi install` (or `pixi run` on any task) fails with:

```
× failed to resolve source package 'libgreet' (at '../../libgreet')
╰─▶ × failed to discover a valid project manifest, the source path
    '<...>/greet-zig/../libgreet' could not be found
```

The correct consumer-relative path would be `../libgreet`; the stored spec
is `../../libgreet` — exactly one `../` too many. The same off-by-one
reproduces in a nested layout (consumer at the workspace root, producer in
a subdirectory): declared host-dep path `libgreet`, propagated spec
`../libgreet`, resolved to a sibling of the workspace root.

Both `libgreet = "*"` and `libgreet = { path = "." }` in the run-exports
table produce identical results, so the bug is in how pixi re-anchors the
resolved producer location for the consumer, not in parsing the spec.

## Analysis

The propagated path is in every case what you would get by computing the
relative path with the anchor's **manifest file path treated as a
directory** (i.e. `greet-zig/greet-cli/pixi.toml` instead of
`greet-zig/greet-cli`): each layout gains exactly one spurious `..`
component. `pixi_spec::SourceAnchor::relativize_location` /
`resolve_location` both contain an `is_known_manifest_file` guard that
strips the filename — so some caller on the run-exports propagation path
appears to construct the anchor from a location that defeats that guard
(or performs the join/diff without going through `SourceAnchor`).

## Impact

`[package.run-exports]` — the conda-idiomatic way for a library package to
hand its runtime dependency to consumers — is unusable for path source
packages. Workaround: consumers declare the library explicitly in
`[package.run-dependencies]`, duplicating what run-exports should infer.

## Environment

- pixi 0.76.2, linux-64
- packages built with a pixi-build backend (pixi-build-zig, in
  development); the failure occurs during environment solving, before any
  backend involvement
