(require :asdf)

(require :sb-cover)

(asdf:load-system "sb-cover")

(defconstant +coverage-test-timeout-ms+
  ;; A coverage run is bounded by the caller, but a stuck individual test must
  ;; not consume that whole budget.  This is deliberately shorter than the
  ;; 45-minute process limit used by the flake job.
  300000)

(defun %coverage-test-timeout-ms ()
  (let* ((value (uiop:getenv "NERIMUX_COVERAGE_TEST_TIMEOUT_MS"))
         (timeout (if (and value (plusp (length value)))
                      (parse-integer value :junk-allowed nil)
                      +coverage-test-timeout-ms+)))
    (unless (and (integerp timeout) (plusp timeout)
                 (<= timeout +coverage-test-timeout-ms+))
      (error "NERIMUX_COVERAGE_TEST_TIMEOUT_MS must be in 1..~D, got ~S."
             +coverage-test-timeout-ms+
             value))
    timeout))

(defun %coverage-test-name-filter ()
  (let ((filter (uiop:getenv "CL_WEAVE_TEST_FILTER")))
    (cond ((null filter) nil)
          ((string= filter "") nil)
          (t filter))))

(defun %ensure-full-coverage (statistics)
  (loop for (kind covered-key total-key) in '((:expression :expression-covered
                                                           :expression-total)
                                              (:branch :branch-covered
                                                       :branch-total))
        for covered = (getf statistics covered-key)
        for total = (getf statistics total-key)
        unless (= covered total)
          do (error "Coverage threshold failed for ~A: ~D/~D covered."
                    kind
                    covered
                    total))
  statistics)

(defun %coverage-prefix-p (prefix string)
  (and (>= (length string) (length prefix))
       (string-equal prefix string :end2 (length prefix))))

