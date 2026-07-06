# mac-forks

Git tools for tracking classic Mac OS files that live in their **resource
fork** rather than their data fork — project files, ResEdit resource files,
anything from the Symantec/THINK C / CodeWarrior / MPW era.

New to this? [SETUP.md](SETUP.md) is a step-by-step checklist for adding it
to a fresh repo. This README explains what it does and why.

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

## Classic Mac text (`mactext`)

Separately from resource forks, classic Mac OS text files have two
properties that break modern git tooling and GitHub's viewer:

- Lines are separated by a bare **CR** (0x0D), not LF — git's own
  line-ending handling (`core.autocrlf`, `text=auto`, `eol=`) only
  understands LF and CRLF, so it can't help, and a diff (or GitHub's blob
  view) of a CR-only file just renders as one giant line.
- The encoding is **Mac OS Roman**, not UTF-8 — so anything above ASCII
  (curly quotes, em dashes, accented letters, ©) is a *different character*
  if read back as UTF-8 or Latin-1. Byte `0xD4` is a left curly quote in Mac
  Roman but shows up as `Ô` if something reads it as Latin-1/UTF-8 instead
  — which is exactly what GitHub's viewer does, since it doesn't know the
  file is Mac Roman.

`mactext-clean`/`mactext-smudge` fix both together (git only allows one
`filter=` per path, so this can't be two independent filters layered on the
same files): clean converts Mac Roman → UTF-8 then CR → LF, so the *stored*
blob is ordinary, correctly-rendering, diffable text; smudge reverses both
so the working copy still has genuine Mac Roman, CR-only text.

Unlike the resource-fork tools, this has no forks or races to worry about —
it's a plain stdin/stdout content transform (`iconv` + `tr`), so it's wired
as an ordinary git filter rather than a hook. `iconv`/`tr` ship with base
macOS, no Xcode Command Line Tools required for this part specifically.

Add it to whichever extensions your project's classic Mac source uses, in
your own `.gitattributes` (see [SETUP.md](SETUP.md)):

```
*.c filter=mactext -text
*.h filter=mactext -text
```

## Requirements

macOS with the Xcode Command Line Tools installed (`xcode-select --install`),
for `/usr/bin/binhex`, `/usr/bin/DeRez`, `/usr/bin/Rez`, `/usr/bin/SetFile`
(needed for the resource-fork tools; `mactext` alone doesn't need these).

## Using this in a project

This repo is meant to be vendored via `git subtree`, at the fixed path
`tools/mac-forks/` (the scripts assume that path — they don't work run from
anywhere else). For adding it to a project for the first time, see
[SETUP.md](SETUP.md). Quick reference for a project that already has it:

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
- `mactext` assumes the *only* control characters in the text are line
  breaks — if a file legitimately embeds a raw CR byte as data rather than a
  line break, it'll get converted anyway (the same risk any line-ending
  normalization takes; git's own `core.autocrlf` has the identical issue for
  CRLF). And Mac Roman can't represent all of Unicode: if a file gets edited
  with a modern tool and picks up a character outside Mac Roman's repertoire
  (an emoji, say), `mactext-clean`'s reverse conversion on the next checkout
  will fail rather than silently corrupt anything — `iconv` errors out on
  unencodable characters instead of guessing.
