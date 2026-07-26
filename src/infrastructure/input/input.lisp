(in-package #:cl-tmux/input)

;;;; Keyboard input: raw-mode wrapper and non-blocking stdin reads.
;;;;
;;;; We read from fd 0 (stdin) via select+CFFI rather than through a Lisp
;;;; stream because Lisp streams may buffer; we need single bytes.

;;; ── Raw-mode convenience macro ─────────────────────────────────────────────

(defmacro with-raw-mode (&body body)
  "Execute BODY with stdin in raw mode, restoring the terminal on exit.
   ENABLE-RAW-MODE! runs OUTSIDE the unwind-protect deliberately: cl-tty-kit's
   enable-raw-mode only records fd 0 as raw AFTER its TCSETATTR syscall
   succeeds, so if it signals an error the terminal was never actually put
   into raw mode and there is nothing to restore. A handler-bind safety net
   used to call disable-raw-mode! unconditionally here, but handler-bind
   runs its handler BEFORE unwinding the stack — if enable-raw-mode! itself
   was the one signalling (still holding cl-tty-kit's internal raw-mode
   lock), that handler's disable-raw-mode! call recursed on the same lock
   from the same thread, crashing with a masking \"recursive lock attempt\"
   error instead of the real one."
  `(progn
     (enable-raw-mode! 0)        ; fd 0 = stdin
     (unwind-protect
          (progn ,@body)
       (disable-raw-mode! 0)
       ;; Move cursor to a clean line after restoring
       (format t "~%")
       (force-output))))

;;; ── Non-blocking byte read ─────────────────────────────────────────────────

(defun read-byte-nonblock (&optional (timeout-us +poll-timeout-us+))
  "Return a byte (0–255) from stdin within TIMEOUT-US microseconds, or NIL.
   NIL means the timeout elapsed with no data — it does NOT mean EOF.
   EOF on stdin is indistinguishable from a zero-byte read at this layer;
   both return NIL.  TIMEOUT-US = 0 is a purely non-blocking poll."
  (declare (type fixnum timeout-us))
  (let ((ready (cl-tmux/pty:select-fds (list 0) timeout-us)))
    (when ready
      ;; Read exactly one byte from fd 0 directly (bypasses Lisp buffering).
      (cffi:with-foreign-object (buf :uint8)
        (let ((n (cffi:foreign-funcall "read"
                                       :int 0 :pointer buf :unsigned-long 1
                                       :long)))
          (when (= n 1)
            (cffi:mem-ref buf :uint8)))))))
