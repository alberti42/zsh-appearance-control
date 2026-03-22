;;; zac-theme-autodetection.el --- Appearance sync via zsh-appearance-control -*- lexical-binding: t; -*-

;; Generic module for reacting to OS appearance changes signalled by
;; zsh-appearance-control: https://github.com/alberti42/zsh-appearance-control
;;
;; zsh-appearance-control plugin writes a single-character state file:
;; - "1" => dark
;; - "0" => light
;;
;; This module watches that file and invokes `zac-load-theme-callback' when the
;; appearance changes.  All color and theme choices live in that callback; this
;; module contains none.

;;; Commentary:
;;
;; Usage:
;; - Set `zac-load-theme-callback' to a function (lambda (appearance) ...) before
;;   loading this module.
;; - The watcher starts automatically on load.
;;
;; Environment:
;; - If $ZAC_CACHE_DIR is set, we read "$ZAC_CACHE_DIR/appearance".
;; - Otherwise we read "$XDG_CACHE_HOME/zac/appearance" or "~/.cache/zac/appearance".

;;; Code:

(defvar zac--watch nil
  "File notification descriptor for the appearance state file, or nil if inactive.")

(defvar zac-load-theme-callback nil
  "Function called by `zac--apply-appearance' to load the appropriate theme.
It receives :light or :dark for the respective appearance.
Example:
  (setq zac-load-theme-callback
        (lambda (appearance)
          (load-theme (if (eq appearance :light)
                          'modus-operandi
                        'modus-vivendi-tinted) t)
          ))")

(defun zac--appearance-file ()
  "Return the path to zsh-appearance-control's appearance state file."
  (expand-file-name
   "appearance"
   (or (getenv "ZAC_CACHE_DIR")
       (expand-file-name "zac" (or (getenv "XDG_CACHE_HOME")
                                   (expand-file-name "~/.cache"))))))

(defun zac--read-appearance ()
  "Read the appearance state file and return :dark, :light, or nil."
  (when (file-readable-p (zac--appearance-file))
     (with-temp-buffer
       (insert-file-contents (zac--appearance-file))
       (if (equal (string-trim (buffer-string)) "1") :dark :light))))

(defun zac--apply-appearance ()
  "Read the current appearance and invoke the user-supplied callback
function `zac-load-theme-callback'."
  ;; Load the appropriate theme based on OS appearance via user-supplied callback.
  ;; theme-harmonize-theme fires automatically via enable-theme-functions
  ;; inside load-theme, so no explicit call is needed here.
  (let ((appearance (zac--read-appearance)))
    (when zac-load-theme-callback
      (funcall zac-load-theme-callback appearance))))


(defun zac-watch-start ()
  "Start watching zsh-appearance-control's appearance file."
  (interactive)
  (zac--apply-appearance)
  ;; Re-apply appearance settings for any new frame (emacsclient / daemon mode).
  (add-hook 'after-make-frame-functions
            (lambda (frame)
              (with-selected-frame frame
                (zac--apply-appearance))))
  (if (fboundp 'file-notify-add-watch)
      (unless zac--watch
        (setq zac--watch
              (file-notify-add-watch
               (zac--appearance-file)
               '(change)
               (lambda (_event)
                 (zac--apply-appearance)))))
    (message "zac: file notifications not supported. Appearance is applied once, \
but there is no automatic mechanism to synchronize it with the OS appearance."))
  nil)

(defun zac-watch-stop ()
  "Stop watching zsh-appearance-control's appearance file."
  (interactive)
  (when zac--watch
    (file-notify-rm-watch zac--watch)
    (setq zac--watch nil)))

;; Start watcher automatically.
(zac-watch-start)

(provide 'zac-theme-autodetection)

;;; zac-theme-autodetection.el ends here
