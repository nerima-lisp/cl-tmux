# cl-tmux

A tmux-compatible terminal multiplexer written entirely in Common Lisp.

cl-tmux reimplements tmux's behavior — commands, options, format strings, copy
mode, hooks, mouse, client/server — on top of SBCL, with no custom C code.
Every verified behavior is pinned by a regression suite of 11,000+ checks that
runs hermetically through Nix.

Start at [Getting started](getting-started.md), or read the
[compatibility statement](reference/compatibility.md) for the precise account
of what is implemented and what is deliberately different.

## Feature highlights

- **Commands** — every primary command name in tmux's command table resolves
  (~100 commands: `split-window`, `send-keys`, `capture-pane`, `display-menu`,
  `display-popup`, `command-prompt`, `choose-tree`, `if-shell`, …), with
  flag-level behavior closed against upstream tmux across repeated audits.
- **Terminal emulation** — VT100/ANSI with 16/256/true color, alternate
  screen, scroll regions, origin mode, G0–G3 charsets with line-drawing
  remap, DECDHL/DECDWL double-size lines, bracketed paste, SGR mouse,
  OSC 52 clipboard, OSC 133 prompt marks, and UTF-8 with wide (CJK) cells.
- **Copy mode** — vi-style navigation, selection (including rectangle),
  incremental search, prompt jumping, and 90+ `send-keys -X` commands.
- **Format strings** — the full `#{...}` modifier set
  (`b: d: U: L: n: =N: pN: s/// E: t: m: C: a: q: l:`, comparison/boolean
  operators, `W:`/`S:`/`P:` iteration) over 160+ format variables.
- **Options & hooks** — 120+ options across server/session/window/pane
  scopes, 28 hook events with `set-hook` scoping, key tables, and
  `bind-key -N` notes.
- **Client/server** — detach/attach over per-user Unix sockets
  (`-L`/`-S`, `$TMUX_TMPDIR`), multiple sessions, session groups sharing one
  window set, and control mode (`-C`) for tools like tmuxp/libtmux-style
  automation.
- **Configuration** — real `.tmux.conf` syntax: `%if`/`%elif`/`%else`,
  `%hidden`, variable assignments, `source-file`, brace blocks, and tmux
  quoting rules. See [Configuration](guide/configuration.md).

## What it is built on

- **SBCL** — the Lisp implementation (PTYs via `sb-ext:run-program`, POSIX via
  `sb-posix`).
- **CFFI** — the handful of libc calls `sb-posix` does not cover (`select`,
  `ioctl`).
- **bordeaux-threads** — one reader thread per PTY pane.
- **babel** / **cl-ppcre** — UTF-8 codecs and regexes (format `s///` and `m/r:`
  matching).

Beyond those four, cl-tmux runs on six sibling `nerima-lisp` libraries; see
[Dogfooded sibling libraries](guide/sibling-libraries.md).

## Project

- Source and issues: <https://github.com/nerima-lisp/cl-tmux>
- Contribution guide, code of conduct, security policy and support channels
  are the organization-wide files published from
  [nerima-lisp/.github](https://github.com/nerima-lisp/.github).
- Licensed under MIT.
