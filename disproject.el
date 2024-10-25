;;; disproject.el --- Dispatch project commands with Transient  -*- lexical-binding: t; -*-

;; Copyright (C) 2024 aurtzy
;; Copyright (C) 2008-2023 The Magit Project Contributors
;; Copyright (C) 2015-2024 Free Software Foundation, Inc.

;; Author: aurtzy <aurtzy@gmail.com>
;; URL: https://github.com/aurtzy/disproject
;; Keywords: convenience, project
;; Package-Version: 0.2.0

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
  `(let ((from-directory (or (disproject--root-directory) default-directory))
         (prefer-other-window (disproject--prefer-other-window))
         ;; Only enable envrc if the initial environment has it enabled.
         (enable-envrc (and (bound-and-true-p envrc-mode)
                            (symbol-function 'envrc-mode))))
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
         ,@body))))


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

(defcustom disproject-find-file-command #'project-find-file
  "The command used for opening a file in a project.

This is called whenever the function `disproject-find-file' is
invoked."
  :type 'function
  :group 'disproject)

(defcustom disproject-find-regexp-command #'project-find-regexp
  "The command used for finding regexp matches in a project.

This is called whenever the function `disproject-find-regexp' is
invoked."
  :type 'function
  :group 'disproject)

(defcustom disproject-shell-command #'project-eshell
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
(transient-define-prefix disproject (&optional directory)
  "Dispatch some command for a project.

DIRECTORY is an optional argument that tells `disproject' where
to start searching first for a project directory root; otherwise,
it moves on to `default-directory'.  If no project is found, it
starts the menu anyways to explicitly ask later when a command is
executed or when --root-directory is manually set."
  :refresh-suffixes t
  ["Options"
   ("p" "Switch project" disproject:--root-directory)
   ("o" "Prefer other window" "--prefer-other-window")]
  ["Project commands"
   :pad-keys t
   [("B" "Buffer list" disproject-list-buffers)
    ("b" "Switch buffer" disproject-switch-to-buffer)
    ("c" "Compile" disproject-compile)
    ("D" "Dired" disproject-dired)
    ("f" "Find file" disproject-find-file)
    ("g" "Find regexp" disproject-find-regexp)]
   [("k" "Kill buffers" disproject-kill-buffers)
    ("s" "Shell" disproject-shell)
    ("v" "VC dir" disproject-vc-dir)
    ("!" "Run" disproject-shell-command)
    ("M-x" "Extended command" disproject-execute-extended-command)]
   ["Magit"
    ;; Needs :refresh-suffixes t since it depends on infix "--root-directory="
    :if (lambda () (and (featurep 'magit)
                        (funcall (symbol-function 'magit-git-repo-p)
                                 (disproject--root-directory))))
    ("m" "Status" disproject-magit-status)
    ("T" "Todos" disproject-todos-list
     :if (lambda () (featurep 'magit-todos)))]]
  (interactive)
  (transient-setup
   'disproject nil nil
   :scope `((root-directory
             . ,(let ((project
                       (project-current nil (or directory default-directory))))
                  (and project (project-root project)))))))

(transient-define-prefix disproject-compile (&optional directory)
  "Dispatch compilation commands.

This prefix can be configured with `disproject-compile-suffixes'."
  ["Compile"
   :class transient-column
   :setup-children disproject-compile--setup-suffixes]
  (interactive)
  (transient-setup
   'disproject-compile nil nil
   :scope `((root-directory . ,(or (disproject--scope 'root-directory)
                                   (project-current t (or directory
                                                          default-directory)))))))


;;;
;;; Transient state handling.
;;;

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

(defun disproject--scope (key &optional no-alist?)
  "Get `disproject' scope.

By default, this function assumes that the scope is an alist.
KEY is the key used to get the alist value.  If NO-ALIST? is
non-nil, the scope will be treated as a value of any possible
type and directly returned instead, ignoring KEY."
  (let ((scope (transient-scope)))
    (if no-alist? scope (alist-get key scope))))

;;;; Infix classes.

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

;;;; Infixes.

