(in-package #:nerimux/test/vcs)

(describe "vcs worktree commands"
  (it "emits exact synchronous worktree operation commands"
    (let* ((repository-path (%vcs-operations-existing-path))
           (secondary-path (concatenate 'string repository-path "secondary"))
           (repository
             (nerimux/workspace-model:make-repository
              :specification "workspace-owner/project"
              :local-path repository-path))
           (main-worktree
             (nerimux/workspace-model:make-worktree
              :repository repository
              :path repository-path
              :branch "main"))
           (secondary-worktree
             (nerimux/workspace-model:make-worktree
              :repository repository
              :path secondary-path
              :branch "feature/ui"))
           (commands nil)
           (execution-options
             (nerimux/vcs::%worktree-operation-execution-options)))
      (nerimux/workspace-model:repository-add-worktree repository main-worktree)
      (nerimux/workspace-model:repository-add-worktree repository secondary-worktree)
      (with-stubbed-fdefinition
          ((vcs-kit:make-vcs-repository
             (lambda (&rest arguments)
               (declare (ignore arguments))
               :command-backend))
           (vcs-kit:vcs-worktree
             (lambda (backend &rest arguments)
               (declare (ignore backend))
               (push (copy-list arguments) commands)
               :command-result))
           (nerimux/vcs:list-repository-worktrees
             (lambda (current) current))
           (nerimux/vcs:refresh-repository-status
             (lambda (current) current)))
        (expect (nerimux/vcs:delete-worktree secondary-worktree))
        (expect (nerimux/vcs:delete-worktree secondary-worktree :force t))
        (expect (nerimux/vcs:lock-worktree secondary-worktree :reason "reason"))
        (expect (nerimux/vcs:lock-worktree secondary-worktree :reason ""))
        (expect (nerimux/vcs:unlock-worktree secondary-worktree))
        (expect (eq :command-result
                    (nerimux/vcs:prune-worktrees
                     repository
                     :dry-run nil
                     :verbose t)))
        (expect
         (equal
          (list (list "remove" secondary-path
                      :execution-options execution-options)
                (list "remove" "--force" secondary-path
                      :execution-options execution-options)
                (list "lock" "--reason" "reason" secondary-path
                      :execution-options execution-options)
                (list "lock" secondary-path
                      :execution-options execution-options)
                (list "unlock" secondary-path
                      :execution-options execution-options)
                (list "prune" "--verbose"
                      :execution-options execution-options))
          (nreverse commands)))
        (let ((condition-seen nil))
          (handler-case
              (nerimux/vcs:delete-worktree main-worktree)
            (error (condition)
              (setf condition-seen condition)))
          (expect (typep condition-seen 'error))))))

  (it "bounds fake git worktree writes and disables terminal prompts"
    (let* ((directory (namestring (host-kit:temporary-directory)))
           (script (merge-pathnames "nerimux-fake-git-timeout.sh"
                                    (host-kit:temporary-directory)))
           (environment-file (merge-pathnames "nerimux-fake-git-environment"
                                              (host-kit:temporary-directory)))
           (repository
             (nerimux/workspace-model:make-repository
              :specification "workspace-owner/project"
              :local-path directory))
           (worktree
             (nerimux/workspace-model:make-worktree
              :repository repository
              :path (concatenate 'string directory "secondary")
              :branch "feature/ui"))
           (backend nil)
           (condition-seen nil))
      (with-open-file (stream script :direction :output :if-exists :supersede)
        (format stream "#!/bin/sh~%printf '%s' \"${GIT_TERMINAL_PROMPT-unset}\" > '~A'~%sleep 5~%"
                (namestring environment-file)))
      (uiop:run-program (list "chmod" "+x" (namestring script)))
      (setf backend
            (vcs-kit:make-vcs-repository
             directory
             :executable (namestring script)
             :default-timeout 30d0))
      (let ((nerimux/vcs::*worktree-operation-timeout-seconds* 0.1d0))
        (with-stubbed-fdefinition
            ((nerimux/vcs::%repository-backend
               (lambda (current)
                 (declare (ignore current))
                 backend)))
          (handler-case
              (nerimux/vcs::%delete-worktree-command worktree nil)
            (error (condition)
              (setf condition-seen condition)))))
      (expect (typep condition-seen 'vcs-kit:vcs-command-timeout-error))
      (with-open-file (stream environment-file :direction :input)
        (expect (string= "0" (read-line stream))))))

  (it "rejects invalid worktree and repository inputs before invoking VCS"
    (let* ((repository-path (%vcs-operations-existing-path))
           (repository
             (nerimux/workspace-model:make-repository
              :specification "workspace-owner/project"
              :local-path repository-path))
           (main-worktree
             (nerimux/workspace-model:make-worktree
              :repository repository
              :path repository-path
              :branch "main"))
           (same-path-worktree
             (nerimux/workspace-model:make-worktree
              :repository repository
              :path (copy-seq repository-path)
              :branch "main"))
           (calls 0))
      (nerimux/workspace-model:repository-add-worktree repository main-worktree)
      (with-stubbed-fdefinition
          ((vcs-kit:vcs-worktree
             (lambda (&rest arguments)
               (declare (ignore arguments))
               (incf calls))))
        (dolist (thunk
                 (list
                  (lambda () (nerimux/vcs:delete-worktree nil))
                  (lambda () (nerimux/vcs:lock-worktree nil))
                  (lambda () (nerimux/vcs:unlock-worktree nil))
                  (lambda () (nerimux/vcs:prune-worktrees nil))
                  (lambda () (nerimux/vcs:delete-worktree same-path-worktree))))
          (let ((condition-seen nil))
            (handler-case (funcall thunk)
              (error (condition) (setf condition-seen condition)))
            (expect (typep condition-seen 'error))))
        (expect (zerop calls))))))
(describe "vcs live-pane-delete attachment safety"
  (it "live-pane-delete rejects live panes before synchronous and asynchronous command dispatch even with force"
    (let* ((repository-path (%vcs-operations-existing-path))
           (repository
             (nerimux/workspace-model:make-repository
              :specification "workspace-owner/project"
              :local-path repository-path))
           (main-worktree
             (nerimux/workspace-model:make-worktree
              :repository repository :path repository-path :branch "main"))
           (worktree
             (nerimux/workspace-model:make-worktree
              :repository repository
              :path (concatenate 'string repository-path "attached")
              :branch "feature/attached"))
           (pane (make-pane :id 42 :fd 1))
           (commands nil)
           (refreshes 0))
      (nerimux/workspace-model:repository-add-worktree repository main-worktree)
      (nerimux/workspace-model:repository-add-worktree repository worktree)
      (nerimux/pane:worktree-add-pane worktree pane)
      (expect (nerimux/pane:pane-live-p pane))
      (with-stubbed-fdefinition
          ((vcs-kit:make-vcs-repository
             (lambda (&rest arguments)
               (declare (ignore arguments))
               :command-backend))
           (vcs-kit:vcs-worktree
             (lambda (backend &rest arguments)
               (declare (ignore backend))
               (push arguments commands)))
           (nerimux/vcs:list-repository-worktrees
             (lambda (current) (incf refreshes) current))
           (nerimux/vcs:refresh-repository-status
             (lambda (current) (incf refreshes) current)))
        (dolist (delete-command
                 (list (lambda (target force)
                         (nerimux/vcs:delete-worktree target :force force))
                       #'nerimux/vcs::%delete-worktree-command))
          (dolist (force '(nil t))
            (let ((condition-seen nil))
              (handler-case (funcall delete-command worktree force)
                (error (condition) (setf condition-seen condition)))
              (expect (typep condition-seen 'error))
              (expect (null commands))
              (expect (zerop refreshes))
              (expect (eq worktree (nerimux/pane:pane-worktree pane)))
              (expect (nerimux/pane:pane-live-p pane))))))))

  (it "live-pane-delete allows dead panes through synchronous and asynchronous command dispatch"
    (let* ((repository-path (%vcs-operations-existing-path))
           (secondary-path (concatenate 'string repository-path "dead-pane"))
           (repository
             (nerimux/workspace-model:make-repository
              :specification "workspace-owner/project"
              :local-path repository-path))
           (main-worktree
             (nerimux/workspace-model:make-worktree
              :repository repository :path repository-path :branch "main"))
           (worktree
             (nerimux/workspace-model:make-worktree
              :repository repository :path secondary-path :branch "feature/dead"))
           (pane (make-pane :id 43 :fd 0))
           (commands nil)
           (execution-options
             (nerimux/vcs::%worktree-operation-execution-options)))
      (nerimux/workspace-model:repository-add-worktree repository main-worktree)
      (nerimux/workspace-model:repository-add-worktree repository worktree)
      (nerimux/pane:worktree-add-pane worktree pane)
      (expect (not (nerimux/pane:pane-live-p pane)))
      (with-stubbed-fdefinition
          ((vcs-kit:make-vcs-repository
             (lambda (&rest arguments)
               (declare (ignore arguments))
               :command-backend))
           (vcs-kit:vcs-worktree
             (lambda (backend &rest arguments)
               (declare (ignore backend))
               (push arguments commands)))
           (nerimux/vcs:list-repository-worktrees
             (lambda (current) current))
           (nerimux/vcs:refresh-repository-status
             (lambda (current) current)))
        (dolist (delete-command
                 (list (lambda (target force)
                         (nerimux/vcs:delete-worktree target :force force))
                       #'nerimux/vcs::%delete-worktree-command))
          (dolist (force '(nil t))
            (expect (funcall delete-command worktree force))))
        (expect
         (equal (list (list "remove" secondary-path
                             :execution-options execution-options)
                      (list "remove" "--force" secondary-path
                            :execution-options execution-options)
                      (list "remove" secondary-path
                            :execution-options execution-options)
                      (list "remove" "--force" secondary-path
                            :execution-options execution-options))
                (nreverse commands)))))))
(describe "vcs live-pane-delete independent agent history"
  (it "live-pane-delete protects an agent pane outside panes until its fd closes"
    (let* ((repository-path (%vcs-operations-existing-path))
           (secondary-path (concatenate 'string repository-path "agent-history"))
           (repository
             (nerimux/workspace-model:make-repository
              :specification "workspace-owner/project"
              :local-path repository-path))
           (main-worktree
             (nerimux/workspace-model:make-worktree
              :repository repository :path repository-path :branch "main"))
           (agent-pane (make-pane :id 44 :fd 0 :agent-kind :codex
                                  :process-exited-p t))
           (worktree
             (nerimux/workspace-model:make-worktree
              :repository repository :path secondary-path :branch "feature/history"
              :agent-pane agent-pane))
           (commands nil)
           (refreshes 0)
           (execution-options
             (nerimux/vcs::%worktree-operation-execution-options)))
      (nerimux/workspace-model:repository-add-worktree repository main-worktree)
      (nerimux/workspace-model:repository-add-worktree repository worktree)
      (expect (null (nerimux/workspace-model:worktree-panes worktree)))
      (expect (eq agent-pane (nerimux/workspace-model:worktree-agent-pane worktree)))
      (with-stubbed-fdefinition
          ((vcs-kit:make-vcs-repository
             (lambda (&rest arguments)
               (declare (ignore arguments))
               :command-backend))
           (vcs-kit:vcs-worktree
             (lambda (backend &rest arguments)
               (declare (ignore backend))
               (push arguments commands)))
           (nerimux/vcs:list-repository-worktrees
             (lambda (current) (incf refreshes) current))
           (nerimux/vcs:refresh-repository-status
             (lambda (current) (incf refreshes) current)))
        (dolist (fd '(0 1))
          (setf (nerimux/pane:pane-fd agent-pane) fd)
          (expect (eql (not (null (nerimux/pane:pane-live-p agent-pane)))
                       (plusp fd)))
          (dolist (delete-command
                   (list (lambda (target force)
                           (nerimux/vcs:delete-worktree target :force force))
                         #'nerimux/vcs::%delete-worktree-command))
            (dolist (force '(nil t))
              (setf commands nil refreshes 0)
              (if (plusp fd)
                  (let ((condition-seen nil))
                    (handler-case (funcall delete-command worktree force)
                      (error (condition) (setf condition-seen condition)))
                    (expect (typep condition-seen 'error))
                    (expect (null commands))
                    (expect (zerop refreshes)))
                  (progn
                    (expect (funcall delete-command worktree force))
                    (expect (equal (list (if force
                                            (list "remove" "--force" secondary-path
                                                  :execution-options execution-options)
                                            (list "remove" secondary-path
                                                  :execution-options execution-options)))
                                   commands))))
              (expect (null (nerimux/workspace-model:worktree-panes worktree)))
              (expect (eq agent-pane
                          (nerimux/workspace-model:worktree-agent-pane worktree)))
              (expect (= fd (nerimux/pane:pane-fd agent-pane))))))))))
