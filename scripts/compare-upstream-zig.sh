#!/usr/bin/env bash
# Build the linux-64 examples with the OFFICIAL zig tarball from ziglang.org
# (sha256-verified against download/index.json) and compare the resulting
# binaries with the conda-forge-zig-built artifacts in dist/. conda-forge
# patches its zig (see docs/conda-forge-zig-compiler.md, "Feedstock patches");
# this surfaces any behavioural drift on every run.
#
# Usage: compare-upstream-zig.sh [dist-dir]
# Env:   UPSTREAM_ZIG_VERSION (default 0.16.0), UPSTREAM_ZIG_CACHE
#        (default .cache/upstream-zig), CONDA_PREFIX (search prefix for
#        host libraries such as zlib; set automatically under `pixi run`).
#
# Exit status is non-zero only when an upstream build fails or an artifact
# is missing. NEEDED/size differences are reported, not failed: the
# conda-forge as-needed patch makes extra glibc entries the expected
# steady state.
set -euo pipefail

dist_dir="${1:-dist}"
version="${UPSTREAM_ZIG_VERSION:-0.16.0}"
cache="${UPSTREAM_ZIG_CACHE:-.cache/upstream-zig}"
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# --- fetch the official toolchain (ziglang.org only; GitHub is not upstream)
zig_dir="$cache/$version"
if [ ! -x "$zig_dir/zig" ]; then
    mkdir -p "$zig_dir"
    curl -sSL https://ziglang.org/download/index.json > "$tmp/index.json"
    read -r url sha < <(python3 - "$tmp/index.json" "$version" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))[sys.argv[2]]["x86_64-linux"]
print(d["tarball"], d["shasum"])
PY
)
    echo "fetching $url"
    curl -sSL -o "$tmp/zig.tar.xz" "$url"
    echo "$sha  $tmp/zig.tar.xz" | sha256sum -c -
    tar -xJf "$tmp/zig.tar.xz" -C "$zig_dir" --strip-components=1
fi
upstream_zig="$(cd "$zig_dir" && pwd)/zig"
echo "upstream zig: $("$upstream_zig" version) at $upstream_zig"

export ZIG_GLOBAL_CACHE_DIR="$tmp/gcache" ZIG_LOCAL_CACHE_DIR="$tmp/lcache"
# Same flags the backend derives for linux-64.
flags=(-Dtarget=x86_64-linux-gnu.2.28 -Dcpu=baseline -Doptimize=ReleaseFast)
search_prefix="${CONDA_PREFIX:-}"

# name:conda-package-name:source-dir[:extra search prefix relative to the upstream out dir]
examples=(
    "hello-zig:hello_zig:examples/hello-zig"
    "zon-dep-zig:zon_dep_zig:examples/zon-dep-zig"
    "zlib-zig:zlib-zig:examples/zlib-zig"
    "libgreet:libgreet:examples/greet-zig/libgreet"
    "greet-cli:greet-cli:examples/greet-zig/greet-cli:libgreet"
)

needed() { readelf -d "$1" 2>/dev/null | awk '/NEEDED/{gsub(/[\[\]]/,"",$5); print $5}' | sort | paste -sd' '; }
linker()  { readelf -p .comment "$1" 2>/dev/null | grep -oE 'Linker: [^(]*' | head -1; }

status=0
for entry in "${examples[@]}"; do
    IFS=: read -r name pkg src dep <<< "$entry"
    out="$tmp/upstream/$name"; mkdir -p "$out"
    args=("${flags[@]}")
    [ -n "$search_prefix" ] && args+=(--search-prefix "$search_prefix")
    [ -n "${dep:-}" ] && args+=(--search-prefix "$tmp/upstream/$dep")
    echo "== $name: upstream build"
    if ! "$upstream_zig" build --build-file "$root/$src/build.zig" --prefix "$out" --search-prefix "$out" "${args[@]}" > "$tmp/$name.log" 2>&1; then
        echo "   UPSTREAM BUILD FAILED"; tail -20 "$tmp/$name.log"; status=1; continue
    fi
    conda="$tmp/conda/$name"; mkdir -p "$conda"
    if ! python3 "$root/scripts/extract-conda.py" --find "$dist_dir" --name "$pkg" --subdir linux-64 "$conda" > /dev/null; then
        echo "   MISSING conda artifact for $pkg (linux-64) in $dist_dir"; status=1; continue
    fi
    while IFS= read -r rel; do
        u="$out/$rel"; c="$conda/$rel"
        if [ ! -e "$c" ]; then echo "   $rel: missing in conda artifact"; status=1; continue; fi
        printf '   %s\n' "$rel"
        printf '      upstream %8d bytes  %s  NEEDED: %s\n' "$(stat -c %s "$u")" "$(linker "$u")" "$(needed "$u")"
        printf '      conda    %8d bytes  %s  NEEDED: %s\n' "$(stat -c %s "$c")" "$(linker "$c")" "$(needed "$c")"
        if [ "$(needed "$u")" != "$(needed "$c")" ]; then
            printf '      NEEDED differs: only-conda={%s} only-upstream={%s}\n' \
                "$(comm -13 <(needed "$u" | tr ' ' '\n') <(needed "$c" | tr ' ' '\n') | paste -sd' ')" \
                "$(comm -23 <(needed "$u" | tr ' ' '\n') <(needed "$c" | tr ' ' '\n') | paste -sd' ')"
        fi
    done < <(cd "$out" && find bin lib -type f \( -perm -u+x -o -name '*.so*' \) 2>/dev/null | sort)
done
exit $status
