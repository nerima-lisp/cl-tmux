(in-package #:nerimux)

(defun %worktree-display-path (path)
  "PATH with the ghq root elided (PC-11).  The root is the same for every
   worktree here, so spending the width on it is what pushes the part that
   says which worktree was created off the message line."
  (let ((root (and (stringp path)
                   (string-right-trim "/" (or (nerimux/vcs:ghq-root-directory) "")))))
    (if (and root
             (plusp (length root))
             (> (length path) (1+ (length root)))
             (string= root path :end2 (length root)))
        (subseq path (1+ (length root)))
        path)))

(defun %client-create-worktree-now (repository branch
                                               conn
                                               session
                                               &key
                                               path
                                               force)
  (let ((display-branch (%strip-argument-control-characters branch)))
  (%client-notify conn (format nil "creating worktree ~A" display-branch))
  (%mark-workspace-refreshing :repository
                              (nerimux/workspace-model:repository-id repository))
  (let ((job (%workspace-job-begin :repository (repository-id repository) :create repository)))
  (flet ((%on-error (condition)
           (%workspace-job-update job repository :failed :outcome condition)
           (%clear-workspace-refreshing :repository
                                        (nerimux/workspace-model:repository-id
                                         repository)
                                        :stale-p
                                        t)
           (%client-log-process conn
                                (format nil "git worktree add -b ~A" display-branch)
                                nil
                                (princ-to-string condition))
           (%client-notify conn
                           (format nil "worktree create failed: ~A" condition))
           (%mark-dirty)))
    (handler-case (nerimux/vcs:create-worktree-async repository
                                                     :branch
                                                     branch
                                                     :path
                                                     path
                                                     :force
                                                     force
                                                     :callback-dispatch
                                                     #'%enqueue-main-thread-callback
                                                     :on-start
                                                     (lambda () (%workspace-job-update job repository :running))
                                                     :on-complete
                                                     (lambda (worktree)
                                                       (%workspace-job-update job repository :succeeded)
                                                       (%clear-workspace-refreshing
                                                        :repository
                                                        (nerimux/workspace-model:repository-id
                                                         repository))
                                                       (when
                                                           (%client-live-p conn)
                                                         (%set-client-selected-worktree
                                                          conn
                                                          worktree)
                                                         (%note-worktree-layout
                                                          conn repository
                                                          (nerimux/workspace-model:worktree-path
                                                           worktree))
                                                         (when session
                                                           (%open-client-worktree-pane
                                                            session
                                                            conn
                                                            worktree)))
                                                       (%refresh-client-picker
                                                        conn)
                                                       (%client-log-process
                                                        conn
                                                        (format nil "git worktree add -b ~A ~A"
                                                                display-branch
                                                                (nerimux/workspace-model:worktree-path
                                                                 worktree))
                                                        t
                                                        "")
                                                       (%client-notify
                                                        conn
                                                        (format nil "worktree created: ~A"
                                                                (%worktree-display-path
                                                                 (nerimux/workspace-model:worktree-path
                                                                  worktree))))
                                                       (%mark-dirty))
                                                     :on-error
                                                     #'%on-error)
      (error (condition)
        (%on-error condition))))))
  t)

(defun %existing-path-prefix-truename (path)
  "Resolve the longest existing prefix of PATH, including symlinks."
  (loop with candidate = (if (pathnamep path)
                             path
                             (uiop:parse-native-namestring path))
        do (handler-case
               (return (truename candidate))
             (file-error ()
               (let ((parent
                       (make-pathname
                        :directory (butlast (pathname-directory candidate))
                        :name nil
                        :type nil
                        :defaults candidate)))
                 (when (equal parent candidate)
                   (return nil))
                 (setf candidate parent))))))

(defun %path-under-directory-p (path directory)
  (let ((path (string-right-trim "/" (namestring path)))
        (directory (string-right-trim "/" (namestring directory))))
    (or (string= path directory)
        (and (> (length path) (length directory))
             (char= (char path (length directory)) #\/)
             (string= directory path :end2 (length directory))))))

(defun %worktree-path-escapes-repository-p (repository path)
  "True when PATH's resolved existing prefix is outside its worktree parent."
  (or (member ".." (uiop:split-string path :separator '(#\/)) :test #'string=)
      (let* ((pathname (uiop:parse-native-namestring path))
             (pathname (if (eq :absolute (first (pathname-directory pathname)))
                           pathname
                           (merge-pathnames
                            pathname
                            (uiop:ensure-directory-pathname
                             (nerimux/workspace-model:repository-local-path
                              repository)))))
             (candidate (%existing-path-prefix-truename pathname))
            (parent (ignore-errors
                      (truename
                       (uiop:parse-native-namestring
                        (nerimux/vcs:worktree-parent-directory repository))))))
        (not (and candidate parent
                  (%path-under-directory-p candidate parent))))))

(defun %client-create-worktree (conn target args)
  (if (not (%client-boolean-option-p args '("--confirm" "confirm")))
      (progn
        (%client-notify conn "wt-create: add --confirm to run")
        t)
      (let* ((repository (%client-selected-repository conn target))
             (branch (or (%client-option-value args
                                               '("--branch" "-b" "branch"))
                         (%client-positional-branch args)))
             (path (%client-option-value args '("--path" "path")))
             (force (%client-boolean-option-p args '("--force" "force"))))
        (cond
          ((not repository)
           (%client-notify conn "worktree create requires a repository")
           t)
          ((not (and (stringp branch) (plusp (length branch))))
           (%client-notify conn "worktree create requires a branch")
           t)
          ((%dash-leading-name-p branch)
           (%client-notify conn "a name cannot start with -")
           t)
          ((not (nerimux/vcs:vcs-package-available-p))
           (%client-notify conn "VCS unavailable")
           t)
          ((and (stringp path) (%dash-leading-name-p path))
           (%client-notify conn "a path cannot start with -")
           t)
          ((and (stringp path) (%worktree-path-escapes-repository-p repository path))
           (%client-notify conn "path must stay under the repository")
           t)
          (t
           (%client-create-worktree-now
            repository branch conn (%attach-target-session)
            :path path :force force))))))
