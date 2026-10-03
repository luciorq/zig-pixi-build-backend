#!/usr/bin/env bash
# Full-surface drift test for the backend's configuration options.
# Builds examples/options-zig natively (linux-64) through the backend and
# asserts that every `[package.build.config]` option had its EFFECT, not
# just that the build succeeded. Run via `pixi run demo-options`, which
# supplies PIXI_BUILD_BACKEND_OVERRIDE.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
ex="$root/examples/options-zig"
dist="$root/dist"
log="$(mktemp)"; tmp="$(mktemp -d)"
trap 'rm -rf "$log" "$tmp"' EXIT

fail=0
check() { # check <description> <command...>
    local desc="$1"; shift
    if "$@" > /dev/null 2>&1; then echo "PASS  $desc"; else echo "FAIL  $desc"; fail=1; fi
}

# Force a real build so the log and the work directory are fresh (pixi
# otherwise serves the cached artifact without invoking the backend).
rm -rf "$ex/.pixi/bld" "$ex/.pixi/artifacts-v0" "$dist"/options_zig-*.conda
mkdir -p "$dist"
echo "== building examples/options-zig (log: $log)"
if ! pixi publish --path "$ex" --target-dir "$dist" > "$log" 2>&1; then
    echo "BUILD FAILED"; tail -40 "$log"; exit 1
fi

echo "== build log"
check "extra-args: -Dgreeting=drift reached zig build"          grep -F -- '-Dgreeting=drift' "$log"
check "cpu: -Dcpu=x86_64_v2"                                     grep -F -- '-Dcpu=x86_64_v2' "$log"
check "optimize: -Doptimize=ReleaseSafe"                         grep -F -- '-Doptimize=ReleaseSafe' "$log"
check "env: OPTIONS_ZIG_DEMO=drift-test visible in the build"    grep -F 'OPTIONS_ZIG_DEMO=drift-test' "$log"

# The exact generated build script (the log wraps long lines and bash's
# trace re-quotes exports, so assert flags and exports against the file).
script="$(ls "$ex"/.pixi/bld/options_zig/*/work/conda_build.sh 2>/dev/null | head -1)"
echo "== generated build script: ${script:-NOT FOUND}"
check "glibc-version: -Dtarget=x86_64-linux-gnu.2.31"            grep -F -- '-Dtarget=x86_64-linux-gnu.2.31' "$script"
check "export-c-toolchain: CC exported with the same target"     grep -F 'export CC="zig cc -target x86_64-linux-gnu.2.31 -mcpu=x86_64_v2"' "$script"
check "export-c-toolchain: CXX/AR/RANLIB exported"               bash -c "grep -qF 'export CXX=\"zig c++' '$script' && grep -qF 'export AR=\"zig ar\"' '$script' && grep -qF 'export RANLIB=\"zig ranlib\"' '$script'"
check "shared-global-cache=false: per-build global cache export" grep -F 'export ZIG_GLOBAL_CACHE_DIR="$SRC_DIR/.zig-global-cache"' "$script"
check "toolchain-package=zig: plain zig on the build PATH"       bash -c "ls '$ex'/.pixi/bld/options_zig/*/bld/bin/zig >/dev/null"

echo "== work directory"
check "shared-global-cache=false: .zig-global-cache under .pixi/bld" \
    bash -c "find '$ex/.pixi/bld' -type d -name .zig-global-cache | grep -q ."

echo "== artifact"
check "ignore-zon-manifest: package named from [package] (options_zig 0.3.0)" \
    bash -c "ls '$dist'/options_zig-0.3.0-*.conda"
check "ignore-zon-manifest: zon name/version NOT used" \
    bash -c "! ls '$dist'/*not_the_package_name* '$dist'/*9.9.9* 2>/dev/null | grep -q ."
python3 "$root/scripts/extract-conda.py" --find "$dist" --name options_zig --subdir linux-64 "$tmp/pkg" > /dev/null
bin="$tmp/pkg/bin/options-zig"
check "binary installed at bin/options-zig" test -x "$bin"
check "dynamic glibc (NEEDED libc.so.6)" bash -c "readelf -d '$bin' | grep -q 'libc.so.6'"
max_glibc="$(readelf -V "$bin" | grep -oE 'GLIBC_[0-9.]+' | sort -uV | tail -1)"
echo "      highest glibc symbol version: ${max_glibc:-none}"
check "glibc-version: no symbol above GLIBC_2.31" \
    test "$(printf '%s\n' "$max_glibc" GLIBC_2.31 | sort -V | tail -1)" = "GLIBC_2.31"
# main.zig calls gettid() (glibc 2.30): unlinkable against the 2.28 default,
# so its presence proves the raised target took effect.
check "glibc-version: gettid@GLIBC_2.30 linked (above the 2.28 default)" \
    test "$max_glibc" = "GLIBC_2.30"
check "binary-relocation=true: rattler-build relinked (RPATH/RUNPATH present)" \
    bash -c "readelf -d '$bin' | grep -qE 'RPATH|RUNPATH'"

echo "== run"
out="$(pixi run --manifest-path "$ex/pixi.toml" -q options 2>&1 | tail -1)"
echo "      $out"
check "runs: greeting from -D option"            grep -F 'greeting=drift' <<< "$out"
check "runs: ReleaseSafe baked in"               grep -F 'optimize=ReleaseSafe' <<< "$out"
check "runs: cpu model x86_64_v2"                grep -F 'cpu=x86_64_v2' <<< "$out"
check "runs: env value baked in"                 grep -F 'env=drift-test' <<< "$out"
check "runs: banner from extra-input-globs asset" grep -F 'banner=drift-banner' <<< "$out"
check "runs: linux-64 target"                    grep -F 'target=x86_64-linux' <<< "$out"
check "runs: gettid() worked"                    grep -F 'tid_ok=true' <<< "$out"

[ $fail = 0 ] && echo "ALL CHECKS PASSED" || { echo "SOME CHECKS FAILED"; exit 1; }
