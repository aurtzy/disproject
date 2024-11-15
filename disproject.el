;;; disproject.el --- Dispatch project commands with Transient  -*- lexical-binding: t; -*-

;; Copyright (C) 2024 aurtzy
;; Copyright (C) 2008-2023 The Magit Project Contributors
;; Copyright (C) 2015-2024 Free Software Foundation, Inc.

;; Author: aurtzy <aurtzy@gmail.com>
;; URL: https://github.com/aurtzy/disproject
;; Keywords: convenience, files, vc

;; Version: 0.13.0
;; Package-Requires: ((emacs "29.4") (transient "0.7.8"))

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
;; (and inspired by) the function `project-switch-project', but also attempts to
;; improve on its feature set in addition to the use of Transient.

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
  "Run BODY with `disproject' \"environment\" options set.

The \"environment\" consists of the following overrides:

`default-directory', `project-current-directory-override': Set to
the project's root directory.

`display-buffer-overriding-action': Set to display in another
window if \"--prefer-other-window\" is enabled."
  (declare (debug t))
  `(let* ((project (disproject--state-project-ensure))
          (from-directory (project-root project))
          (prefer-other-window? (disproject--state-prefer-other-window?))
          ;; Only enable envrc if the initial environment has it enabled.
          (enable-envrc (and (bound-and-true-p envrc-mode)
                             (symbol-function 'envrc-mode)))
          ;; Only enable mise if the initial environment has it enabled.
          (enable-mise (and (bound-and-true-p mise-mode)
                            (symbol-function 'mise-mode)))
          ;; HACK: Since `project-external-roots' targets specifically the
          ;; current buffer's major mode - a problem, since we create a temp
          ;; buffer - we make it work by grabbing the function that it's supposed
          ;; to return (i.e. `project-vc-external-roots-function') before
          ;; entering the temp buffer, and then restoring it.  This won't be
          ;; needed once `project.el' supports project-wide external roots.
          (external-roots-function project-vc-external-roots-function))
     (with-temp-buffer
       (let ((default-directory from-directory)
             ;; This handles edge cases with `project' commands.
             (project-current-directory-override from-directory)
             (display-buffer-overriding-action
              (and prefer-other-window? '(display-buffer-use-some-window
                                          (inhibit-same-window t))))
             (project-vc-external-roots-function external-roots-function))
         ;; Make sure commands are run in the correct direnv environment
         ;; if envrc-mode is enabled.
         (when enable-envrc (funcall enable-envrc))
         ;; Make sure commands are run in the correct mise environment
         ;; if mise-mode is enabled.
         (when enable-mise (funcall enable-mise))
         ,@body))))


;;;
;;; Global variables.
;;;

(defgroup disproject nil
  "Transient interface for managing and interacting with projects."
  :group 'convenience
  :group 'project)

(defcustom disproject-custom-suffixes '(("c" "Make"
                                          :command-type compile
                                          :command "make -k"
                                          :identifier "make"))
  "Commands for the `disproject-custom-dispatch' prefix.

The value should be a list of transient-like specification
entries (KEY DESCRIPTION {PROPERTY VALUE} ...).

KEY is the key-bind that will be used in the Transient menu.  Key
sequences starting with alphanumeric characters (regexp
\"[a-zA-Z0-9]\") are reserved for the user.

DESCRIPTION is used as the Transient command description.

The following properties are required:

`:command' is an s-expression which is evaluated and used
depending on the command type `:command-type'.

`:command-type' is a symbol that specifies what to do with the
value of `:command'.  It can be any of the following keys:

  bare-call: the value is called as an interactive function from
  the current buffer.  This is the only command type that is not
  automatically run in the environment provided by
  `disproject--with-environment'.

  call: the value will be called as an interactive function.

  compile: the value of `:command' should be a string or an
  interactive function that returns a string that will be passed
  to `compile' as the shell command to run.

When using the \\='bare-call or \\='call command types, consider
using the variable `disproject-command-buffer-name' (available
when evaluating `:command') as the buffer name for processes to
enable tracking e.g. process state.

Some optional properties may be set as well:

`:identifier' is used as part of the buffer name, and should be
unique to the command.  It defaults to the result of applying
`disproject-command-buffer-name' to the value (or first word in
the description if not specified).  Users may choose to set the
same identifier for multiple commands to mark them as
incompatible (only one can run at a given time).  This relies on
commands like `compile' which notify the user that a buffer with
the same name already has a process running.

To illustrate usage of `disproject-custom-suffixes', for
example, the following may be used as a dir-locals.el value for
some project to add \"make -k\" and \"guile --help\" as compile
commands and some custom `find-file' call commands:

  ((\"m\" \"Make\"
    :command-type compile
    :command \"echo Running make...; make -k\"
    :identifier \"make\")
   (\"h\" \"Get help from a program (if it supports --help)\"
    :command-type compile
    :command (lambda (program)
               (interactive \"sProgram: \")
               (concat program \" --help\"))
    :identifier \"guile-help\")
   (\"f\" \"Find a file\"
    :command-type call
    :command #\\='find-file)
   (\"F\" \"Announce the finding a file\"
    :command-type call
    :command (lambda ()
               (interactive)
               (message \"FINDING A FILE!\")
               (call-interactively #\\='find-file))))"
  :type '(repeat (list (string :tag "Key bind")
                       (string :tag "Description")
                       (plist :inline t
                              :tag "Properties"
                              :key-type (choice (const :command-type)
                                                (const :command)
                                                (const :identifier)))))
  :group 'disproject)

(defcustom disproject-find-dir-command #'project-find-dir
  "Command to find a directory in a project.

This is called whenever the function `disproject-find-dir' is
invoked."
  :type 'function
  :group 'disproject)

(defcustom disproject-find-file-command #'project-find-file
  "Command used for opening a file in a project.

This is called whenever the function `disproject-find-file' is
invoked."
  :type 'function
  :group 'disproject)

(defcustom disproject-find-regexp-command #'project-find-regexp
  "Command used for finding regexp matches in a project.

This is called whenever the function `disproject-find-regexp' is
invoked."
  :type 'function
  :group 'disproject)

(defcustom disproject-or-external-find-file-command
  #'project-or-external-find-file
  "Command used to find a file in a project or its external roots.

This is called whenever the function
`disproject-or-external-find-file' is invoked."
  :type 'function
  :group 'disproject)

(defcustom disproject-or-external-find-regexp-command
  #'project-or-external-find-regexp
  "Command used to find regexp matches in a project or its external roots.

This is called whenever the function
`disproject-or-external-find-file' is invoked."
  :type 'function
  :group 'disproject)

(defcustom disproject-shell-command #'project-eshell
  "Command used for opening a shell in a project.

This is called whenever the function `disproject-shell-command'
is invoked."
  :type 'function
  :group 'disproject)

(defcustom disproject-switch-to-buffer-command #'project-switch-to-buffer
  "Command used for switching project buffers.

This is called whenever the function
`disproject-switch-to-buffer' is invoked."
  :type 'function
  :group 'disproject)


;;;
;;; Prefix handling.
;;;

(defun disproject--assert-type (variable value)
  "Assert that VALUE matches the type for custom VARIABLE.

A nil value is returned and a warning is signaled if VALUE does
not match the type.  Otherwise, this function returns a non-nil
value."
  (let ((type (get variable 'custom-type)))
    (if (widget-apply (widget-convert type) :match value)
        t
      ;; The rest of the menu should still be usable if a customizable variable
      ;; type is invalid, so only warn user about invalid types.
      (warn "Value `%S' does not match type %s" value type)
      nil)))

(defun disproject--setup-scope (&optional overrides write-scope?)
  "Set up Transient scope for a Disproject prefix.

When WRITE-SCOPE? is non-nil, overwrite the current Transient scope
with the return value.

OVERRIDES should be an alist, with optional key-value entries
where the key corresponds to one in the scope that permits being
overridden (see specifications below).  If a corresponding key is
non-nil, the override value will be used instead, ignoring any
current project state.

The specifications for the scope returned is an alist with keys
and descriptions of their values as follows:

\\='default-project: the project belonging to
`default-directory' (or the current buffer, in other words).  Can
be overridden.

\\='project: the currently selected project in the Transient
menu.  Can be overridden.

\\='prefer-other-window?: whether to prefer another window when
displaying buffers.  Can be overridden.

\\='custom-suffixes: suffixes for `disproject-custom-dispatch',
as described `disproject-custom-suffixes'."
  (let* ((maybe-override ; TODO: maybe this should be a macro?
          (lambda (key value)
            (if-let* ((override (assq key overrides)))
                (cdr override)
              value)))
         (default-project
          (funcall
           maybe-override
           'default-project
           (project-current nil default-directory)))
         (project
          (funcall
           maybe-override
           'project
           (or (disproject--state-project) default-project)))
         (prefer-other-window?
          (funcall
           maybe-override
           'prefer-other-window?
           (disproject--state-prefer-other-window?)))
         (dir-local-variables
          (with-temp-buffer
            (when-let* ((project)
                        (default-directory (project-root project)))
              (hack-dir-local-variables)
              dir-local-variables-alist)))
         ;; Type-check local custom variables, since `hack-dir-local-variables'
         ;; only reads an alist.
         (custom-suffixes
          (if-let* ((suffixes (alist-get 'disproject-custom-suffixes
                                         dir-local-variables
                                         (default-value
                                          'disproject-custom-suffixes)))
                    ((disproject--assert-type 'disproject-custom-suffixes
                                              suffixes)))
              suffixes))
         (new-scope
          `((default-project . ,default-project)
            (project . ,project)
            (prefer-other-window? . ,prefer-other-window?)
            (custom-suffixes . ,custom-suffixes))))
    ;; Remember the project in case it's not in `project-known-project-roots'.
    (when project (project-remember-project project))
    (if-let* ((write-scope?)
              (scope (disproject--scope nil t)))
        (seq-each (pcase-lambda (`(,key . ,value))
                    (setf (alist-get key scope) value))
                  new-scope))
    new-scope))

;;;; Prefixes.

;;;###autoload (autoload 'disproject-dispatch "disproject")
(transient-define-prefix disproject-dispatch (&optional project)
  "Dispatch some command for a project.

PROJECT is an optional argument that tells the function what to
start with as the selected project."
  :refresh-suffixes t
  [:description
   (lambda ()
     (format (propertize "Project: %s" 'face 'transient-heading)
             (if-let* ((directory (disproject--state-project-root)))
                 (propertize directory 'face 'transient-value)
               (propertize "None detected" 'face 'transient-inapt-suffix))))
   ("p" "Switch project" disproject-switch-project
    :transient t)
   ("P" "Switch to active project" disproject-switch-project-active
    :transient t)
   ("C-p" "Manage projects" disproject-manage-projects-dispatch)]
  ["Options"
   ("o" "Prefer other window" "--prefer-other-window")]
  ["Commands"
   :pad-keys t
   [("b" "Switch buffer" disproject-switch-to-buffer)
    ("B" "Buffer list" disproject-list-buffers)
    ("d" "Dired" disproject-dired)
    ("k" "Kill buffers" disproject-kill-buffers)
    ("s" "Shell" disproject-shell)]
   [("!" "Run" disproject-shell-command)
    ("M-x" "Extended command" disproject-execute-extended-command)
    ;; DEPRECATED: Replaced by `SPC' key-bind.
    ("c" "(deprecated) Custom dis." disproject-custom-dispatch)]
   ["Find"
    ("D" "directory" disproject-find-dir)
    ("f" "file" disproject-find-file)
    ("F" "file (+external)" disproject-or-external-find-file)
    ("g" "regexp" disproject-find-regexp)
    ("G" "regexp (+external)" disproject-or-external-find-regexp)]]
  ;; This section may contain commands that are dynamically enabled/disabled
  ;; depending on the chosen project.  This requires :refresh-suffixes to be t.
  ;;
  ;; FIXME: There is a case where the section doesn't display when it should.
  ;; 1. Start with no project detected; 2. Custom dispatch, selecting a project
  ;; that has vc; 3. return to main dispatch menu.  Version control should show
  ;; up since that project is now selected, but it doesn't until the next
  ;; refresh (e.g. by flipping an option).
  [["Version control"
    :if (lambda () (nth 1 (disproject--state-project)))
    ("m" "Magit" disproject-magit-commands-dispatch
     :if (lambda () (and (featurep 'magit) (disproject--state-git-repository?))))
    ("v" "VC status" disproject-vc-dir)]]
  [("SPC" "Custom dispatch" disproject-custom-dispatch
    :transient transient--do-replace)]
  (interactive)
  (transient-setup
   'disproject-dispatch nil nil
   :scope (disproject--setup-scope
           `(,@(if project `((project . ,project)) '())))
   ;; XXX: Preserve options in scope if we're coming from another Disproject
   ;; Transient.  `:refresh-suffixes' being true causes the `:init-value'
   ;; function to be called every refresh which messes up --prefer-other-window,
   ;; so that can't be used.
   :value `(,@(if (disproject--state-prefer-other-window?)
                  '("--prefer-other-window")))))

(transient-define-prefix disproject-custom-dispatch (&optional project)
  "Dispatch custom suffix commands.

If non-nil, PROJECT is used as the project to dispatch custom
commands for.

This prefix can be configured with `disproject-custom-suffixes'.

Suffixes have an associated buffer that is tracked for command
activity; this is shown in the menu in the form of \"[CHAR]\",
where the string is color-coded and CHAR is a single character.
These characters represent the following states:

  [a]: Command is active.
  [i]: Command is inactive."
  :refresh-suffixes t
  ["Custom suffix commands"
   :class transient-column
   :pad-keys t
   :setup-children disproject-custom--setup-suffixes]
  [("<tab>" "View command buffer" "--view-buffer")
   ("SPC" "Main dispatch" disproject-dispatch
    :transient transient--do-replace)]
  (interactive)
  (transient-setup
   'disproject-custom-dispatch nil nil
   :scope (disproject--setup-scope
           `((project . ,(or project (disproject--state-project-ensure)))))))

(transient-define-prefix disproject-magit-commands-dispatch ()
  "Dispatch Magit-related commands for a project.

DIRECTORY will be searched for the project if passed.

Some commands may not be available if the selected project is not
the same as the default (current buffer) one."
  ["Magit commands"
   ("d" "Dispatch" magit-dispatch
    :inapt-if-not disproject--state-project-is-default?)
   ("f" "File dispatch" magit-file-dispatch
    :inapt-if-not disproject--state-project-is-default?)
   ("m" "Status" disproject-magit-status)
   ("T" "Todos" disproject-magit-todos-list
    :if (lambda () (featurep 'magit-todos)))]
  (interactive)
  (transient-setup
   'disproject-magit-commands-dispatch nil nil
   :scope (disproject--setup-scope)))

(transient-define-prefix disproject-manage-projects-dispatch (&optional project)
  "Dispatch commands for managing projects.

If PROJECT is non-nil, it overrides the currently selected
project in Transient state (if any)."
  ["New"
   ("n g c" "git clone" magit-clone
    :if (lambda () (featurep 'magit)))
   ("n g i" "git init" magit-init
    :if (lambda () (featurep 'magit)))]
  ["Forget"
   ;; TODO: Could add an option to close buffers of the project to forget.
   ("f p" "a project" disproject-forget-project)
   ("f u" "projects under..." disproject-forget-projects-under)
   ("f z" "zombie projects" disproject-forget-zombie-projects)]
  ["Remember"
   ("r a" "active projects" disproject-remember-projects-active)
   ("r u" "projects under..." disproject-remember-projects-under)]
  (interactive)
  (transient-setup
   'disproject-manage-projects-dispatch nil nil
   :scope (disproject--setup-scope
           `(,@(if project `((project . ,project)) '())))))


;;;
;;; Transient state handling.
;;;

(defun disproject--active-projects ()
  "Return a list of active known projects, i.e. those with open buffers."
  (let* ((buffer-list
          ;; Ignore ephemeral buffers
          (match-buffers (lambda (buf)
                           (not (string-prefix-p " " (buffer-name buf))))))
         (directories
          (cl-remove-duplicates (mapcar
                                 (lambda (buf)
                                   (buffer-local-value 'default-directory buf))
                                 buffer-list)
                                :test #'equal)))
    (cl-remove-duplicates
     (seq-mapcat (lambda (directory)
                   (if-let* ((project (project-current nil directory)))
                       (list project)))
                 directories)
     :test (lambda (p1 p2) (equal (project-root p1) (project-root p2))))))

(defun disproject--scope (key &optional no-alist?)
  "Get `disproject' scope.

By default, this function assumes that the scope is an alist.
KEY is the key used to get the alist value.  If NO-ALIST? is
non-nil, the scope will be treated as a value of any possible
type and directly returned instead, ignoring KEY."
  ;; Just return nil instead of signaling an error if there is no prefix.
  (if-let* (((transient-prefix-object))
            (scope (transient-scope)))
      (if no-alist? scope (alist-get key scope))))

;;;; Infix classes.

;;;; Infixes.

;;;; Transient state getters.
;; Functions that query the Transient state should have their names be prefixed
;; with "disproject--state-" to provide unique identifiers that can be searched
;; for.

(defun disproject--state-view-buffer ()
  "Return whether to only view a buffer."
  (if-let* ((args (transient-args transient-current-command)))
      (transient-arg-value "--view-buffer" args)))

(defun disproject--state-custom-suffixes ()
  "Return the `disproject-dispatch' custom suffixes for this scope."
  (disproject--scope 'custom-suffixes))

(defun disproject--state-default-project-root ()
  "Return the current caller's (the one setting up Transient) root directory."
  (if-let* ((project (disproject--scope 'default-project)))
      (project-root project)))

(defun disproject--state-git-repository? ()
  "Return if project is a Git repository."
  ;; Index 1 contains the project backend; see
  ;; `project-vc-backend-markers-alist'.
  (eq (nth 1 (disproject--scope 'project)) 'Git))

(defun disproject--state-prefer-other-window? ()
  "Return whether other window should be preferred when displaying buffers."
  (if (eq transient-current-command 'disproject-dispatch)
      (let ((args (transient-args transient-current-command)))
        (and args (transient-arg-value "--prefer-other-window" args)))
    (disproject--scope 'prefer-other-window?)))

(defun disproject--state-project ()
  "Return the project from the current Transient scope."
  (disproject--scope 'project))

(defun disproject--state-project-ensure ()
  "Ensure that there is a selected project and return it.

This checks if there is a selected project in Transient scope,
prompting for the value if needed to meet that expectation.
Sets the Transient state if possible."
  (or (disproject--state-project)
      (if-let* ((directory (project-prompt-project-dir))
                (project (project-current nil directory)))
          (progn
            (disproject--setup-scope `((project . ,project)) t)
            project)
        (error "No project found for directory: %s" directory))))

(defun disproject--state-project-is-default? ()
  "Return whether the selected project is the same as the default project."
  (if-let* ((default-project (disproject--scope 'default-project))
            (project (disproject--scope 'project)))
      (equal (project-root default-project) (project-root project))))

(defun disproject--state-project-root ()
  "Return the selected project's root directory from Transient state."
  (if-let* ((project (disproject--scope 'project)))
      (project-root project)))


;;;
;;; Suffix handling.
;;;

(defun disproject-command-buffer-name (&optional identifier)
  "Return the command buffer name according to project and IDENTIFIER.

IDENTIFIER is an optional string argument that can be specified
to make the buffer name unique.  If non-nil, \"default\" is used
as the identifier.

This function is *not* meant to be used like
`project-prefixed-buffer-name', although it is similar in
functionality; the identifier should not be tied to the buffer
mode in any way.  It should be the only means of making a name
unique in the context of a project.  This allows users to track
buffers based on just an identifier and also allow specifying
incompatible commands (e.g. if two commands use the same buffer
name, they should not be allowed to run at the same time)."
  (concat "*"
          (file-name-nondirectory
           (directory-file-name (disproject--state-project-root)))
          "-command|"
          (or identifier "default")
          "*"))

(defun disproject-custom--suffix (spec-entry)
  "Construct and return a suffix to be parsed by `transient-parse-suffixes'.

SPEC-ENTRY is a single entry from the specification described by
`disproject-custom-suffixes'."
  (pcase spec-entry
    (`( ,key ,description
        .
        ,(map :command-type :command :identifier))
     (let* (;; Fall back to description if identifier is not provided.
            ;; Uniqueness is preferred over the name looking nice to prevent
            ;; unintentionally making commands incompatible.
            (identifier (or identifier description))
            (disproject-command-buffer-name (disproject-command-buffer-name
                                             identifier)))
       `(,key
         ,(disproject-custom--suffix-description
           (get-buffer disproject-command-buffer-name)
           description)
         (lambda ()
           (interactive)
           ;; Expose buffer name to the user; see note in
           ;; `disproject-custom-suffixes'.
           (let ((disproject-command-buffer-name ,disproject-command-buffer-name))
             (if (disproject--state-view-buffer)
                 (if (get-buffer disproject-command-buffer-name)
                     (disproject--with-environment
                      (switch-to-buffer disproject-command-buffer-name))
                   (error "No buffer with name found: %s"
                          disproject-command-buffer-name))
               ,(disproject-custom--suffix-command command-type command)
               ;; Auto-refresh menu on command completion
               (when-let* ((buffer (get-buffer disproject-command-buffer-name))
                           (process (get-buffer-process buffer))
                           ((not (advice-function-member-p
                                  #'disproject-custom--suffix-refresh-transient
                                  (process-sentinel process)))))
                 (add-function
                  :before (process-sentinel process)
                  #'disproject-custom--suffix-refresh-transient))))))))))

(defun disproject-custom--suffix-command (command-type command)
  "Dispatch a command s-expression to be evaluated in a custom suffix.

COMMAND-TYPE is a symbol corresponding to a command type
documented in `disproject-custom-suffixes'.

COMMAND is an yet-to-be-evaluated s-expression which is inserted
appropriately according to the command type."
  (pcase command-type
    ('bare-call
     `(let ((command ,command))
        (cond
         ((commandp command t)
          (call-interactively command))
         (t
          ,(disproject-custom--suffix-command-type-error
            "Not an interactive function" command-type command)))))
    ('call
     `(disproject--with-environment
       ;; DEPRECATED: `compilation-buffer-name-function' will not be
       ;; automatically set for this command type in the future.  This
       ;; should no longer be considered a "set everything under the
       ;; sun" command type; new types can be created if needed
       ;; instead.
       (let* ((compilation-buffer-name-function
               (lambda (&rest _ignore)
                 (let ((display-buffer-overriding-action
                        '(display-buffer-same-window)))
                   (display-warning
                    'disproject
                    (concat
                     "DEPRECATION WARNING:"
                     " The `call' custom suffix command type"
                     " commands will soon no longer automatically"
                     " set `compilation-buffer-name-function';"
                     " use the `compile' command type instead"
                     " or manually set the variable.")))
                 disproject-command-buffer-name))
              (command ,command))
         (cond
          ((commandp command t)
           (call-interactively command))
          (t
           ,(disproject-custom--suffix-command-type-error
             "Not an interactive function" command-type command))))))
    ('compile
     `(disproject--with-environment
       (let* ((compilation-buffer-name-function
               (lambda (&rest _ignore) disproject-command-buffer-name))
              (command ,command))
         (compile (cond
                   ((stringp command)
                    command)
                   ((commandp command t)
                    (let ((result (call-interactively command)))
                      (if (stringp result)
                          result
                        ,(disproject-custom--suffix-command-type-error
                          "Function does not return string"
                          command-type
                          command))))
                   (t
                    ,(disproject-custom--suffix-command-type-error
                      "Not a string or interactive function"
                      command-type
                      command)))))))))

(defun disproject-custom--suffix-command-type-error (message
                                                     command-type
                                                     command)
  "Return an s-expression to evaluate when there is a suffix command type error.

MESSAGE is the message body stating the typing issue.

COMMAND-TYPE is the `:command-type' value declared in the custom
suffix entry specification.

COMMAND is an unevaluated s-expression representing the declared
`:command' value that can be printed as-is for the user."
  `(error "(`%s') %s: %s" ',command-type ,message ',command))

(defun disproject-custom--suffix-description (buffer description)
  "Return an appropriate description for a custom suffix.

BUFFER is the associated custom suffix buffer.  It may be
non-nil.

DESCRIPTION is the custom suffix description as defined by the
user."
  (concat (cond
           ((null buffer)
            "")
           ((get-buffer-process buffer)
            (concat (propertize "[a]" 'face 'transient-enabled-suffix)
                    " "))
           (t
            (concat (propertize "[i]" 'face 'transient-inactive-value)
                    " ")))
          description))

(defun disproject-custom--suffix-refresh-transient (&rest _ignore)
  "Refresh the `disproject-custom-dispatch' transient, if active."
  (when (transient-active-prefix)
    (transient--refresh-transient)))

(defun disproject--switch-project (search-directory)
  "Modify the Transient scope to switch to another project.

Look for a valid project root directory in SEARCH-DIRECTORY.  If
one is found, update the Transient scope to switch the selected
project."
  (if-let* ((project (project-current nil search-directory)))
      (disproject--setup-scope `((project . ,project)) t)
    (error "No parent project found for %s" search-directory)))

;;;; Suffix setup functions.

(defun disproject-custom--setup-suffixes (_)
  "Set up suffixes according to `disproject-custom-suffixes'."
  (transient-parse-suffixes
   'disproject-custom-dispatch
   (mapcar #'disproject-custom--suffix
           `(,@(disproject--state-custom-suffixes)
             ("!" "Alternative compile..."
              :command-type compile
              :command (lambda ()
                         (interactive)
                         (compilation-read-command (eval compile-command))))))))

;;;; Suffixes.

(transient-define-suffix disproject-dired ()
  "Open Dired in project root."
  (interactive)
  (disproject--with-environment
   (call-interactively #'project-dired)))

(transient-define-suffix disproject-execute-extended-command ()
  "Execute an extended command in project root."
  (interactive)
  (disproject--with-environment
   (call-interactively #'execute-extended-command)))

(transient-define-suffix disproject-find-dir ()
  "Find directory in project."
  (interactive)
  (disproject--with-environment
   (call-interactively disproject-find-dir-command)))

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

(transient-define-suffix disproject-forget-project ()
  "Forget a project."
  (interactive)
  (call-interactively #'project-forget-project))

(transient-define-suffix disproject-forget-projects-under ()
  "Forget projects under a directory."
  (interactive)
  (call-interactively #'project-forget-projects-under))

(transient-define-suffix disproject-forget-zombie-projects ()
  "Forget zombie projects."
  (interactive)
  (call-interactively #'project-forget-zombie-projects))

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

(transient-define-suffix disproject-or-external-find-file ()
  "Find file in project or external roots."
  (interactive)
  (disproject--with-environment
   (call-interactively disproject-or-external-find-file-command)))

(transient-define-suffix disproject-or-external-find-regexp ()
  "Find regexp in project or external roots."
  (interactive)
  (disproject--with-environment
   (call-interactively disproject-or-external-find-regexp-command)))

(transient-define-suffix disproject-remember-projects-active ()
  "Remember active projects."
  (interactive)
  (let ((active-projects (disproject--active-projects)))
    (seq-each (lambda (project)
                (project-remember-project project t))
              active-projects)
    (project--write-project-list)))

(transient-define-suffix disproject-remember-projects-under ()
  "Remember projects under a directory."
  (interactive)
  (call-interactively #'project-remember-projects-under))

(transient-define-suffix disproject-shell ()
  "Start a shell in project."
  (interactive)
  (disproject--with-environment
   (call-interactively disproject-shell-command)))

(transient-define-suffix disproject-shell-command ()
  "Run a shell command asynchronously in a project."
  (interactive)
  (disproject--with-environment
   (let ((shell-command-buffer-name-async
          (project-prefixed-buffer-name "async-shell")))
     (call-interactively #'async-shell-command))))

(transient-define-suffix disproject-switch-project ()
  "Switch project to dispatch commands on.

Uses `project-prompt-project-dir' to switch project root
directories."
  (interactive)
  (disproject--switch-project (project-prompt-project-dir)))

(transient-define-suffix disproject-switch-project-active ()
  "Switch to an active project to dispatch commands on.

This is equivalent to `disproject-switch-project' but only shows
active projects when prompting for projects to switch to."
  (interactive)
  (let* ((active-projects (mapcar #'project-root (disproject--active-projects)))
         ;; `project--file-completion-table' seems to accept any collection as
         ;; defined by `completing-read'.
         (completion-table (project--file-completion-table active-projects))
         (project-directory (completing-read "Select active project: "
                                             completion-table nil t)))
    (disproject--switch-project project-directory)))

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
