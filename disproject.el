;;; disproject.el --- Dispatch project commands with Transient  -*- lexical-binding: t; -*-

;; Copyright (C) 2024 aurtzy
;; Copyright (C) 2008-2023 The Magit Project Contributors
;; Copyright (C) 2015-2024 Free Software Foundation, Inc.

;; Author: aurtzy <aurtzy@gmail.com>
;; URL: https://github.com/aurtzy/disproject
;; Keywords: convenience, project
;; Package-Version: 0.1.0

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Disproject is a `transient.el' interface that provides integration with
;; `project.el' for managing and interacting with projects.  It is similar to
;; (and inspired by) the function `project-switch-project', but attempts to make
;; it more convenient than just a Transient-ified version.

;;; Code:

(require 'grep)
(require 'pcase)
(require 'map)
(require 'project)
(require 'transient)

;;;
;;; Macros.
;;;

(defmacro disproject--with-environment (&rest body)
  "Run BODY with `disproject' \"environment\" options set."
  ;; Define variables that determine the environment.
  `(let ((from-directory (or (disproject--from-directory)
                             default-directory))
         (prefer-other-window (disproject--prefer-other-window))
         ;; Only enable envrc if the initial environment has it enabled.
         (enable-envrc (and (bound-and-true-p envrc-mode)
                            (symbol-function 'envrc-mode)))
         ;; Save the environment to restore in case of problem.
         (old-default-directory default-directory)
         (old-project-current-directory-override
          project-current-directory-override)
         (old-display-buffer-overriding-action
          display-buffer-overriding-action))
     (unwind-protect
         ;; Don't let the current buffer affect execution in case it's not
         ;; related to the project.
         (with-temp-buffer
           (let ((default-directory from-directory)
                 ;; This handles edge cases with `project' commands.
                 (project-current-directory-override from-directory)
                 (display-buffer-overriding-action
                  (and prefer-other-window '(display-buffer-use-some-window
                                             (inhibit-same-window t)))))
             ;; Make sure commands are run in the correct direnv environment
             ;; if envrc-mode is enabled.
             (when enable-envrc (funcall enable-envrc))
             ,@body))
       (setq default-directory
             old-default-directory
             project-current-directory-override
             old-project-current-directory-override
             display-buffer-overriding-action
             old-display-buffer-overriding-action))))


;;;
;;; Global variables.
;;;

(defgroup disproject nil
  "Transient interface for managing and interacting with projects."
  :group 'convenience
  :group 'project)

(defcustom disproject-compile-suffixes '(("c" "make" "make -k"
                                          :description "Make"))
  "Commands for the `disproject-compile' prefix.

The value should be a list of transient-like specification
entries (KEY IDENTIFIER COMPILE-COMMAND {PROPERTY VALUE} ...).

KEY is the keybind that will be used in the Transient menu.

IDENTIFIER is used in the compilation buffer name.  This should
be unique, but it may be useful to use the same identifier as
another command if one wants certain project compilation commands
as incompatible (only one runs at a given time).

