(in-package #:nerimux)

(defun %pane-retired-p (pane)
  (or (not (plusp (pane-fd pane)))
      (and *reader-process-generation*
           (not (eq *reader-process-generation*
                    (nerimux/pane:pane-process-generation pane))))))

(defun %reader-idle-wait ()
  (sleep (/ +pty-poll-timeout-us+ 1000000)))

(defun %linux-pty-read-eof-p (condition)
  #+linux
  (let ((reason (cl-tty-kit:pty-operation-failed-reason condition)))
    (and (eq :fd-read
             (cl-tty-kit:pty-operation-failed-operation condition))
         (search "errno 5)" (princ-to-string reason))))
  #-linux
  (declare (ignore condition))
  #-linux
  nil)

(defun reader-idle-state (pane)
  (let ((next
          (cl-concurrent-kit:with-lock-held ((nerimux/pane:pane-process-lock pane))
            (cond
              ((%pane-retired-p pane) nil)
              ((select-fds (list (pane-fd pane)) 0) #'reader-reading-state)
              (t #'reader-idle-state)))))
    ;; A polling wait under the process lock can starve close indefinitely.
    (when (eq next #'reader-idle-state)
      (%reader-idle-wait))
    next))

(defun reader-reading-state (pane)
  (cl-concurrent-kit:with-lock-held ((nerimux/pane:pane-process-lock pane))
    (unless (%pane-retired-p pane)
      (let ((bytes
              (handler-case
                  (pty-read-blocking-into (pane-fd pane) *reader-scratch-buffer*)
                (cl-tty-kit:pty-operation-failed (condition)
                  (if (%linux-pty-read-eof-p condition)
                      nil
                      (error condition))))))
        (if (null bytes)
            #'reader-eof-state
            (progn
              (handler-case (pane-feed pane bytes)
                (peer-io-failure () nil))
              (nerimux/pane:pane-mark-output pane bytes)
              (when (nerimux/terminal:screen-bell-pending
                     (nerimux/pane:pane-screen pane))
                (nerimux/pane:pane-mark-bell pane))
              (%mark-dirty)
              #'reader-idle-state))))))

(defun reader-eof-state (pane)
  (cl-concurrent-kit:with-lock-held ((nerimux/pane:pane-process-lock pane))
    (unless (%pane-retired-p pane)
      (nerimux/commands::%close-pane-pty-locked pane)))
  (%mark-dirty)
  nil)

(defun %run-reader-states (pane initial-state)
  "Drive the CPS reader state machine for PANE starting from INITIAL-STATE."
  (loop for state = initial-state then (funcall state pane)
        while (and *running* state)))

(defun %pane-reader-loop (pane)
  "Feed PTY output into PANE screen until EOF or *running* becomes NIL."
  (let ((*reader-scratch-buffer*
          (make-array +pty-buf-size+ :element-type '(unsigned-byte 8))))
    (%run-reader-states pane #'reader-idle-state)))

(defun start-reader-thread (pane)
  "Bind this reader to the process generation present at creation."
  (let ((generation (nerimux/pane:pane-process-generation pane)))
    (make-thread
     (lambda ()
       (let ((*reader-process-generation* generation))
         (handler-case
             (%pane-reader-loop pane)
           (error (condition)
             (nerimux/pane:pane-mark-process-exit
              pane
              :reason (format nil "reader thread failed: ~A" condition))))))
     :name (format nil "pty-reader-~D" (pane-id pane)))))

(defun stop-reader-threads (threads)
  "Signal shutdown and join each thread in THREADS with a bounded timeout."
  (setf *running* nil)
  (dolist (thread threads)
    (handler-case (%join-thread-with-timeout thread
                                             +reader-thread-join-timeout+)
      (sb-thread:join-thread-error ()
        nil))))