(transient-define-infix disproject:--root-directory ()
  :class transient-option
  :argument "--root-directory="
  :init-value (lambda (obj)
                (oset obj value (disproject--scope 'root-directory)))
  :always-read t
  :reader (lambda (&rest _ignore)
            (let ((new-root-directory (disproject--find-root-directory
                                       (project-prompt-project-dir)))
                  (scope (disproject--scope nil t)))
              ;; Update --root-directory in Transient scope to keep it in sync
              (setf (alist-get 'root-directory scope) new-root-directory)
              new-root-directory)))

;;;; Transient state getters.

(defun disproject--prefer-other-window ()
  "Return whether other window should be preferred when displaying buffers."
  (let ((args (transient-args transient-current-command)))
    (and args (transient-arg-value "--prefer-other-window" args))))

(defun disproject--root-directory ()
  "Return the project root directory defined in transient arguments.

Prefer the current Transient prefix's arguments.  If not
available, try the Transient scope.  Otherwise, if neither have a
root directory stored, use `default-directory' to find the
current project or prompt as needed."
  (let ((args (transient-args transient-current-command)))
    (or (and args (transient-arg-value "--root-directory=" args))
        (disproject--scope 'root-directory)
        (project-root (project-current t)))))


;;;
;;; Suffixes.
;;;

(transient-define-suffix disproject-dired ()
  "Open Dired in project root."
  (interactive)
  (disproject--with-environment
   (call-interactively #'dired)))

(transient-define-suffix disproject-execute-extended-command ()
  "Execute an extended command in project root."
  (interactive)
  (disproject--with-environment
   (call-interactively #'execute-extended-command)))

(transient-define-suffix disproject-find-file ()
  "Find file in project."
  (interactive)
  (disproject--with-environment
   (call-interactively disproject-find-file-command)))

(transient-define-suffix disproject-find-regexp ()
  "Search project for regexp."
  (interactive)
  (disproject--with-environment
   (call-interactively disproject-find-regexp-command)))

(transient-define-suffix disproject-kill-buffers ()
  "Kill all buffers related to project."
  (interactive)
  (disproject--with-environment
   (call-interactively #'project-kill-buffers)))

(transient-define-suffix disproject-list-buffers ()
  "Display a list of open buffers for project."
  (interactive)
  (disproject--with-environment
   (call-interactively #'project-list-buffers)))

(transient-define-suffix disproject-magit-status ()
  "Open the Magit status buffer for project."
  (interactive)
  (declare-function magit-status-setup-buffer "magit-status")
  (disproject--with-environment
   (magit-status-setup-buffer)))

(transient-define-suffix disproject-magit-todos-list ()
  "Open a `magit-todos-list' buffer for project."
  (interactive)
  (declare-function magit-todos-list-internal "magit-todos")
  (disproject--with-environment
   (magit-todos-list-internal default-directory)))

(transient-define-suffix disproject-shell ()
  "Start a shell in project."
  (interactive)
  (disproject--with-environment
   (call-interactively disproject-shell-command)))

(transient-define-suffix disproject-shell-command ()
  "Run a shell command asynchronously in a project."
  (interactive)
  (disproject--with-environment
   (call-interactively #'async-shell-command)))

(defun disproject-compile--setup-suffixes (_)
  "Set up suffixes according to `disproject-compile-suffixes'."
  (disproject--with-environment
   (hack-dir-local-variables-non-file-buffer)
   (transient-parse-suffixes
    'disproject-compile
    `(,@(mapcar
         (pcase-lambda (`( ,key ,identifier ,compile-command
                           . ,(map :description)))
           `(,key
             ,(or description compile-command)
             (lambda ()
               (interactive)
               (disproject--with-environment
                (let* ((compilation-buffer-name-function
                        (lambda (major-mode-name)
                          (project-prefixed-buffer-name
                           (concat ,identifier "-" major-mode-name)))))
                  (compile ,compile-command))))))
         disproject-compile-suffixes)
      ("!"
       "Alternative command..."
       (lambda ()
         (interactive)
         (disproject--with-environment
          (call-interactively #'compile))))))))

(transient-define-suffix disproject-switch-to-buffer ()
  "Switch to buffer in project."
  (interactive)
  (disproject--with-environment
   (call-interactively disproject-switch-to-buffer-command)))

(transient-define-suffix disproject-vc-dir ()
  "Run VC-Dir in project."
  (interactive)
  (disproject--with-environment
   (call-interactively #'vc-dir)))

(provide 'disproject)
;;; disproject.el ends here
