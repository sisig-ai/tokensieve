<p align="center">
  <img src=".github/assets/banner.png" width="640" alt="tokensieve: dithered pixel art of a bowl sieving falling specks">
</p>

<h1 align="center">tokensieve</h1>

<p align="center">
  <strong>Minimal Zig CLI that compresses successful tool output for LLM agents.</strong>
</p>

<p align="center">
  <a href="https://github.com/sisig-ai/tokensieve/releases"><img src="https://img.shields.io/github/v/release/sisig-ai/tokensieve?style=flat-square" alt="Latest release"></a>
  <a href="https://github.com/sisig-ai/tokensieve/actions/workflows/release-main.yml"><img src="https://img.shields.io/github/actions/workflow/status/sisig-ai/tokensieve/release-main.yml?style=flat-square" alt="Release main workflow status"></a>
  <a href="https://ziglang.org/"><img src="https://img.shields.io/badge/zig-0.16.0-171914?style=flat-square" alt="Zig 0.16.0"></a>
  <a href="./LICENSE"><img src="https://img.shields.io/github/license/sisig-ai/tokensieve?style=flat-square" alt="License"></a>
</p>

<p align="center">
  <a href="#quick-start">Quick start</a> ·
  <a href="#usage">Usage</a> ·
  <a href="#how-it-works">How it works</a> ·
  <a href="#contributing">Contributing</a>
</p>

tokensieve runs a known tool and, on success, optionally compresses stdout so LLM agents spend fewer tokens. Stderr is always forwarded unchanged. Exit status is forwarded.

```sh
tokensieve git status
```

## Why

Agents spend tokens on tool-output noise. tokensieve is inspired by [rtk](https://github.com/rtk-ai/rtk)'s goal of cutting that noise. It is an independent implementation (not a fork).

## Features

- Filters for `git status`, `git log`, `git diff`, `cargo test`, `pytest`, `bun test`, `eslint`, `prettier`, `django test`, `ruff`, `mypy`, `rg`, and `grep`.
- Falls back to ANSI strip only when a tool prints an output shape it does not recognize.
- Prefers `rg` for `tokensieve grep` when `rg` is on `PATH`, otherwise runs system `grep`.
- Merges `bun test` stdout and stderr on success and emits the result on stdout only.

## Quick start

Download the Linux x86_64 release binary, built from each push to `main`:

```sh
curl -L -o tokensieve https://github.com/sisig-ai/tokensieve/releases/latest/download/tokensieve-linux-x86_64
chmod +x tokensieve
```

Or build from source. This requires Zig 0.16.0.

```sh
zig build
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
tokensieve rg [-- args...]
tokensieve grep [-- args...]
tokensieve --help
tokensieve --version
```

Top-level `--help` / `--version` are tokensieve's. After a recognized tool, flags are forwarded to the child. Trailing argv (including a literal `--`) is forwarded unchanged.

Unknown top-level command or git subcommand → stderr message, exit `2`. `tokensieve bun` / `tokensieve django` without `test` → exit `2`.

`tokensieve grep` prefers `rg` when it is on `PATH`, otherwise runs system `grep`. `tokensieve rg` always runs `rg`.

### Measuring reduction

Measure reduction locally (not tokenizer "token %"):

```sh
git status | wc -c -l
tokensieve git status | wc -c -l

git log -n 5 | wc -c -l
tokensieve git log -n 5 | wc -c -l
```

## How it works

### Success filters

| Invocation | On success |
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
| `rg` / `grep` | truncate each line to 120 chars (`…`); hard-cap 150 lines then `… +N more lines`; `--json` → ANSI strip only. Exit 1 (no matches) and other nonzero → raw passthrough |

Capture loses stdout/stderr interleaving. Unless noted (`bun test` merge), each stream is byte-identical to the child's buffer.

## Non-goals

- No PreToolUse / permission hooks
- No telemetry, network, analytics, or SQLite
- No auto-install as an agent hook: explicit invocation only
- No filtering when the child exits non-zero (failure output is verbatim)
- No `ls`, Windows, or unknown-command proxy

## Development

Run the tests:

```sh
zig build test
```

`cargo test` / `pytest` / `bun test` / `eslint` / `prettier` / `django test` / `ruff` / `mypy` / `rg`/`grep` filters are covered by fixtures under `testdata/` (optional live regen if those tools are installed).

## Contributing

Issues and PRs are welcome. Run `zig build test` before opening a PR.

## License

MIT, see [LICENSE](./LICENSE).
