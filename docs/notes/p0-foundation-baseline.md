# P0 foundation baseline

This note records the baseline evidence used by the foundation refactor. It
separates measurements from checks that were unavailable on the development
machine.

## Static baseline

- The manifest contains 247 test files, and the on-disk `t/` tree contains 247
  files. `scripts/checks/manifest-check.lisp` is the reproducer.
- The suite-structure scan visits 392 Lisp test files. `scripts/checks/suite-structure-check.pl .`
  is the reproducer.
- The first-frame benchmark has recorded control and attach samples in
  `docs/src/benchmarks.md`. The recorded attach median changed from 89.115 ms
  to 131.448 ms, with a 32.976 ms control noise floor; the document does not
  claim that this is a current-tree measurement.
- No key-update benchmark driver or measured key-update result exists in this
  tree, so that baseline remains unmeasured rather than being inferred.

## Coverage and deadlock baseline

- The coverage runner now includes `src/` and every `packages/*/src/` root,
  rejects an empty test selection and empty assertion journal, requires a
  non-empty report, and is registered as a flake check. Its per-test timeout
  is capped at 300 seconds and the outer Nix timeout is 2700 seconds.
- The former deadlock path was `pty-close` closing the PTY master and then
  calling `sb-ext:process-wait` on the same process object. The replacement
  polls process status and `kill(pid, 0)` until a five-second deadline and
  reports a timeout as an error.
- A local filtered PTY run was attempted but interrupted after the Nix daemon
  produced no output for more than 90 seconds. The pull request CI run remains
  the runtime evidence for the pre-fix tree; the post-fix runtime result must
  come from CI.
