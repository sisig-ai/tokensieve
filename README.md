# tokensieve

Minimal Zig CLI that runs a known tool, and on **success** optionally compresses **stdout** so LLM agents spend fewer tokens. Stderr is always forwarded unchanged. Exit status is forwarded.

Inspired by [rtk](https://github.com/rtk-ai/rtk)’s goal of cutting tool-output noise for agents; **independent implementation** (not a fork). Apache-2.0.

## Non-goals

- No PreToolUse / permission hooks
- No telemetry, network, analytics, or SQLite
- No auto-install as an agent hook — **explicit invocation only**
- No filtering when the child exits non-zero (failure output is verbatim)
- No `ls`, Windows, or unknown-command proxy

## Build

Requires Zig 0.16.0.

```sh
zig build
zig build test
```

Binary: `zig-out/bin/tokensieve`

## Usage

```sh
tokensieve git status [-- args...]
tokensieve git log [-- args...]
tokensieve git diff [-- args...]
tokensieve cargo test [-- args...]
tokensieve pytest [-- args...]
tokensieve bun test [-- args...]
tokensieve eslint [-- args...]
tokensieve prettier [-- args...]
tokensieve django test [-- args...]
tokensieve ruff [-- args...]
tokensieve mypy [-- args...]
tokensieve --help
tokensieve --version
```

Top-level `--help` / `--version` are tokensieve’s. After a recognized tool, flags are forwarded to the child. Trailing argv (including a literal `--`) is forwarded unchanged.

Unknown top-level command or git subcommand → stderr message, exit `2`. `tokensieve bun` / `tokensieve django` without `test` → exit `2`.

### Success filters

| invocation | on success |
|---|---|
| `git status` (no args) | drop empty lines and `(use "git …")` hints |
| `git status` with any args | ANSI strip only |
| `git log` with no args, or only `-n <int>` / `--max-count=<int>` | compact default/oneline log to `hash subject` lines when recognized; else ANSI strip only |
| `git log` with other args (`-p`, `--stat`, …) | ANSI strip only |
| `git diff` | ANSI strip only (full diff kept) |
| `cargo test` | drop per-test `ok` lines when suite all-pass; keep summary; unknown shape → ANSI strip only |
| `pytest` | drop `PASSED` / progress lines when all-pass; keep summary; unknown shape → ANSI strip only |
| `bun test` | drop `(pass)` lines and bare file headers when all-pass; keep version + summary; unknown shape → ANSI strip only. On success, stdout+stderr are merged before filtering (bun prints results on stderr) and emitted on stdout only |
| `eslint` | empty / `✖ 0 problems` → `eslint: ok`; otherwise ANSI strip only (no `-f json` injection) |
| `prettier` | keep `All matched files use Prettier…`; drop `Checking formatting...`; unknown shape → ANSI strip only |
| `django test` | drop `... ok` and create/destroy DB lines when all-pass; keep Found/System check/Ran/OK; unknown shape → ANSI strip only |
| `ruff` | `All checks passed!` / `already formatted` / empty → `ruff: ok`; otherwise ANSI strip only |
| `mypy` | `Success: no issues found…` / empty → `mypy: ok`; otherwise ANSI strip only |

Capture loses stdout/stderr interleaving. Unless noted (`bun test` merge), each stream is byte-identical to the child’s buffer.

## Example (bytes / lines)

Measure reduction locally (not tokenizer “token %”):

```sh
git status | wc -c -l
tokensieve git status | wc -c -l

git log -n 5 | wc -c -l
tokensieve git log -n 5 | wc -c -l
```

`cargo test` / `pytest` / `bun test` / `eslint` / `prettier` / `django test` / `ruff` / `mypy` filters are covered by fixtures under `testdata/` (optional live regen if those tools are installed).

## License

Apache-2.0 — see [LICENSE](./LICENSE).
