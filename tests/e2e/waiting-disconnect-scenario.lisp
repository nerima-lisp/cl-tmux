(defun %waiting-disconnect-write-fake-codex ()
  (let* ((bin-dir (merge-pathnames "bin/" (uiop:ensure-directory-pathname
                                           (sb-ext:posix-getenv "TMPDIR"))))
         (path (merge-pathnames "codex" bin-dir)))
    (ensure-directories-exist bin-dir)
    (with-open-file (stream path :direction :output :if-exists :supersede
                                  :if-does-not-exist :create)
      (write-line "#!/bin/sh" stream)
      (write-line "printf 'E2E_WAITING\\a\\n'" stream)
      (write-line "sleep 30" stream))
    (multiple-value-bind (exit-code stdout stderr timed-out)
        (run-program-bounded "chmod" (list "u+x" (namestring path)))
      (unless (and (eql exit-code 0) (not timed-out))
        (error "fake codex chmod failed: exit=~S timeout=~S stdout=~S stderr=~S"
               exit-code timed-out stdout stderr)))
    (namestring bin-dir)))

(defun %run-waiting-disconnect-scenario (binary)
  "Disconnect a client immediately after an agent BEL and keep another client
   alive long enough to prove the server survived its next waiting broadcast."
  (let* ((worktree (%prepare-bare-worktree))
         (fake-bin (%waiting-disconnect-write-fake-codex))
         (path-separator ":")
         (old-path (or (sb-ext:posix-getenv "PATH") ""))
         (environment nil)
         (marker "E2E_WAITING"))
    (sb-posix:setenv "PATH"
                    (format nil "~A~A~A" fake-bin path-separator old-path)
                    1)
    (setf environment (sb-ext:posix-environ))
    (if (plusp (length old-path))
        (sb-posix:setenv "PATH" old-path 1)
        (sb-posix:unsetenv "PATH"))
    (multiple-value-bind (client-fd client-pid)
        (nerimux/pty:forkpty-with-shell
         24 80
         :start-dir worktree
         :default-command (format nil "exec ~S attach ~S" binary worktree)
         :environment environment)
      (unwind-protect
           (multiple-value-bind (observer-fd observer-pid)
               (nerimux/pty:forkpty-with-shell
                24 80
                :start-dir worktree
                :default-command (format nil "exec ~S attach" binary)
                :environment environment)
             (unwind-protect
                  (let ((client-startup (%make-accumulator))
                        (client-output (%make-accumulator))
                        (observer-startup (%make-accumulator)))
                    (%wait-for-startup-render client-fd
                                              +e2e-startup-timeout-seconds+
                                              client-startup)
                    (%wait-for-startup-render observer-fd
                                              +e2e-startup-timeout-seconds+
                                              observer-startup)
                    ;; The explicit attach selects the worktree in the
                    ;; overview; x opens its selected row as an agent pane.
                    (nerimux/pty:pty-write client-fd "x")
                    (unless (%wait-for-marker client-fd marker
                                               +e2e-marker-timeout-seconds+
                                               client-output)
                      (error "fake agent waiting marker did not appear"))
                    ;; pty-close sends SIGHUP to the client, leaving its
                    ;; server-side connection to be discovered on the next
                    ;; select/broadcast cycle.
                    (nerimux/pty:pty-close client-fd client-pid)
                    (setf client-fd -1)
                    (multiple-value-bind (exit-code stdout stderr timed-out)
                        (run-program-bounded binary '("kill" "--force")
                                                 :timeout-seconds 10)
                      (if (and (eql exit-code 0) (not timed-out))
                          (values t
                                  (format nil
                                          "disconnected waiting client did not take down server; kill exit=0 stdout=~S"
                                          stdout))
                          (values nil
                                  (format nil
                                          "server cleanup after disconnect failed: exit=~S timeout=~S stderr=~S"
                                          exit-code timed-out stderr))))))
               (nerimux/pty:pty-close observer-fd observer-pid)))
        (when (plusp client-fd)
          (nerimux/pty:pty-close client-fd client-pid))))))
