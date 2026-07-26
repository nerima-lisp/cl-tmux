# Dogfooded sibling libraries

cl-tmux is the organization's L4 application package: nothing depends on it, so
it is where `nerima-lisp` libraries get exercised against a real workload. Each
one below was adopted where it is a genuine fit for something cl-tmux already
did by hand — not bolted on beside it.

## Cold-path reasoning with cl-prolog

`src/reasoning/` is a declarative read-model built on
[cl-prolog](https://github.com/nerima-lisp/cl-prolog), a dependency-free Common
Lisp Prolog engine that is a **core dependency** of cl-tmux (compiled into the
binary). It projects cl-tmux's declarative tables into Prolog rulebases and
answers relational questions the flat tables cannot express directly.

It is used strictly on **cold paths** — introspection, validation, diagnostics
— never the hot per-keystroke dispatch loop, which stays imperative for speed.

Two domains ship today, key bindings and the canonical command table:

```lisp
(let ((rb (cl-tmux/reasoning:current-key-rulebase)))
  (cl-tmux/reasoning:key-command rb "prefix" #\c)   ; => :NEW-WINDOW, T
  (cl-tmux/reasoning:keys-running rb :new-window)   ; => (("prefix" . #\c))
  (cl-tmux/reasoning:binding-conflicts rb))         ; keys bound differently across tables

(let ((rb (cl-tmux/reasoning:current-command-rulebase)))
  (cl-tmux/reasoning:command-accepts-flag-p rb "bind-key" "T") ; => T
  (cl-tmux/reasoning:commands-with-flag rb "t")               ; commands taking -t target
  (cl-tmux/reasoning:scriptable-commands rb))                 ; commands taking no arguments
```

Its regression suite (`cl-tmux/weave`) uses
[cl-weave](https://github.com/nerima-lisp/cl-weave) — custom matchers,
`around-each` fixtures, a property test, and cl-prolog's own `deftest-queries`
bridge — and runs as the `weave` flake check.

## The other seven

- [cl-cli](https://github.com/nerima-lisp/cl-cli) parses the top-level
  `cl-tmux [flags] [command [flags]]` global flags
  (`main-startup-flags.lisp`, `*cli-app*`), replacing the old ad hoc
  `-L`/`-S`-only scanner with real tmux(1) flag parity — flags may now appear
  in any order before the command word.
- [cl-boundary-kit](https://github.com/nerima-lisp/cl-boundary-kit) supplies
  the process boundary (`cl-tmux/config:*process-boundary*`) that `run-shell` /
  `if-shell` and config-time shell directives run through, so tests can swap in
  a fake process without shelling out for real.
- [cl-dataflow](https://github.com/nerima-lisp/cl-dataflow) models the
  copy-mode lifecycle as an inspectable state machine (`src/dataflow/`), the
  cl-dataflow counterpart to `src/reasoning/` above — same cold-path-only rule,
  same dedicated flake check (`dataflow`).
- [cl-tty-kit](https://github.com/nerima-lisp/cl-tty-kit) backs the PTY layer:
  pane spawn, byte-transparent master-fd read/write, raw mode, and
  terminal-size queries all delegate to it (`src/infrastructure/pty/`). It also
  contributes `rgb-to-256` for `-2` (force-256-colour) true-colour
  downsampling in `renderer-format.lisp`, cl-tmux's first outer-terminal
  colour-capability negotiation. cl-tmux keeps its own `select(2)`
  fd-multiplexing loop, SIGHUP `pty-close`, and `set-pty-size` ioctl on top.
- [cl-parser-kit](https://github.com/nerima-lisp/cl-parser-kit) is the
  tokenizer framework behind `commands-tokenizer.lisp`'s shell-style argument
  splitter — one custom rule for the quote/escape-joining scan (no generic
  library has tmux's "quotes extend the current argument" grammar built in)
  plus a whitespace-skip rule, composed through
  `cl-parser-kit:tokenize-string`.
- [cl-process-kit](https://github.com/nerima-lisp/cl-process-kit) is the
  timeout-guarded subprocess runner the three direct "shell out and capture"
  sites call: `#(shell-command)` format expansion, the `#{pane_current_*}` OS
  probes, and the copy-mode `copy-command` pipe. `process-kit:run` escalates
  SIGTERM→SIGKILL over the child's process group on a deadline overrun, so a
  hung command never orphans a shell. `run-shell` / `if-shell` deliberately
  stay on cl-boundary-kit, which supplies the injectable test double
  (`make-test-process-boundary`) that cl-process-kit has no equivalent for.
- [cl-history-kit](https://github.com/nerima-lisp/cl-history-kit) replaced the
  hand-rolled list-and-cursor walk behind `:command-prompt`'s Up/Down recall
  (`runtime-history.lisp`, `prompt.lisp`). Storage, capacity, and navigation
  are now cl-history-kit's: `history-add`/`history-entries` for the store,
  `history-merge` to carry entries across a capacity change when
  `prompt-history-limit` is set at runtime, and `history-previous`/
  `history-next` for recall. This is a deliberate behavior change from real
  tmux: cl-history-kit's recall is **prefix-filtered** (the buffer at the
  start of a walk becomes both its match filter and its restore origin,
  zsh-style), where tmux's own Up/Down is an unfiltered raw walk. Chosen for
  the better editing ergonomics over strict Up/Down parity.

## External dependencies

Beyond the eight siblings and cl-weave, cl-tmux depends on four libraries from
outside the organization: `cffi`, `bordeaux-threads`, `babel` and `cl-ppcre`.
It is the only `nerima-lisp` repository that does. The rationale for each is
recorded per line in `cl-tmux.asd` and in `flake.nix`; the short version is
that each covers a gap SBCL does not, and that cl-tmux can carry them because
nothing in the organization depends on cl-tmux, so an upstream break cannot
propagate.
