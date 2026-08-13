#!/usr/bin/env bash
# Extract every .conda in dist/ and report the payload layout and binary
# formats, so a cross-compile run can be verified at a glance.
set -euo pipefail

dist_dir="${1:-dist}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

shopt -s nullglob
condas=("$dist_dir"/*.conda)
if [ ${#condas[@]} -eq 0 ]; then
    echo "no .conda artifacts in $dist_dir/" >&2
    exit 1
fi

for conda in "${condas[@]}"; do
    rm -rf "$tmp/x" && mkdir -p "$tmp/x"
    python3 - "$conda" "$tmp/x" <<'EOF'
import sys, zipfile
zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])
EOF
    tar --zstd -xf "$tmp"/x/pkg-*.tar.zst -C "$tmp/x"
    echo "== $(basename "$conda")"
    (cd "$tmp/x" && find . -type f \
        -not -name "*.tar.zst" -not -name "metadata.json" -not -path "./info/*" \
        | sort | while read -r f; do
            printf '   %s\n      %s\n' "$f" "$(file -b "$f")"
        done)
done
