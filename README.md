# ncd

Jump to a directory you have already visited by typing a fragment of its name.

```bash
ncd proj        # cd to the best match in your history, e.g. ~/work/projects
ncd proj        # again: rotate to the next match
ncs             # toggle back to the previous directory (like `cd -`)
```

Plain Perl 5 (core modules only) plus two bash functions. Runs on Linux and on
Windows under Git-Bash / msys.

## Installation

```bash
mkdir -p ~/bin
cp ncd.pl bashrc.inc ~/bin/
chmod +x ~/bin/ncd.pl
echo '. $HOME/bin/bashrc.inc' >> ~/.bashrc
```

Open a new shell. The history starts empty and fills up as you move around with
`ncd` and `ncs`; `ncd <existing path>` behaves like `cd` and records the
directory.

## Usage

| Command | Effect |
|---|---|
| `ncd <fragment>` | go to the best match; repeat to rotate through the others |
| `ncd work/proj` | match consecutive path components (`…/work/projects`, …) |
| `ncd <path>` | an existing directory always wins over the history |
| `ncd` | go home |
| `ncs [n]` | rotate among the *n* last directories (default 2, i.e. `cd -`) |
| `ncd -v <fragment>` | also list the candidates on stderr |
| `ncd -l` | list the history |
| `ncd --clean` | move vanished directories to `~/.ncdpath.missing` |

### Matching

Every component of every path in the history is compared to the fragment and
ranked: **exact** name, then **prefix**, then **substring**. Ties go to the most
recently used directory, then to the shortest path. The result is cut right
after the component that matched, so `ncd projects` lands on `~/work/projects`
even if only `~/work/projects/ncd` is in the history.

**Smart case**: an all-lower-case fragment ignores case; a fragment holding an
upper-case letter is matched case-sensitively.

### Rotation

Typing the same query again *while still standing on the previous answer*
moves to the next candidate. Moving anywhere else accepts the answer, and the
next query starts a fresh search. The current directory is always skipped.

A directory is promoted to the top of the history when you **leave** it, not
when you reach it: candidates you rotated past do not climb the history.

### Vanished directories

Directories that no longer exist are reported on stderr and skipped, but kept
in the history by default — an unmounted share or a detached drive should not
erase it. Use `ncd --clean` to move them out of the way (into
`~/.ncdpath.missing`, nothing is lost), or set `NCDautoremove` to drop them
automatically.

## Configuration

| Variable | Default | Meaning |
|---|---|---|
| `NCDfile` | `~/.ncdpath` | history file, one path per line, most recent first |
| `NCDmax` | unlimited | maximum number of history entries |
| `NCDautoremove` | off | drop vanished directories from the history |
| `NCDquiet` | off | no informational messages on stderr |

State files, next to `$NCDfile`: `.mem` (rotation state, shared by all your
terminals) and `.missing` (written by `--clean`).

## Tests

```bash
prove -v t/ncd.t      # or: perl t/ncd.t
```

The tests run in a temporary sandbox and never touch your real history. Five
of them need a case-sensitive filesystem and are skipped elsewhere; on Windows,
see `CLAUDE.md` for how to enable case sensitivity on a test directory.

## License

MIT — see [LICENSE](LICENSE).
