# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Initial public development. Highlights of what the tree contains today:

- tmux-compatible terminal multiplexer written in pure Common Lisp (SBCL +
  sb-posix + CFFI; no custom C).
- Full command surface: every primary command name in tmux's command table
  resolves (canonical names only — short aliases are deliberately rejected),
  with flag-level parity validated against upstream behavior.
- VT100/ANSI emulator: SGR (16/256/true color), alternate screen, scroll
  regions, charsets G0–G3, DECDHL/DECDWL double-size lines, bracketed paste,
  mouse reporting, OSC 52 clipboard, OSC 133 prompt marks, UTF-8 with wide
  (CJK) cells.
- Copy mode with vi-style navigation, selection, search, and 90+
  `-X` commands; paste buffers.
- Format-string engine (`#{...}`) with the full modifier set and 160+
  format variables.
- Options across server/session/window/pane scopes, 28 hook events, key
  tables, and `.tmux.conf`-style configuration including `%if`/`%hidden`,
  variable assignments, and `source-file`.
- Client/server over per-user Unix sockets (`-L`/`-S`, `$TMUX_TMPDIR`),
  session groups sharing one window set, control mode (`-C`).
- Test suite (11,000+ checks) run hermetically via `nix flake check`, now on
  the [`cl-weave`](https://github.com/nerima-lisp/cl-weave) framework.
- Cold-path reasoning read-models built on the dependency-free
  [`cl-prolog`](https://github.com/nerima-lisp/cl-prolog) engine, now a **core
  dependency** compiled into the binary (`src/reasoning/`). Two declarative
  domains are projected into Prolog rulebases and queried for relations the
  flat tables cannot express directly:
  - **key bindings** — resolution, reverse lookup, cross-table conflicts,
    root-shadowing, and repeatable-command inference;
  - **command metadata** — the canonical command table with derived
    `accepts-flag`, `scriptable`, and flag-reverse-lookup relations.
  Reasoning is strictly cold-path (introspection/validation); the hot
  per-keystroke dispatch loop stays imperative for speed.
- `cl-weave` regression suite (`cl-tmux/weave`) for the reasoning models, using
  custom matchers, `around-each` fixtures, a property test, and `cl-prolog`'s
  own `deftest-queries` bridge; exposed as the `weave` flake check.
- Six more dependency-light sibling libraries adopted as **core
  dependencies**, each replacing or augmenting a hand-rolled piece of the
  same concern it specializes in:
  - [`cl-cli`](https://github.com/nerima-lisp/cl-cli) — the top-level
    `cl-tmux [flags] [command [flags]]` entry point (`main-startup.lisp` /
    `main-startup-flags.lisp` `*cli-app*`) now parses real tmux(1) global
    flags (`-2`, `-C`/`-CC`, `-D`, `-L`, `-N`, `-S`, `-T`, `-V`, `-c`, `-f`,
    `-h`, `-l`, `-u`, `-v`, verified against `man 1 tmux`) in any order, fixing
    a real bug where a flag before `-C`/`-V` (e.g. `cl-tmux -L sock -C`) used
    to hard-fail with a usage error.
  - [`cl-tty-kit`](https://github.com/nerima-lisp/cl-tty-kit) — now backs the
    whole PTY layer: pane spawn, byte-transparent master-fd read/write, raw
    mode, and terminal-size queries delegate to it
    (`src/infrastructure/pty/`), replacing cl-tmux's own termios implementation
    (`pty-rawmode.lisp`, now a thin cl-tty-kit wrapper) and the `%read`/`%write`
    CFFI. cl-tmux keeps its own
    `select(2)` fd-multiplexing loop, SIGHUP `pty-close`, and `set-pty-size`
    ioctl on top. Separately, `rgb-to-256` downsamples true-colour SGR output
    to the 256-colour palette when `-2` is given (`renderer-format.lisp`
    `*color-downsample-fn*`), the first cl-tmux terminal-capability negotiation
    beyond emitting whatever a style asks for unconditionally.
  - [`cl-boundary-kit`](https://github.com/nerima-lisp/cl-boundary-kit) — a
    process boundary (`cl-tmux/config:*process-boundary*`) now sits behind
    every `run-shell` / `if-shell` subprocess call (config-time and
    command-time), swappable for `make-test-process-boundary` /
    `make-recording-process-boundary` in tests without touching a real shell.
  - [`cl-dataflow`](https://github.com/nerima-lisp/cl-dataflow) — a new
    cold-path read-model (`src/dataflow/`, mirroring `src/reasoning/`) models
    the copy-mode lifecycle already documented as a Prolog-style rule table
    atop `commands-copy-mode.lisp` as an inspectable `cl-dataflow` state
    machine, with DOT/Mermaid export; regression-tested by the new
    `cl-tmux/dataflow` cl-weave suite (`dataflow` flake check).
  - [`cl-parser-kit`](https://github.com/nerima-lisp/cl-parser-kit) —
    `commands-tokenizer.lisp`'s shell-style argument splitter is now one
    custom `cl-parser-kit` token rule (the quote/escape-joining scan, which
    has no off-the-shelf equivalent) composed with a whitespace-skip rule and
    run through `tokenize-string`, inheriting span tracking and the library's
    tokenizer resource-limit guards for free.
  - [`cl-process-kit`](https://github.com/nerima-lisp/cl-process-kit) — the
    three direct "shell out, capture stdout, enforce a deadline" call sites
    that still hand-rolled `uiop:run-program` + a `:timeout` (and, for
    copy-command, a redundant belt-and-suspenders `bt:with-timeout`) now call
    `process-kit:run` directly: `#(shell-command)` format expansion
    (`format-shell-command.lisp`), the `pgrep`/`ps`/`readlink`/`lsof`
    `#{pane_current_*}` OS probes (`format-context-os-probe.lisp`), and the
    copy-mode `copy-command` pipe (`commands-copy-mode-clip.lisp`). On a
    deadline overrun `process-kit:run` escalates SIGTERM→SIGKILL against the
    child's **whole process group**, so a hung command can no longer orphan a
    shell past its timeout — the behaviour the bare `bt:with-timeout` wrapper
    only pretended to guarantee. `run-shell`/`if-shell` deliberately stay on
    `cl-boundary-kit`, which supplies the injectable test double
    (`make-test-process-boundary`) that cl-process-kit has no equivalent for.

### Changed

- **Org migration `github:takeokunn` → `github:nerima-lisp`.** Every project
  URL (flake inputs `cl-weave`/`cl-prolog`, the `.asd`
  homepage/source-control/bug-tracker, README/SECURITY badges and links, the
  Cachix cache name) now points at the `nerima-lisp` organization; author
  attribution (`© takeokunn`, the `:author` slots) is unchanged. Sibling flake
  inputs were re-locked to their current `nerima-lisp` revs in the same pass.

- **Test framework migrated from FiveAM to cl-weave.** The `fiveam` dependency
  is gone from the ASDF test system and the Nix checks, and so is the temporary
  compatibility shim that first bridged the two — every test file is now
  authored directly in cl-weave's native surface (`describe` / `it` / `expect`
  / `signals` / `finishes` / `skip`), with custom matchers and `around-each`
  fixtures where useful. The runner (`run-tests`) drives `cl-weave:run-all`
  (single-worker sequential); per-test thread cleanup runs through a root
  `after-each` hook.

- **Duplicated option-table registration folded into one macro.**
  `define-tmux-options` and `define-server-options` each hand-rolled an
  identical "populate the immutable known-registry fallback" step after
  delegating their other two phases to `define-option-table`; that third
  phase now lives in `define-option-table` itself (a `known-registry-var`
  parameter), so both wrappers are a one-line delegating call.

- **Copy-mode's numeric-prefix accumulator converted to CPS.** Instead of
  mutating the raw `*copy-mode-prefix*` integer across calls,
  `%copy-mode-accumulate-digit` is now `%make-copy-mode-digit-k`, a
  self-recursive continuation constructor
  mirroring `make-prompt-utf8-k`/`*prompt-utf8-continuation*` — the shape its
  own docstring had described as the target since before the prompt-UTF8
  helper adopted it.

- **Ongoing `cl-weave:it-each` conversion of `dolist`-driven test tables.**
  26 more parameterized-case tables (across `events-tests-f.lisp`,
  `renderer-format-tests-b.lisp`, `protocol-tests.lisp`) now expand into
  independently named/reported cases instead of one aggregate `it` per
  table, continuing the sweep noted in the FiveAM-migration entry above.
  Tables built from computed values (row elements that are function calls,
  not literal data) are left as manual `dolist`s — `it-each`'s row-list is
  literal/unevaluated, so a computed row cannot convert.

### Fixed

- `main-startup-flags.lisp`: wrap the `%flag-parser-clause` helper in
  `eval-when` so `define-flag-parser` can expand on a cold compile (the helper
  and its macro-time callers now live in one file after the bootstrap split).
- Restored `load-config-from-stream` / `load-config-from-string` in
  `config-preprocessor.lisp`: a file-split refactor dropped these two exported
  loaders while their callers (`load-config-file`) and exports remained,
  leaving config-file loading undefined at runtime.
- Renamed the startup-only `%flag-value` (flat arg-list scanner, 3 callers) to
  `%startup-flag-value` to end a name collision with dispatch's `%flag-value`
  (alist accessor, 95 callers). Because the startup file loads last, its
  definition had been clobbering dispatch's, breaking every flag-taking
  command (e.g. `switch-client -T`, modifier-arrow resize) at runtime.
- Moved the `with-loop-safe-error` macro to `server-multi-dispatch.lisp` (the
  first file that uses it); it had been defined in `server-multi.lisp`, which
  loads later, so the multi-client command handlers compiled the macro calls as
  undefined-function calls and left `CONDITION` unbound at runtime.
- Fixed an infinite loop in `%consume-global-socket-flags`: its helper
  `%consume-socket-flag` popped its own *local* argv, so the caller never
  advanced and spun forever on the first `-L`/`-S` — hanging every
  `cl-tmux -L <name> <command>` at startup. The helper now returns the
  remaining argv.
- Restored the `-F`-skipping loop in `%list-commands-arguments`; a refactor had
  replaced it with a positional scan that returned the `-F` format value as the
  command name.
- `flake.nix`'s `devShells.default` printed `sbcl --load cl-tmux.asd --eval
  '(asdf:load-system :cl-tmux)'` as the way to start hacking, but that command
  fails outright: `.asd` files read `defsystem` in whatever package ASDF
  happens to install as the reader's current package, which is only correct
  once `(require :asdf)` and the sibling-library central-registry pushes (the
  same ones the `checks` derivations already assemble as
  `siblingRegistryPushEvals`) have run first. The shell hook now exports a
  `cl-tmux-sbcl` function wrapping those in, and prints working commands built
  on it.