COMPILE-COMMAND is passed to `compile' as the shell command to
run.

Optional properties can be set after COMPILE-COMMAND through
keywords.

:description is the only valid property.  It is used as the
transient command description.  If this is not specified, then
COMPILE-COMMAND will be used instead.

For example, the following may be used as a dir-locals.el value
for `disproject-compile-suffixes' to add \"make -k\" and
\"guile --help\" in a particular project:

  ((\"m\" \"make\"
    \"echo Running make...; make -k\"
    :description \"Make\")
   (\"g\" \"guile-help\"
    \"echo Get some help from Guile...; guile --help\"
    :description \"/Compile/ some help from Guile!\")))"
  :type '(repeat (list (string :tag "Key bind")
                       (string :tag "Identifier")
                       (string :tag "Shell command")
                       (plist :inline t
                              :tag "Properties"
                              :key-type (const :description)
                              :value-type string)))
  :group 'disproject)

(defcustom disproject-find-file-command
  (lambda ()
    (interactive)
    (let* ((project (project-current t))
           (dirs (list default-directory)))
      (project-find-file-in (thing-at-point 'filename)
                            dirs
                            project
                            ;; TODO: Support some way of enabling INCLUDE-ALL
                            ;; include-all
                            )))
  "The command used for opening a file in a project.

This is called whenever the function `disproject-find-file' is
invoked."
  :type 'function
  :group 'disproject)

(defcustom disproject-find-regexp-command
  ;; Modified version of `project-find-regexp' from `project.el'.
  (lambda (regexp)
    (interactive (list (project--read-regexp)))
    (xref-show-xrefs
     (apply-partially #'project--find-regexp-in-files
                      regexp
                      (project--files-in-directory default-directory nil))
     nil))
  "The command used for finding regexp matches in a project.

This is called whenever the function `disproject-find-regexp' is
invoked."
  :type 'function
  :group 'disproject)

(defcustom disproject-shell-command
  ;; Modified version of `project-eshell' from `project.el'.
  (lambda ()
    (interactive)
    (let* ((eshell-buffer-name (project-prefixed-buffer-name "eshell"))
           (eshell-buffer (get-buffer eshell-buffer-name)))
      (if (and eshell-buffer (not current-prefix-arg))
          (pop-to-buffer eshell-buffer
                         (bound-and-true-p display-comint-buffer-action))
        (eshell t))))
  "The command used for opening a shell in a project.

This is called whenever the function `disproject-shell-command'
is invoked."
  :type 'function
  :group 'disproject)

(defcustom disproject-switch-to-buffer-command #'project-switch-to-buffer
  "The command used for switching project buffers.

This is called whenever the function
`disproject-switch-to-buffer' is invoked."
  :type 'function
  :group 'disproject)


;;;
;;; Prefixes.
;;;

;;;###autoload (autoload 'disproject "disproject" nil t)
(transient-define-prefix disproject ()
  "Dispatch some command for a project."
  ["Options"
   ("p" "Switch project" disproject:--root-directory)
   ("d" "From directory" disproject:--from-directory)
   ("o" "Prefer other window" "--prefer-other-window")]
  ["Project commands"
   :pad-keys t
   [("B" "Buffer list" disproject-list-buffers)
    ("b" "Switch buffer" disproject-switch-to-buffer)]
   [("k" "Kill buffers" disproject-kill-buffers)
    ("m" "Magit status" disproject-magit-status
     :if (lambda () (featurep 'magit)))]]
  ["From directory"
   :pad-keys t
   [("c" "Compile" disproject-compile)
    ("D" "Dired" disproject-dired)
    ("s" "Shell" disproject-shell)]
   [("v" "VC dir" disproject-vc-dir)
    ("!" "Run" disproject-shell-command)
    ("M-x" "Extended command" disproject-execute-extended-command)]]
  ["Find"
   [("f" "file" disproject-find-file)]
   [("g" "regexp" disproject-find-regexp)]])

(transient-define-prefix disproject-compile ()
  "Dispatch compilation commands.

This prefix can be configured with `disproject-compile-suffixes'."
  ["Compile"
   :class transient-column
   :setup-children disproject-compile--setup-suffixes])


;;;
;;; Infix handling.
;;;

(transient-define-infix disproject:--root-directory ()
  :class transient-option
  :argument "--root-directory="
  :init-value (lambda (obj)
                (oset obj value (disproject--find-root-directory
                                 default-directory)))
  :always-read t
  :reader (lambda (&rest _ignore)
            (disproject--find-root-directory (project-prompt-project-dir))))

(defun disproject--find-root-directory (directory &optional silent)
  "Attempt to find project root directory from DIRECTORY.  May return nil.

A message is printed if no root directory can be found.  SILENT
may be set to a non-nil value to suppress it."
  (if-let ((directory (directory-file-name (file-truename directory)))
           (project (project-current nil directory))
           (root-directory (project-root project)))
      (progn
        (project-remember-project project)
        root-directory)
    (unless silent
      (message "No parent project found for %s"
               directory))
    nil))

(defun disproject--root-directory ()
  "Return the project root directory defined in transient arguments."
  (if-let ((args (transient-args transient-current-command))
           (root-dir (transient-arg-value "--root-directory=" args)))
      root-dir
    (project-root (project-current t))))

(defclass disproject-option-switches (transient-switches)
  ()
  "Class used for a set of switches where exactly one is selected.")

(cl-defmethod transient-infix-read ((obj disproject-option-switches))
  "Cycle through mutually exclusive switch options from OBJ.

This method skips over nil, so exactly one switch of this object
is always selected."
  (let ((choices (mapcar (apply-partially #'format (oref obj argument-format))
                         (oref obj choices))))
    (if-let ((value (oref obj value))
             (next-value (cadr (member value choices))))
        next-value
      (car choices))))

(transient-define-infix disproject:--from-directory ()
  :class disproject-option-switches
  :argument-format "--from-%s-directory"
  :argument-regexp "\\(--from-\\(root\\|sub\\)-directory\\)"
  :init-value (lambda (obj)
                (oset obj value "--from-root-directory"))
  :choices '("root" "sub"))

(defun disproject--prompt-directory (root-directory)
  "Prompt for a subdirectory in project and return the selected path.

ROOT-DIRECTORY is used to determine the project."
  ;; XXX: This is based on `project-find-dir' in project.el, which has an issue
  ;; of not displaying empty directories.
  (let* ((project (project-current nil root-directory))
         (all-files (project-files project))
         (completion-ignore-case read-file-name-completion-ignore-case)
         (all-dirs (mapcar #'file-name-directory all-files)))
    (funcall project-read-file-name-function
             "Select directory"
             ;; Some completion UIs show duplicates.
             (delete-dups all-dirs)
             nil 'file-name-history)))

(defun disproject--from-directory ()
  "Return the working directory to be used for `disproject' commands."
  (let ((args (transient-args transient-current-command))
        (root-directory (disproject--root-directory)))
    (cond
     ((transient-arg-value "--from-root-directory" args)
      root-directory)
     ((transient-arg-value "--from-sub-directory" args)
      (disproject--prompt-directory root-directory)))))

(defun disproject--prefer-other-window ()
  "Return whether other window should be preferred when displaying buffers."
  (let ((args (transient-args transient-current-command)))
    (and args (transient-arg-value "--prefer-other-window" args))))


;;;
;;; Suffixes.
;;;

(transient-define-suffix disproject-switch-to-buffer ()
  "Switch to buffer in project."
  (interactive)
  (disproject--with-environment
   (call-interactively disproject-switch-to-buffer-command)))

(transient-define-suffix disproject-list-buffers ()
  "Display a list of open buffers for project."
  (interactive)
  (disproject--with-environment
   (project-list-buffers)))

(transient-define-suffix disproject-dired ()
  "Open Dired in project root."
  (interactive)
  (disproject--with-environment
   (dired (disproject--from-directory))))

(transient-define-suffix disproject-find-file ()
  "Find file in project."
  (interactive)
  (disproject--with-environment
   (call-interactively disproject-find-file-command)))

(transient-define-suffix disproject-kill-buffers ()
  "Kill all buffers related to project."
  (interactive)
  (disproject--with-environment
   (call-interactively #'project-kill-buffers)))

(transient-define-suffix disproject-shell ()
  "Start an Eat terminal emulator in project."
  (interactive)
  (disproject--with-environment
   (call-interactively disproject-shell-command)))

(transient-define-suffix disproject-shell-command ()
  "Run a shell command asynchronously in a project."
  (interactive)
  (disproject--with-environment
   (call-interactively #'async-shell-command)))

(transient-define-suffix disproject-execute-extended-command ()
  "Execute an extended command in project root."
  (interactive)
  (disproject--with-environment
   (call-interactively #'execute-extended-command)))

(transient-define-suffix disproject-find-regexp ()
  "Search project for regexp."
  (interactive)
  (disproject--with-environment
   (call-interactively disproject-find-regexp-command)))

(transient-define-suffix disproject-magit-status ()
  "Open the Magit dispatch transient for project."
  (interactive)
  (declare-function magit-status-setup-buffer "magit-status")
  (disproject--with-environment
   (magit-status-setup-buffer)))

(defun disproject-compile--setup-suffixes (_)
  "Set up suffixes according to `disproject-compile-suffixes'."
  (disproject--with-environment
   (hack-dir-local-variables-non-file-buffer)
   ;; XXX: Since infix arguments from `disproject' are not made available for
   ;; `disproject-compile', work around it by setting `default-directory' from
   ;; the current (desired) environment to be used later.
   (transient-parse-suffixes
    'disproject-compile
    `(,@(mapcar
         (pcase-lambda (`( ,key ,identifier ,compile-command
                           . ,(map :description)))
           `(,key
             ;; TODO: Color the command
             ,(or description compile-command)
             (lambda ()
               (interactive)
               (let ((default-directory ,default-directory))
                 (disproject--with-environment
                  (let* ((compilation-buffer-name-function
                          (lambda (major-mode-name)
                            (project-prefixed-buffer-name
                             (concat ,identifier "-" major-mode-name)))))
                    (compile ,compile-command)))))))
         disproject-compile-suffixes)
      ("!"
       "Alternative command..."
       (lambda ()
         (interactive)
         (let ((default-directory ,default-directory))
           (disproject--with-environment
            (call-interactively #'compile)))))))))

(transient-define-suffix disproject-vc-dir ()
  "Run VC-Dir in project."
  (interactive)
  (disproject--with-environment
   (vc-dir (disproject--from-directory))))

(provide 'disproject)
;;; disproject.el ends here
