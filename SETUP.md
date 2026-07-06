# Setting Up a New Vintage Mac Git Repo

Quick checklist for starting a fresh git repo around a classic Mac project
(THINK C/Symantec C++/CodeWarrior/MPW era), using
[mac-forks](https://github.com/crufi/mac-forks) for resource forks and its
`mactext` filter for Mac Roman, CR-only text. See the [README](README.md) for
more details; this file is just a how-to.

macOS + Xcode Command Line Tools only (`xcode-select --install`) — that's
where `binhex`/`DeRez`/`Rez`/`SetFile` come from.

## 1. Init the repo

```sh
git init
```

## 2. Pull in mac-forks

```sh
git remote add mac-forks https://github.com/crufi/mac-forks.git
git subtree add --prefix=tools/mac-forks mac-forks main --squash
sh tools/mac-forks/install.sh
```

`install.sh` checks for the required tools, symlinks the `pre-commit` /
`post-checkout` / `post-merge` hooks, and configures the `mactext` filter.
**Every clone needs to run this once** — hooks and filter config live in
`.git/`, which `git clone` never populates.

## 3. Add `.gitattributes`

Not shipped by mac-forks itself — every project's extensions differ, so this
lives in your own repo, one pattern per line:

```
*.hqx -text
*.r -text

*.c filter=mactext -text
*.h filter=mactext -text
*.cp filter=mactext -text
*.cpp filter=mactext -text
*.hpp filter=mactext -text
```

Add more `filter=mactext -text` lines for whatever else your project has —
`.p`/`.pas` (Pascal), `.a`/`.asm`, etc.

⚠️ **Naming collision to watch for:** mac-forks generates `.r` sidecars for
resource-only files (`Foo.rsrc` → `Foo.rsrc.r`). If your project also has
genuine hand-written Rez source ending in `.r`, **rename them** (`.rez` or
similar instead of `.r`) before using mac-forks.

## 4. Normal `.gitignore` stuff

`export.sh` maintains its own generated block automatically (listing
whichever resource-fork-bearing files it finds) — leave that alone. You'll
still want the usual:

```
.DS_Store
```

## 5. Add your files, commit

Edit everything normally — including the real `.π`/`.rsrc` files directly in
ResEdit/the IDE. (`hfsutils` provides a great way to get vintage Mac files in/out
of an emulator disk image.) 

The `pre-commit` hook finds anything with a resource fork
and encodes it automatically; you never `git add` those files yourself.

```sh
git add .
git commit -m "Initial commit"
```

## 6. Verify with a genuinely fresh clone

Problems in this kind of setup mostly only show up on a fresh clone —
an already-configured working copy hides plenty. Before trusting it:

```sh
cd /tmp && git clone /path/to/your/repo verify-me && cd verify-me
sh tools/mac-forks/install.sh
# diff verify-me's files against your real working copy
```

## 7. Push

Wherever you like (GitHub, etc.) — nothing here is remote-specific.
