#!/usr/bin/env python3
"""Extract .conda packages (a zip of zstd tarballs) without relying on a
zstd-capable tar — works the same on linux, macOS and Windows runners.

Usage:
  extract-conda.py <pkg.conda> <dest>
  extract-conda.py --find <dist-dir> --name <pkg-name> --subdir <platform> <dest>

The --find form scans <dist-dir>/*.conda, reads each package's
info/index.json, and extracts the one matching --name/--subdir (the build
hash in the filename is not predictable, so filenames alone cannot identify
a platform).
"""

import argparse
import glob
import io
import json
import os
import sys
import tarfile
import zipfile

import zstandard


def open_payload(z: zipfile.ZipFile, prefix: str) -> tarfile.TarFile:
    name = next(
        n for n in z.namelist() if n.startswith(prefix) and n.endswith(".tar.zst")
    )
    data = zstandard.ZstdDecompressor().decompress(
        z.read(name), max_output_size=1 << 31
    )
    return tarfile.open(fileobj=io.BytesIO(data))


def read_index(conda: str) -> dict:
    with zipfile.ZipFile(conda) as z:
        with open_payload(z, "info-") as t:
            return json.load(t.extractfile("info/index.json"))


def extract(conda: str, dest: str) -> None:
    os.makedirs(dest, exist_ok=True)
    with zipfile.ZipFile(conda) as z:
        with open_payload(z, "pkg-") as t:
            try:
                t.extractall(dest, filter="data")
            except TypeError:  # python < 3.12
                t.extractall(dest)


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("source", help=".conda file, or a directory with --find")
    p.add_argument("dest")
    p.add_argument("--find", action="store_true")
    p.add_argument("--name")
    p.add_argument("--subdir")
    args = p.parse_args()

    if not args.find:
        extract(args.source, args.dest)
        print(f"extracted {args.source} -> {args.dest}")
        return 0

    for conda in sorted(glob.glob(os.path.join(args.source, "*.conda"))):
        idx = read_index(conda)
        if args.name and idx.get("name") != args.name:
            continue
        if args.subdir and idx.get("subdir") != args.subdir:
            continue
        extract(conda, args.dest)
        print(f"extracted {conda} ({idx.get('name')}/{idx.get('subdir')}) -> {args.dest}")
        return 0

    print(
        f"no package matching name={args.name} subdir={args.subdir} in {args.source}",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