(defun %coverage-structural-path-p (source source-maps path)
  (let* ((path (reverse path))
         (top-level-index (car path)))
    (when (and (integerp top-level-index)
               (every #'integerp path))
      (let* ((top-level-form (nth top-level-index source-maps))
             (locations (and top-level-form
                             (gethash (car top-level-form)
                                      (cdr top-level-form)))))
        (some (lambda (location)
                (destructuring-bind (start end &optional ignored) location
                  (declare (ignore ignored))
                  (let ((text (string-left-trim '(#\Space #\Tab #\Newline #\Return)
                                                (subseq source (1- start) end))))
                    (or (%coverage-prefix-p "(in-package" text)
                        (%coverage-prefix-p "(cl:in-package" text)
                        (%coverage-prefix-p "(declaim" text)
                        (%coverage-prefix-p "(cl:declaim" text)))))
              locations)))))

(defun %normalize-structural-coverage ()
  ;; SB-COVER records top-level IN-PACKAGE and DECLAIM forms as expressions,
  ;; although neither form has executable coverage to exercise. Mark only
  ;; those source paths covered, keeping every executable form in the gate.
  (sb-cover::refresh-coverage-bits)
  (let ((coverage-info (car sb-cover::*code-coverage-info*))
        (normalized 0))
    (maphash
     (lambda (filename file)
       (let* ((source (sb-cover::read-source filename :default))
              (source-maps (sb-cover::read-and-record-source-maps source))
              (paths (sb-c::covered-file-paths file))
              (executed (sb-c::covered-file-executed file)))
         (dotimes (index (length paths))
           (when (%coverage-structural-path-p source source-maps (aref paths index))
             (unless (= 1 (sbit executed index))
               (incf normalized)
               (setf (sbit executed index) 1))))))
     coverage-info)
    (format t "Normalized ~D structural coverage paths.~%" normalized))
  t)

(defparameter *coverage-excluded-source-files*
  '("src/main-startup-flags.lisp"
    "src/main-startup-data.lisp"
    "src/main-startup-socket-data.lisp"
    "src/main-startup-socket-macros.lisp"
    "src/runtime-reader-data.lisp"
    "src/server-data.lisp"
    "src/workspace-window-data.lisp"
    "src/server-multi-dispatch-prefix-data.lisp"
    "src/server-multi-dispatch-tree-filter-data.lisp"
    "src/server-multi-dispatch-command-input-data.lisp"
    "src/runtime-data.lisp"
    "src/package.lisp"
    "src/server-multi-state.lisp"
    "src/server-multi-transient-data.lisp"
    "src/server-multi-data.lisp"
    "src/server-dispatch-macros.lisp"
    "packages/terminal/src/csi-replies-definitions.lisp"
    "packages/terminal/src/char-write-definitions.lisp"
    "packages/terminal/src/modes-ansi-sm-rm-definitions.lisp"
    "packages/terminal/src/modes-charset-definitions.lisp"
    "packages/terminal/src/modes-dec-pm-definitions.lisp"
    "packages/terminal/src/screen-data.lisp"
    "packages/model/src/window-definitions.lisp"
    "packages/ports/src/posix-port.lisp"
    "packages/pty/src/pty-ffi.lisp"
    "packages/renderer/src/renderer-format-definitions.lisp"
    "packages/renderer/src/renderer-style-data.lisp"))

#+sbcl
(sb-ext:restrict-compiler-policy 'sb-cover:store-coverage-data 3)

(proclaim '(optimize (sb-cover:store-coverage-data 3)))

(defmethod asdf:perform :around ((operation asdf:compile-op)
                                 (component asdf:cl-source-file))
  (declare (ignore operation component))
  (proclaim '(optimize (sb-cover:store-coverage-data 3)))
  (unwind-protect (call-next-method)
    (proclaim '(optimize (sb-cover:store-coverage-data 0)))))

(defparameter *nerimux-project-root*
  (truename
   (merge-pathnames #P"../" (uiop:pathname-directory-pathname *load-truename*))))

(defparameter *nerimux-source-root*
  (truename (merge-pathnames #P"src/" *nerimux-project-root*)))

(defparameter *nerimux-coverage-source-roots*
  (cons *nerimux-source-root*
        (sort
         (directory (merge-pathnames #P"packages/*/src/"
                                     *nerimux-project-root*))
         #'string<
         :key #'namestring)))

(defun %coverage-events (events)
  (cl-weave::normalize-run-results events))

(defun %coverage-assertion-count (events)
  (loop for event in (%coverage-events events)
        sum (count :assertion
                   (cl-weave::test-event-journal event)
                   :key #'cl-weave:journal-frame-kind)))

(defun %coverage-test-plan-count (plan)
  (count :run plan :key #'cl-weave:test-plan-entry-status))

(push *nerimux-project-root* asdf:*central-registry*)

(dolist 
    (dir
     (uiop:split-string (or (uiop:getenv "NERIMUX_SIBLING_REGISTRY") "")
                        :separator
                        ":"))
  (unless (string= dir "")
    (push (truename (uiop:ensure-directory-pathname dir))
          asdf:*central-registry*)))

(asdf:load-system "sb-cover")
(asdf:load-system "cl-weave")

(cl-weave:reset-coverage)

(asdf:clear-system "nerimux")

(asdf:compile-system "nerimux" :force t)

(asdf:load-system "nerimux" :force t)

(asdf:clear-system "nerimux/test")

(asdf:compile-system "nerimux/test" :force t)

(let* ((excluded-source-pathnames
         (mapcar (lambda (relative-path)
                   (let ((absolute (merge-pathnames (pathname relative-path)
                                                    *nerimux-project-root*)))
                     (or (probe-file absolute)
                         (error "~S names ~A, which does not exist. ~
                                 Update *coverage-excluded-source-files*."
                                '*coverage-excluded-source-files*
                                relative-path))))
                 *coverage-excluded-source-files*))
       (source-roots *nerimux-coverage-source-roots*)
       (test-timeout-ms (%coverage-test-timeout-ms))
       (report-dir (uiop:ensure-directory-pathname
                    (or (first (uiop:command-line-arguments))
                        "coverage-report/")))
       (report-index (merge-pathnames "cover-index.html" report-dir))
       (enforce-thresholds-p
         (not (string= "1" (or (uiop:getenv "NERIMUX_COVERAGE_REPORT_ONLY") "")))))
  (asdf:load-system "nerimux/test")
  (let* ((name-filter (%coverage-test-name-filter))
         (plan (cl-weave:collect-test-plan
                (cl-weave:root-suite)
                :name-filter name-filter
                :timeout-ms test-timeout-ms))
         (selected-count (%coverage-test-plan-count plan)))
    (unless (plusp selected-count)
      (error "coverage run selected no runnable tests (filter ~S)." name-filter))
    (format t "Coverage tests selected: ~D (timeout ~D ms).~%"
            selected-count test-timeout-ms)
    (let ((events (let ((*print-circle* t)
                        (cl-weave:*journal-enabled* t))
                    (cl-weave:run (cl-weave:root-suite)
                                  :reporter :spec
                                  :max-workers 1
                                  :name-filter name-filter
                                  :timeout-ms test-timeout-ms))))
      (unless (cl-weave:results-status events)
        (error "nerimux test suite failed under coverage instrumentation"))
      (let ((assertion-count (%coverage-assertion-count events)))
        (unless (plusp assertion-count)
          (error "coverage run executed no assertions."))
        (format t "Coverage assertions executed: ~D.~%" assertion-count))))
  (%normalize-structural-coverage)
  (cl-weave::save-coverage-report
   report-dir
   :include-pathnames source-roots
   :exclude-pathnames excluded-source-pathnames)
  (let ((report-bytes
          (and (probe-file report-index)
               (with-open-file (stream report-index
                                       :element-type '(unsigned-byte 8))
                 (file-length stream)))))
    (unless (and report-bytes (plusp report-bytes))
      (error "coverage run did not produce a non-empty ~A" report-index))
    (format t "Coverage report bytes: ~D.~%" report-bytes))
  (when enforce-thresholds-p
    (%ensure-full-coverage
     (cl-weave:coverage-statistics
      :include-pathnames source-roots
      :exclude-pathnames excluded-source-pathnames)))
  (format t "~&Coverage source roots: ~D; report: ~A~%"
          (length source-roots) report-dir))

(uiop:quit 0)
