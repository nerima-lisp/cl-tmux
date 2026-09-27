(in-package #:nerimux)

(defmacro %startup-mode (mode-name handler &key raw-args-p)
  `(list ,mode-name
         ',handler
         ,@(when raw-args-p
             '(:raw-args-p t))))

(defparameter *startup-modes*
  (list (%startup-mode "server" run-server)
        (%startup-mode "attach" run-attach-simple :raw-args-p t)
        (%startup-mode "kill" run-kill :raw-args-p t)
        (%startup-mode "doctor" run-doctor :raw-args-p t)
        (%startup-mode "-V" run-version :raw-args-p t)
        (%startup-mode "--version" run-version :raw-args-p t)
        (%startup-mode "-h" run-usage :raw-args-p t)
        (%startup-mode "--help" run-usage :raw-args-p t))
  "Mode-name to handler metadata for the binary entry point.")

(defparameter *diagnostic-logger*
  (log-kit:make-logger
   :name "nerimux"
   :handler (make-instance 'log-kit:text-handler :stream *error-output*)
   :level log-kit:+level-info+)
  "Structured logger for command and server startup diagnostics.")

(defun %diagnostic-log (level message &optional fields)
  (log-kit:emit-log *diagnostic-logger* level message fields))
