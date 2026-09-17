# Zig upstream lives on Codeberg — GitHub `ziglang/*` is NOT maintained

**Read this before touching anything that points at Zig upstream.**

Since **2025-11-26** the Zig project hosts all of its official repositories
on **Codeberg**, under https://codeberg.org/ziglang. Every repository under
https://github.com/ziglang is a frozen leftover:

- `github.com/ziglang/zig` — description literally reads **"Moved to
  Codeberg"**; last push 2025-11-27; its `homepage` field points to the
  migration announcement
  (https://ziglang.org/news/migrating-from-github-to-codeberg/).
- Every other `github.com/ziglang/*` repo (`zig-bootstrap`, `translate-c`,
  `vscode-zig`, `zig.vim`, `zig-mode`, `zig-pypi`, `www.ziglang.org`,
  `release-cutter`, `qemu-static`, ...) is **archived**.
- `codeberg.org/ziglang/zig` receives commits daily (checked 2026-09-16;
  `zig-bootstrap`, `translate-c`, `arocc`, `zig-libc-abi`,
  `libc-abi-tools`, `ziglang.org`, `infra` all updated within the last
  month).

Verified 2026-09-16 with:

```sh
gh api repos/ziglang/zig --jq '{description, pushed_at, homepage}'
gh api 'orgs/ziglang/repos?per_page=100&sort=pushed' --jq '.[] | "\(.name)\t\(.archived)"'
curl -s 'https://codeberg.org/api/v1/orgs/ziglang/repos?limit=50'
```

## Practical consequences

| what you want | do NOT use | use instead |
|---|---|---|
| latest release / tag | GitHub releases or tags API (stops at 0.15.1 / 0.15.2) | https://ziglang.org/download/index.json |
| master snapshot tarballs | GitHub archive URLs | `https://ziglang.org/builds/zig-<version>.tar.xz` (listed in `index.json`) |
| source, commits, blame | `github.com/ziglang/zig` (frozen at 2025-11-27) | https://codeberg.org/ziglang/zig |
| issues / PRs / milestones | GitHub issues (read-only history) | https://codeberg.org/ziglang/zig/issues and `/pulls`, milestones at `/milestones` |
| filing a bug (e.g. `docs/upstream/zig-macho-rpath.md`) | GitHub | Codeberg issue tracker |
| CI checkout of zig sources | `actions/checkout` on `ziglang/zig` | tarball from `ziglang.org/builds` or a Codeberg clone |
| `build.zig.zon` dependency on a `ziglang/*` project | `https://github.com/ziglang/...` | `https://codeberg.org/ziglang/...` (or a release tarball) |
| Renovate / Dependabot / "latest zig" scripts | GitHub-based watchers (silently stale on 0.15.x) | poll `index.json` |

Notes:

- GitHub's `ziglang/zig` is **not** archived, so an automated check for
  `archived: true` will not catch it. Check the description or the
  `pushed_at` date instead.
- Third-party mirrors on GitHub may exist and may lag; treat them as
  unofficial.
- The conda-forge `zig-feedstock` already sources tarballs from
  `ziglang.org/builds` / `ziglang.org/download`, so it is unaffected.
- `gh` cannot query Codeberg. Use the Forgejo REST API:
  `https://codeberg.org/api/v1/repos/ziglang/zig/...` (e.g. `/releases`,
  `/tags`, `/issues?state=open`, `/milestones`).

## Codeberg API quick reference

```sh
# latest tags
curl -s 'https://codeberg.org/api/v1/repos/ziglang/zig/tags?limit=5' | jq -r '.[].name'
# open issues mentioning rpath
curl -s 'https://codeberg.org/api/v1/repos/ziglang/zig/issues?state=open&q=rpath&type=issues' | jq -r '.[] | "\(.number)\t\(.title)"'
# 0.17.0 milestone
curl -s 'https://codeberg.org/api/v1/repos/ziglang/zig/milestones?state=all' | jq -r '.[] | "\(.title)\t\(.open_issues) open / \(.closed_issues) closed"'
```
