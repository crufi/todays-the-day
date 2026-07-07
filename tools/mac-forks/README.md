# mac-forks

Git tools for tracking classic Mac OS files that mainly live in their **resource
fork** rather than their data fork — project files, ResEdit resource files,
anything from the Symantec/THINK C/CodeWarrior/MPW era.

New to this? [SETUP.md](SETUP.md) is a step-by-step checklist for adding it
to a fresh repo. This README explains what it does and why.

## The problem

Git only ever sees a file's data fork. A Symantec C++ project (`.π`) or a
ResEdit resource-only file (`.rsrc`) typically has an empty data fork —
everything that matters lives in the resource fork, which git has no concept
of at all. `git add` such a file and you silently commit nothing.

## The approach

Two scripts, driven entirely by file attributes (not stricly filenames, so this
directory can be dropped into any vintage Mac project unchanged):

- **`export.sh`** scans the working tree for files with a non-empty resource
  fork and encodes each one to a plain-text sidecar that git can actually
  store and diff:
  - a **`*.rsrc`-named file (case-insensitive) with an empty data fork** is
    decompiled with `DeRez` to `<name>.r`. Since `DeRez` only knows about the
    resources themselves — not the file's own Finder type/creator — that's
    captured separately as a human-readable leading comment, e.g.
    `/* mac-forks: type=rsrc creator=RSED */`.
  - **anything else with a resource fork** is archived with `binhex encode` to
    `<name>.hqx` — self-contained (data fork + resource fork + type/creator
    all round-trip in one step). (We prefer binhex here to the more space-efficient
    MacBinary format just for github display nicety.)

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
properties that break modern git tools and GitHub's viewer:

- Lines are separated by a bare CR (0x0D), not LF — git's own
  line-ending handling (`core.autocrlf`, `text=auto`, `eol=`) only
  understands LF and CRLF, so it can't help, and a diff (or GitHub's blob
  view) of a CR-only file just renders as one giant line.
- The encoding is MacRoman, not UTF-8 — so anything above ASCII
  (curly quotes, em dashes, accented letters, ©) is the wrong character
  if read back as UTF-8 or Latin-1. (Byte `0xD4` is a left curly quote in Mac
  Roman but shows up as `Ô` if something reads it as Latin-1/UTF-8 instead
  — which is exactly what GitHub's viewer does, since it doesn't know the
  file is MacRoman.)

`mactext-clean`/`mactext-smudge` fix both together (git only allows one
`filter=` per path, so this can't be two independent filters layered on the
same files): clean converts MacRoman → UTF-8 then CR → LF, so the stored
blob is ordinary, correctly-rendering, diffable text; smudge reverses both
so the working copy still has genuine Mac Roman, CR-only text.

Unlike the resource-fork tools, this has no forks or races to worry about —
it's a plain stdin/stdout content transform (`iconv` + `tr`), so it's wired
as an ordinary git filter rather than a hook. (`iconv`/`tr` ship with base
macOS, no Xcode Command Line Tools required for this part specifically.)

`mactext-clean` also captures the file's current Finder type/creator, if it
has one, as a human-readable leading comment:

```
/* auto-generated (do not modify): type=TEXT creator=KAHL hex=544558544B41484C... */
```

Where that ever comes from: these files don't normally carry Finder info at
all (most editors don't preserve xattrs) -- but the *first* time one is
checked in, it's expected to have been pulled straight off a real vintage
volume (e.g. via `hcopy`), which is exactly when it'd have a meaningful
type/creator to capture. Once captured, it's carried forward automatically:
if a later commit has no live Finder info (the common case), the previous
value already in the comment is preserved rather than silently dropped.

Restoring it on checkout does **not** happen inside `mactext-smudge` --
same reasoning as the resource-fork tools: a smudge filter's stdout *is* the
file content git writes, so it can't safely side-effect the same path's
Finder info too. Instead `import.sh` does it as a separate pass, once git has
already checked the file out, reading the marker from the tracked blob
(always LF, guaranteed by `mactext-clean`) rather than the working-tree copy
(which is genuinely CR-only after smudge, so ordinary `head`/`sed` can't
pull "just the first line" back out of it).

Add it to whichever extensions your project's classic Mac source uses, in
your own `.gitattributes` (see [SETUP.md](SETUP.md)):

```
*.c filter=mactext -text
*.h filter=mactext -text
```

### `macroman` — the encoding half alone, for `.r` sidecars

`export.sh`'s own DeRez-generated `.r` sidecars need the Mac-Roman-encoding
fix too — DeRez's hex-dump comments embed raw bytes straight from the
resource fork, and for text-bearing resources (`STR#`, `vers`, an owner-name
resource, etc.) those bytes are genuine Mac Roman prose that renders wrong on
GitHub, the same as any other Mac Roman byte would.

But they do **not** need (and must not get) the CR↔LF half: DeRez always
emits LF-terminated output on this machine, right now — it's a live tool's
output, not a persisted vintage file, so there's no CR convention to
preserve. Running `mactext` on a `.r` sidecar would wrongly inject CR line
endings into it and break `import.sh`'s own `head -n 1` parsing of its
leading type/creator comment (which assumes LF). Confirmed empirically: an
encoding-only round trip matches byte-for-byte; adding CR↔LF conversion
turned the whole file into a single line.

So `.r` sidecars get their own filter, `macroman`, which is exactly
`mactext-clean`/`-smudge` minus the `tr` step — Mac Roman ↔ UTF-8 only,
line endings untouched:

```
*.r filter=macroman -text
```

## Requirements

macOS with the Xcode Command Line Tools installed (`xcode-select --install`),
for `/usr/bin/binhex`, `/usr/bin/DeRez`, `/usr/bin/Rez`, `/usr/bin/SetFile`
(for the resource-fork tools only, not mactext).

## Using this in a project

This repo is meant to be vendored via `git subtree`, at the fixed path
`tools/mac-forks/` (the scripts assume that path — they don't work run from
anywhere else). For adding it to a project for the first time, see
[SETUP.md](SETUP.md). Quick reference for a project that already has it:

Pulling in later mac-forks improvements:

```sh
git subtree pull --prefix=tools/mac-forks mac-forks main --squash
```

Pushing a change you made in-place back upstream:

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
  clone`) — **every clone needs to run `install.sh` once**. Until then, the repo
  is still completely valid; the fork-bearing files just stay as their
  `.hqx`/`.r` sidecars, unexpanded.
- `mactext` assumes the *only* control characters in the text are line
  breaks.
- MacRoman can't represent all of Unicode: if a file gets edited
  with a modern tool and picks up a character outside MacRoman's repertoire
  (an emoji, say), `mactext-clean`'s reverse conversion on the next checkout
  will fail with an error — `iconv` errors out on
  unencodable characters instead of guessing.
