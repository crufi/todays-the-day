# mac-forks

Git tools for tracking classic Mac OS files that live in their **resource
fork** rather than their data fork — project files, ResEdit resource files,
anything from the Symantec/THINK C / CodeWarrior / MPW era.

## The problem

Git only ever sees a file's data fork. A Symantec C++ project (`.π`) or a
ResEdit resource-only file (`.rsrc`) typically has an **empty data fork** —
everything that matters lives in the resource fork, which git has no concept
of at all. `git add` such a file and you silently commit nothing.

## The approach

Two scripts, driven entirely by file *shape* — never by filename, so this
directory can be dropped into any vintage Mac project unchanged:

- **`export.sh`** scans the working tree for files with a non-empty resource
  fork and encodes each one to a plain-text sidecar that git can actually
  store and diff:
  - a `*.rsrc`-named file (case-insensitive) with an **empty data fork** is
    decompiled with `DeRez` to `<name>.r`. Since `DeRez` only knows about the
    resources themselves — not the file's own Finder type/creator — that's
    captured separately as a human-readable leading comment, e.g.
    `/* mac-forks: type=rsrc creator=RSED */`.
  - anything else with a resource fork is archived with `binhex encode` to
    `<name>.hqx` — self-contained (data fork + resource fork + type/creator
    all round-trip in one step).

  The real, fork-bearing files are gitignored (`export.sh` maintains a
  generated block in `.gitignore` automatically) and never tracked directly.

- **`import.sh`** does the reverse: finds `.hqx`/`.r` sidecars and
  reconstitutes the real files from them, restoring the resource fork and
  Finder type/creator exactly.

Both are wired up as git hooks (see `install.sh`):

| Hook | Runs | Why |
|---|---|---|
| `pre-commit` | `export.sh` | keeps the tracked sidecars in sync with whatever real files exist before every commit |
| `post-checkout` | `import.sh` | rebuilds real files after `checkout`/`clone`/`switch` |
| `post-merge` | `import.sh` | rebuilds real files after `merge`/`pull` (a fetch+merge doesn't go through checkout, so this needs its own hook) |

Because the real files are gitignored rather than tracked, `import.sh` writes
them directly — there's no tracked path for git's own checkout machinery to
be racing against.

## Requirements

macOS with the Xcode Command Line Tools installed (`xcode-select --install`),
for `/usr/bin/binhex`, `/usr/bin/DeRez`, `/usr/bin/Rez`, `/usr/bin/SetFile`.

## Using this in a project

This repo is meant to be vendored via `git subtree`, at the fixed path
`tools/mac-forks/` (the scripts assume that path — they don't work run from
anywhere else).

First time in a given project:

```sh
git remote add mac-forks https://github.com/crufi/mac-forks.git
git subtree add --prefix=tools/mac-forks mac-forks main --squash
sh tools/mac-forks/install.sh
```

`install.sh` checks for the required tools, symlinks the hooks into
`.git/hooks`, and runs `import.sh` once immediately.

Pulling in later improvements:

```sh
git subtree pull --prefix=tools/mac-forks mac-forks main --squash
```

Pushing a fix you made in-place back upstream:

```sh
git subtree push --prefix=tools/mac-forks mac-forks main
```

## Known limitations

- `DeRez`/`Rez` don't round-trip byte-for-byte — Rez recompiles a
  semantically equivalent resource fork, not necessarily identical bytes.
  Fine for ResEdit/an IDE/a linker; don't expect `cmp` to agree after a round
  trip.
- The `.r` path only ever produces an empty data fork on import (that's the
  only case it's used for: `*.rsrc`-named files with an empty data fork to
  begin with). If a resource-fork-bearing file also has real data-fork
  content, it always goes through the BinHex (`.hqx`) path instead, which is
  fully fork-agnostic.
- Hooks are local to each clone (`.git/hooks` is never populated by `git
  clone`) — every clone needs to run `install.sh` once. Until then, the repo
  is still completely valid; the fork-bearing files just stay as their
  `.hqx`/`.r` sidecars, unexpanded.
