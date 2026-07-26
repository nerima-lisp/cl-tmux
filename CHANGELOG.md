# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

<!--
Heading format is fixed across the org:

    ## [X.Y.Z] - YYYY-MM-DD

The version is bracketed, the separator is an ASCII hyphen (not an em dash),
and the date is ISO 8601. release.yml extracts the section matching the pushed
tag as the GitHub Release body, so a heading that deviates makes the release
fail. Keep `## [Unreleased]` at the top at all times.

Use only these subsection names, and omit the ones that are empty:
Added / Changed / Deprecated / Removed / Fixed / Security
-->

## [Unreleased]

### Added

- **Adopted [cl-history-kit](https://github.com/nerima-lisp/cl-history-kit)
  v1.0.0** as an eighth dogfooded sibling library, replacing the hand-rolled
  list-and-cursor walk behind `:command-prompt`'s Up/Down recall
  (`runtime-history.lisp`, `prompt.lisp`). See
  [Sibling libraries](docs/src/guide/sibling-libraries.md) for what moved and
  why, and [Compatibility](docs/src/reference/compatibility.md) for the
  resulting, deliberate deviation from tmux's own unfiltered Up/Down walk
  (cl-history-kit's recall is prefix-filtered, zsh-style).
- Closed two real SB-COVER branch-coverage gaps found by a src/-only scoped
  triage: `commands-copy-mode-search.lisp`'s incremental-search (`C-s`/`C-r`)
  live-jump engine and submit path, and `commands-copy-mode-brackets.lisp`'s
  cursor-not-on-bracket fallback plus nested/cross-row backward matching.
  `config.lisp`'s low expression-coverage number was confirmed a load-time
  artifact (data/`eval-when` forms), not a gap.
- Closed two more coverage gaps, src/-only SB-COVER now 87.50% expression /
  82.72% branch (up from 85.82%/82.27%): `%run-command-line`'s
  semicolon-chaining (previously only exercised through the static `bind`
  directive parser, never a runtime command line), and
  `%execute-menu-cmd`'s list-encoded `(:select-window id)`/`(:switch-client
  name)` shapes — the actual per-item command format tmux's
  choose-window/choose-session menus use, which existing tests never
  triggered past "the menu opens."
- Covered `flags-of-command` (`src/reasoning/command-rulebase.lisp`), the
  one query helper in the command-metadata reasoning read-model with no test
  call sites — found by a paredit `unused-definitions` re-audit, which
  otherwise reconfirmed zero removable dead code in this codebase.

### Changed

- **Deduplicated two more genuine near-copies found by a directory-scoped
  `paredit inspect similarity` pass** (the whole-tree run is too slow to
  finish): `copy-mode-toggle-position`/`copy-mode-toggle-rectangle` now
  share a `define-copy-mode-toggle` macro instead of two byte-identical
  guard/flip/dirty bodies, and `%option-sgr`/`%copy-match-sgr` collapse
  into one `%option-style-sgr` (the narrower one becomes a one-line
  wrapper). No behavior change.
- Extended that similarity sweep to every remaining src/ subsystem
  directory: `%cmd-bind-arg`/`%cmd-unbind-arg` now share a
  `define-config-directive-command` macro, and `window-operations.lisp`'s
  `%build-spine-tree` — a fully redundant duplicate of `layout.lisp`'s
  `%build-flat-tree :h` (their only difference, an explicit `1/2` ratio,
  was already `make-layout-split`'s default) — is deleted outright.
- **Readability: extracted the 6 most deeply-nested functions in the
  codebase** (per `paredit inspect complexity`'s per-definition nesting
  metric), each split so every dispatch branch has a named helper matching
  its siblings — `%expand-brace`, `describe-key-binding-notes`,
  `%render-copy-search-matches`, `%cmd-send-keys-arg`, `%parse-rgb-color`,
  `%cmd-new-session-arg`. No behavior change; verified by the full test
  suite after each extraction.
- **Sibling dependency bump: `cl-boundary-kit` v0.6.0 → v1.0.0,
  `cl-process-kit` v1.0.0 → v1.0.1.** Both are behavior-preserving per
  upstream release notes — `cl-boundary-kit` 1.0.0 is a stability-policy
  commitment with no exported-symbol/protocol changes, and `cl-process-kit`
  1.0.1 is a packaging-only fix (a stale transitive tag reference) with no
  source change. Verified with the real sandboxed `nix flake check`, not just
  the interactive dev-shell suite. The other 6 dogfooded siblings
  (`cl-cli`, `cl-dataflow`, `cl-parser-kit`, `cl-prolog`, `cl-tty-kit`,
  `cl-weave`) are already pinned to their current newest tags, so there was
  nothing left to bump there.

## [0.1.0] - 2026-07-26

### Added

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
- Four external (non-org) runtime dependencies, the only ones in the
  organization: `cffi` (BSD-style/MIT), `bordeaux-threads` (MIT), `babel`
  (MIT) and `cl-ppcre` (BSD-2-Clause). All four are permissive and compatible
  with this project's MIT license. `DEPENDENCY_POLICY.md` grandfathers them in
  on the grounds that cl-tmux is the sole L4 application package, so nothing
  in the organization can inherit a break from them. The reason each is
  required is recorded per line in `cl-tmux.asd` and in `flake.nix`.

### Changed

- **Conformance with the org package standard.** The repository layout now
  follows `PACKAGE_STANDARD.md`: tests moved from `tests/` to `t/`, a single
  `run-tests.lisp` at the root became the only Lisp-level test entry point,
  the four standard workflows and the `nix-setup` composite action were
  installed with every `uses:` pinned to a 40-character commit SHA, the
  hardcoded Cachix cache name was replaced by `vars.CACHIX_CACHE`, and the
  documentation moved into a `docs/src/` MkDocs site gated by
  `mkdocs --strict`. `src/` stays nested, which the standard records as this
  repository's one sanctioned exception.
- **flake.nix moved off flake-utils to plain `nixpkgs.lib.genAttrs`.**
  `eachDefaultSystem` derived the platform list from flake-utils' hardcoded
  default set, which advertised `aarch64-linux` and `x86_64-darwin` — two
  platforms nothing in this project has ever built. `systems` is now the two
  that are actually verified, `x86_64-linux` by CI and `aarch64-darwin` by
  `nix flake check` on the development machine (ADR-0078). In the same pass
  the version became a read of `cl-tmux.asd` rather than a second hardcoded
  number, every sibling input gained a release tag, and `checks` gained
  `formatting` (treefmt/nixfmt) and `docs` (`mkdocs --strict`) alongside the
  existing `default`, `weave` and `dataflow`.
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
