;;; disproject.el --- Dispatch project commands with Transient  -*- lexical-binding: t; -*-

;; Copyright (C) 2024 aurtzy
;; Copyright (C) 2008-2023 The Magit Project Contributors
;; Copyright (C) 1985-1987, 1992-2024 Free Software Foundation, Inc.

;; Author: aurtzy <aurtzy@gmail.com>
;; URL: https://github.com/aurtzy/disproject
;; Keywords: convenience, files, vc

;; Version: 1.3.1
;; Package-Requires: ((emacs "29.4") (transient "0.8.0"))

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

;; Disproject implements Transient menus for dispatching project-related
;; commands on top of the `project.el' library.  It aims to provide a more
;; featureful version of the `project-switch-project' command, which it is
;; inspired by.  Those who are familiar with Projectile may also find
;; similarities to `projectile-commander'.

;;; Code:

(require 'cl-lib)
(require 'eieio)
(require 'grep)
(require 'pcase)
(require 'pp)
(require 'map)
(require 'project)
(require 'transient)


;;;
;;; Global variables.
;;;

(defgroup disproject nil
  "Transient interface for managing and interacting with projects."
  :group 'convenience
  :group 'project)

(defgroup disproject-commands nil
  "Customizable Disproject main dispatch commands.

See documentation on `disproject-with-environment' for the
variables it sets according to the menu settings.  These must be
respected (when relevant) by commands.  For example, a command
will not always run in the project root directory if it does not
respect `default-directory' or
`project-current-directory-override', which the macro sets."
  :group 'disproject)

(defvar disproject-prefix--transient-commands nil
  "Disproject transient prefix commands.

This is a list of prefix commands that use and permit sharing a
`disproject-scope' instance as a scope value.  Prefixes which use
`disproject-prefix' or a child type are automatically added to
this list via `initialize-instance'.")

;;;; Custom variables.

(defcustom disproject-custom-allowed-suffixes '()
  "Allowed values for `disproject-custom-suffixes'."
  :risky t
  :group 'disproject
  :type '(alist :key-type (string :tag "Project path")
                :value-type (repeat (sexp :tag "Custom suffix"))))

(defcustom disproject-custom-suffixes '(("c" "Make"
                                         (lambda () (interactive) "make -k")
                                         :class disproject-compilation-suffix
                                         :buffer-id "make"))
  "Commands for the `disproject-custom-dispatch' prefix.

The custom dispatch was initially designed for suites of
compilation commands, but it is flexible enough to be used for
any custom command designated for a particular project, like
starting servers or updating dependencies.

This value is passed to `transient-parse-suffixes' to fill the
\"Custom suffixes section\"; see Info node
`(transient)Group Specifications' or Info node `(transient)Suffix
Specifications' for documentation on syntax.

Suffixes should specify the `class' slot as `disproject-suffix'
or one of its subclasses to apply menu options and other features
as needed.  `disproject-suffix' is the most general class, which
applies settings from `disproject-with-environment' before
running the command.

Subclasses like `disproject-compilation-suffix' and
`disproject-shell-command-suffix' provide additional features for
handling processes associated with a command, like managing the
compilation buffer name and showing an indicator for process
status in the description.  See their respective documentations
for more information about customizing specific behaviors in
these classes.

See `disproject-suffix' for documentation on extending the
class (or its subclasses).

Here is an example value, for reference:

  ((\"f\" \"Find a file from project\" find-file
    :class disproject-suffix)
   (\"F\" \"Loudly find a file\"
    (lambda () (interactive)
      (message \"FINDING A FILE!\")
      (call-interactively #\\='find-file))
    :class disproject-suffix)
   (\"m\" \"Run make\"
    (lambda () (interactive) \"echo Running make...; make -k\")
    :class disproject-compilation-suffix
    :buffer-id \"make\")
   (\"M\" \"Run make test\"
    (lambda () (interactive) \"echo Running tests...; make test\")
    :class disproject-compilation-suffix
    :buffer-id \"make\")
   (\"s\" \"Sleep for a couple of seconds\"
    (lambda () (interactive)
      \"echo Sleeping... && sleep 5 && echo Done sleeping.\")
    :class disproject-shell-command-suffix))

This variable is marked safe due to various reasons discussed in
`disproject-custom--suffixes-allowed?'.  Prompts are deferred to
the mentioned function, called when setting up the custom
dispatch menu.  Non-default values must still be explicitly
allowed by the user - this may be unsafe if unconditionally
evaluated."
  :type 'sexp
  :group 'disproject)
;;;###autoload(put 'disproject-custom-suffixes 'safe-local-variable #'always)

;;;;; Customizable Disproject commands.

(defcustom disproject-find-dir-command #'project-find-dir
  "Command to find a directory in a project.

This is called whenever the function `disproject-find-dir' is
invoked."
  :type 'function
  :group 'disproject
  :group 'disproject-commands)

(defcustom disproject-find-file-command #'project-find-file
  "Command used for opening a file in a project.

This is called whenever the function `disproject-find-file' is
invoked."
  :type 'function
  :group 'disproject
  :group 'disproject-commands)

(defcustom disproject-find-line-command #'disproject-default-find-line
  "Command to find line occurrences in a project's open buffers.

This is called whenever the function `disproject-find-line' is
invoked."
  :type 'function
  :group 'disproject
  :group 'disproject-commands)

(defcustom disproject-find-regexp-command #'project-find-regexp
  "Command used for finding regexp matches in a project.

This is called whenever the function `disproject-find-regexp' is
invoked."
  :type 'function
  :group 'disproject
  :group 'disproject-commands)

(defcustom disproject-or-external-find-file-command
  #'project-or-external-find-file
  "Command used to find a file in a project or its external roots.

This is called whenever the function
`disproject-or-external-find-file' is invoked."
  :type 'function
  :group 'disproject
  :group 'disproject-commands)

(defcustom disproject-or-external-find-regexp-command
  #'project-or-external-find-regexp
  "Command used to find regexp matches in a project or its external roots.

This is called whenever the function
`disproject-or-external-find-file' is invoked."
  :type 'function
  :group 'disproject
  :group 'disproject-commands)

(defcustom disproject-shell-command #'project-eshell
  "Command used for opening a shell in a project.

This is called whenever the function `disproject-shell-command'
is invoked."
  :type 'function
  :group 'disproject
  :group 'disproject-commands)

(defcustom disproject-switch-to-buffer-command #'project-switch-to-buffer
  "Command used for switching project buffers.

This is called whenever the function
`disproject-switch-to-buffer' is invoked."
  :type 'function
  :group 'disproject
  :group 'disproject-commands)

(defcustom disproject-vc-status-commands '((Git . magit-status)
                                           (nil . project-vc-dir))
  "Alist of entries denoting a VC backend and an associated status command.

BACKEND is a VC backend; see `project-vc-backend-markers-alist'
for recognized keys.  COMMAND is a symbol or function that is
called interactively when the suffix is invoked.

In certain cases, COMMAND may be unbound, or an entry for a
selected project's backend is not present.  In both of these
cases, the entry with a nil backend will be used instead as a
fallback.  A fallback should always be specified.

This is used in the command `disproject-vc-status'."
  :type 'alist
  :group 'disproject
  :group 'disproject-commands)

;;;; Default commands.

(defun disproject-default-find-line (regexp)
  "Find matching line in buffers associated with the current project.

REGEXP is a regular expression used to search for occurrences.

This uses `multi-occur' under the hood."
  (interactive (list (project--read-regexp)))
  (if-let* ((project (project-current)))
      (multi-occur (project-buffers project) regexp)
    (error "No project in current directory: %s" default-directory)))

;;;; Transient groups.

;; Evaluate at compile-time so `transient-define-prefix' can find definitions.
(eval-and-compile
  (defconst disproject--selected-project-header-group
    [:description disproject--selected-project-description ""]
    "Header for transient prefixes to display the currently selected project."))


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
      (display-warning
       'disproject
       (format-message "Value: `%S'\nDoes not match type: %s" value type))
      nil)))

(defun disproject-custom--suffixes-allowed? (project custom-suffixes)
  "Return non-nil if CUSTOM-SUFFIXES for PROJECT has been allowed.

CUSTOM-SUFFIXES should follow the specifications from
`disproject-custom-suffixes'.  PROJECT is the project context in
which the suffixes will be checked.

If CUSTOM-SUFFIXES has not been marked as allowed, a prompt will
be made to temporarily or permanently do so.

Due to the tendency for `disproject-custom-suffixes' to be
tweaked or customized, we use this function with limited history
saving to determine if the suffixes are allowed in order to
prevent `safe-local-variable-values' from increasing drastically
in size.

This does not check other projects, because commands may behave
differently depending on the project (e.g. what \"make\" does for
one project can do something else for another).

Saved history of allowed suffixes is currently not implemented.
Only the most recent custom suffixes (i.e. currently used) are
saved."
  ;; TODO: Add some form of saved history; the
  ;; `disproject-custom-allowed-suffixes' alist value is a list type to allow
  ;; for this.  This implementation only saves a single custom-suffixes element
  ;; to the list at the moment.
  (let* ((root-directory (project-root project))
         (project-suffixes-list (alist-get root-directory
                                           disproject-custom-allowed-suffixes
                                           nil nil #'equal)))
    (or (seq-some (lambda (suffixes)
                    (equal suffixes custom-suffixes))
                  project-suffixes-list)
        (let* ((buf (get-buffer-create "*Custom Suffixes*")))
          (with-current-buffer buf
            (erase-buffer)
            (insert "\
This project has modified local custom suffixes, which may be risky.

Allow the custom suffixes?  You can type
y -- to allow the custom suffixes.
n -- to ignore them and use the default custom suffixes.
! -- to permanently allow the custom suffixes."
                    "\n\n")
            ;; TODO: Replace this pretty print with a custom one to give a more
            ;; uniform layout (e.g. new line for each keyword followed by
            ;; value).  This one is particularly funky with the ":" prefix.
            (save-excursion
              (let ((pp-use-max-width t)
                    (pp-max-width 60)
                    (pp-escape-newlines nil))
                (pp-emacs-lisp-code custom-suffixes)))
            (dolist (pair '(;; FIXME: This can produce incorrect output in the
                            ;; edge case where there is an escaped backslash
                            ;; right before an "n", like "\\n".
                            ("\\\\n" . "\n")
                            ;; Remove empty lines that can result from the
                            ;; pretty-printer.
                            ("\n+" . "\n")
                            ;; The pretty-printer sometimes has open parentheses
                            ;; at the end of a line; these can be combined with
                            ;; the next line.
                            ("(\n\s+" . "(")))
              (save-excursion
                (pcase-exhaustive pair
                  (`(,regexp . ,replacement)
                   (while (re-search-forward regexp nil t)
                     (replace-match replacement))))))
            (setq-local cursor-type nil)
            (set-buffer-modified-p nil)
            (goto-char (point-min)))
          ;; FIXME: If the user presses an invalid key in the menu after
          ;; answering prompt, the menu does not quit until a valid key is
          ;; pressed (e.g. "C-g" doesn't quit it, but "SPC").
          (save-window-excursion
            (pop-to-buffer buf '(display-buffer-at-bottom))
            (prog1
                (pcase (read-char-choice "Type y, n, or !: " '(?y ?n ?!))
                  (?y t)
                  (?n nil)
                  (?! (progn
                        (setf (alist-get root-directory
                                         disproject-custom-allowed-suffixes
                                         nil nil #'equal)
                              (list custom-suffixes))
                        (customize-push-and-save
                         'disproject-custom-allowed-suffixes
                         disproject-custom-allowed-suffixes)
                        t)))
              (quit-window t)))))))

(defun disproject--selected-project-description ()
  "Return a Transient menu headline to indicate the currently selected project."
  (format (propertize "Project: %s" 'face 'transient-heading)
          (if-let* ((scope (disproject--scope))
                    (project (disproject-scope-selected-project scope))
                    (root (disproject-project-root project)))
              (propertize root 'face 'transient-value)
            (propertize "None detected" 'face 'transient-inapt-suffix))))

;;;; Prefix classes.

;;;;; General Disproject prefix class.

(defclass disproject-prefix (transient-prefix) ()
  "General Disproject prefix class.

All prefixes that need to make use of `disproject-scope' as the
scope object should be of this type or inherit from it, as it is
responsible for preserving the scope across menus.")

(cl-defmethod initialize-instance :after ((obj disproject-prefix) &rest _slots)
  "Add OBJ command to `disproject-prefix--transient-commands' if not a member."
  (let ((command (oref obj command)))
    (unless (memq command disproject-prefix--transient-commands)
      (add-to-list 'disproject-prefix--transient-commands command))))

(cl-defmethod transient-init-scope ((obj disproject-prefix))
  "Initialize transient scope for OBJ.

Inherit the current prefix's scope if it is part of
`disproject-prefix--transient-commands'; otherwise, initialize a
new `disproject-scope' scope value if it hasn't already been
initialized."
  (if (memq transient-current-command disproject-prefix--transient-commands)
      (let ((scope (disproject--scope)))
        (setf (disproject-scope-prefer-other-window? scope)
              (disproject--state-prefer-other-window?))
        (oset obj scope scope))
    ;; This method is also called for situations like returning from a
    ;; sub-prefix, in which case we want to keep the existing scope.
    (unless (oref obj scope)
      (oset obj scope (disproject-scope)))))

;;;;; Disproject custom-suffixes prefix
;; HACK: A prefix specific to custom-dispatch is needed to avoid an issue caused
;; by prompts.  `disproject-custom--setup-suffixes' is perfectly capable of
;; getting custom-suffixes, but when a prompt is made in it, there is breakage
;; in the menu; e.g. pressing invalid keys can result in the menu being "sticky"
;; and passing inputs to the current buffer instead of the transient menu.  This
;; may be an upstream issue that has something to do with prompts made during
;; transient setup.

(defclass disproject--custom-suffixes-prefix (disproject-prefix) ()
  "Class for Disproject prefixes that need to use custom suffixes.")

(cl-defmethod transient-init-scope ((obj disproject--custom-suffixes-prefix))
  "Ensure custom suffixes are loaded after initializing scope for OBJ."
  (cl-call-next-method)
  (disproject-project-custom-suffixes
   (disproject-scope-selected-project-ensure (oref obj scope))))

;;;; Disproject prefix command/group aptness predicates.
;; These predicates are specifically meant for usage during transient setup of
;; `disproject-prefix' prefixes.  Calling these in any other situation may lead
;; to unexpected/undesired results.

(defun disproject-prefix--feature-magit-clone? ()
  "Return non-nil if `magit-clone' is an available library."
  (featurep 'magit-clone))

(defun disproject-prefix--feature-magit-status? ()
  "Return non-nil if `magit-status' is an available library."
  (featurep 'magit-status))

(defun disproject-prefix--git-clone-fallback-apt? ()
  "Return non-nil if the \"git clone\" fallback command should be used."
  (and (not (featurep 'magit-clone)) (executable-find "git")))

(defun disproject-prefix--git-init-fallback-apt? ()
  "Return non-nil if the \"git init\" fallback command should be used."
  (and (not (featurep 'magit-status)) (executable-find "git")))

(defun disproject-prefix--in-default-project? ()
  "Return non-nil if the selected project is also the default project."
  (if-let* ((scope (transient-scope)))
      (disproject-scope-project-is-default? scope)))

(defun disproject-prefix--magit-apt? ()
  "Return non-nil if magit commands are apt to show."
  (and (featurep 'magit)
       (if-let* ((scope (transient-scope))
                 (project (disproject-scope-selected-project scope)))
           (eq 'Git (disproject-project-backend project)))))

(defun disproject-prefix--magit-todos-apt? ()
  "Return non-nil if `magit-todos' commands are apt to show."
  (and (featurep 'magit-todos)
       (disproject-prefix--magit-apt?)))

(defun disproject-prefix--version-control-apt? ()
  "Return non-nil if version control commands are apt to show.

Consider commands apt when no project is selected, since the
state already implies that a prompt will be made to select a
project."
  (if-let* ((project (disproject-scope-selected-project (transient-scope))))
      (disproject-project-backend project)
    t))

;;;; Prefixes.

;;;###autoload (autoload 'disproject-dispatch "disproject" nil t)
(transient-define-prefix disproject-dispatch (&optional project)
  "Dispatch some command for a project.

PROJECT is an optional argument that tells the function what to
start with as the selected project.  This argument is deprecated;
`project-current-directory-override' should be used instead.

See Info node `(transient)Modifying Existing Transients' for
information on inserting user-defined suffix commands to this
menu."
  :class disproject-prefix
  :refresh-suffixes t
  [:description
   disproject--selected-project-description
   ("p" "Switch project" disproject-switch-project
    :transient t)
   ("P" "Switch to open project" disproject-switch-project-open
    :transient t)
   ("C-p" "Manage projects" disproject-manage-projects-dispatch)]
  ["Options"
   (",o" "Prefer other window" "--prefer-other-window")]
  ["Deprecated options"
   :hide always
   ;; DEPRECATED: Remove at least 1 month after deprecation.
   ("o" "Prefer other window (deprecated)"
    (lambda () (interactive)
      (seq-each (lambda (suffix)
                  (when (and (object-of-class-p suffix 'transient-switch)
                             (equal "--prefer-other-window"
                                    (oref suffix argument)))
                    (oset suffix value (transient-infix-read suffix))
                    (message
                     (concat "Key-bind \"o\" for --prefer-other-window is"
                             " deprecated; please use \",o\" instead"))))
                (transient-suffixes 'disproject-dispatch)))
    :transient t)]
  ["Main commands"
   :pad-keys t
   [("b" "Switch buffer" disproject-switch-to-buffer)
    ("B" "Buffer list" disproject-list-buffers)
    ("c" "Compile" disproject-compile)
    ("d" "Dired" disproject-dired)
    ("k" "Kill buffers" disproject-kill-buffers)
    ("l" "Dir-locals file" disproject-dir-locals)
    ("s" "Shell" disproject-shell)
    ("v" disproject-vc-status
     :inapt-if-not disproject-prefix--version-control-apt?)]
   [("!" "Run" disproject-shell-command)
    ("M-x" "Extended cmd." disproject-execute-extended-command)]
   ["Find"
    ("D" "directory" disproject-find-dir)
    ("f" "file" disproject-find-file)
    ("F" "file (+external)" disproject-or-external-find-file)
    ("g" "regexp" disproject-find-regexp)
    ("G" "regexp (+external)" disproject-or-external-find-regexp)
    ("L" "line occurrence" disproject-find-line)
    ("T" "todos" disproject-magit-todos-list
     :if disproject-prefix--magit-todos-apt?)]]
  ["Version control"
   :hide always
   :if disproject-prefix--version-control-apt?
   ("m" "Magit" disproject-magit-commands-dispatch
    :if disproject-prefix--magit-apt?)]
  [("SPC" "Custom dispatch" disproject-custom-dispatch
    :transient transient--do-replace)]
  (interactive)
  ;; DEPRECATED: Remove at least 1 month after deprecation.
  (when project
    (display-warning 'disproject "\
PROJECT argument for `disproject-dispatch' is deprecated since after v1.2"))
  (let ((project-current-directory-override (or (and project (project-root project))
                                                project-current-directory-override)))
    (transient-setup
     'disproject-dispatch nil nil
     ;; XXX: Preserve options in scope if we're coming from another Disproject
     ;; Transient.  `:refresh-suffixes' being true causes the `:init-value'
     ;; function to be called every refresh which messes up --prefer-other-window,
     ;; so that can't be used.
     :value `(,@(if (disproject--state-prefer-other-window?)
                    '("--prefer-other-window"))))))

(transient-define-prefix disproject-custom-dispatch (&optional project)
  "Dispatch custom suffix commands.

If non-nil, PROJECT is used as the project to dispatch custom
commands for.  This argument is deprecated;
`project-current-directory-override' should be used instead.

This prefix can be configured with `disproject-custom-suffixes';
see its documentation for more information.

Suffixes have an associated buffer that is tracked for command
process activity; this is shown in the menu in the form of
\"[CHAR]\", where the string is color-coded and CHAR is a single
character.  These characters represent the following states:

  [a]: Command is active.
  [i]: Command is inactive."
  :class disproject--custom-suffixes-prefix
  :refresh-suffixes t
  disproject--selected-project-header-group
  ["Custom suffix commands"
   :class transient-columns
   :pad-keys t
   :setup-children disproject-custom--setup-suffixes]
  [ :class transient-row
    ("SPC" "Main dispatch" disproject-dispatch
     :transient transient--do-replace)
    ("!" "Alternative compile" (lambda () (interactive))
     :class disproject-compilation-suffix
     :buffer-id "default-compile")]
  (interactive)
  ;; DEPRECATED: Remove at least 1 month after deprecation.
  (when project
    (display-warning 'disproject "\
PROJECT argument for `disproject-custom-dispatch' is deprecated since after v1.2"))
  (let ((project-current-directory-override (or (and project (project-root project))
                                                project-current-directory-override)))
    (transient-setup
     'disproject-custom-dispatch nil nil)))

;; DEPRECATED: Remove at least 1 month after earliest release with deprecation.
(transient-define-prefix disproject-magit-commands-dispatch ()
  "Dispatch Magit-related commands for a project.

Some commands may not be available if the selected project is not
the same as the default (current buffer) one."
  :class disproject-prefix
  disproject--selected-project-header-group
  ["Magit commands"
   ("d" "Dispatch" magit-dispatch
    :inapt-if-not disproject-prefix--in-default-project?)
   ("f" "File dispatch" magit-file-dispatch
    :inapt-if-not disproject-prefix--in-default-project?)
   ("m" "Status" disproject-magit-status)
   ("T" "Todos" disproject-magit-todos-list
    :if (lambda () (featurep 'magit-todos)))])

(make-obsolete 'disproject-magit-commands-dispatch
               "some commands have been moved to `disproject-dispatch'."
               "after v1.2")

(transient-define-prefix disproject-manage-projects-dispatch ()
  "Dispatch commands for managing projects."
  ["New"
   ("n g c" "git clone" magit-clone
    :if disproject-prefix--feature-magit-clone?)
   ("n g c" "git clone" disproject-git-clone-fallback
    :if disproject-prefix--git-clone-fallback-apt?)
   ("n g i" "git init" magit-init
    :if disproject-prefix--feature-magit-status?)
   ("n g i" "git init" disproject-git-init-fallback
    :if disproject-prefix--git-init-fallback-apt?)]
  ["Forget"
   ;; TODO: Could add an option to close buffers of the project to forget.
   ("f p" "a project" disproject-forget-project)
   ("f u" "projects under..." disproject-forget-projects-under)
   ("f z" "zombie projects" disproject-forget-zombie-projects)]
  ["Remember"
   ("r o" "open projects" disproject-remember-projects-open)
   ("r u" "projects under..." disproject-remember-projects-under)]
  ["Deprecated"
   :hide always
   ;; DEPRECATED: Remove when `disproject-remember-projects-active' is removed.
   ("r a" "active projects" disproject-remember-projects-active)])


;;;
;;; Transient state handling.
;;;

(defun disproject--open-projects ()
  "Return a list of projects with open buffers."
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

(defun disproject--scope ()
  "Return the scope for a `disproject-prefix' prefix."
  ;; Always fall back to initializing scope from `disproject-prefix' (i.e. class
  ;; of `disproject-dispatch') rather than a child class to be predictable.
  (transient-scope (cons 'disproject-dispatch
                         disproject-prefix--transient-commands)))

;;;; Transient state classes.

;;;;; Project class.

(defclass disproject-project ()
  ;; root must be a path to a valid project.  An `initialize-instance' method
  ;; for this class enforces this.
  ((root :reader disproject-project-root
         :initarg :root
         :type string
         :documentation "Project root directory.")
   (instance :reader disproject-project-instance
             :type list
             :documentation "Project `project.el' instance.")
   (backend :reader disproject-project-backend
            :type symbol
            :documentation "Project VC backend.")
   (custom-suffixes :reader disproject-project-custom-suffixes
                    :type list
                    :documentation "\
Project's custom suffixes as described in
`disproject-custom-suffixes'."))
  "Class representing a `project.el' project.

Instances of this class are initialized by providing the `:root'
initialization argument, which is the only argument available.
Other slots depend on this value, and are lazily fetched as
needed when calling readers.  These fetched values are then
cached for subsequent queries.")

(cl-defmethod initialize-instance :after ((obj disproject-project) &rest _slots)
  "Do additional initialization for a `disproject-project' instance.

This enforces that the root is part of a valid project.  If
unbound, `project-current' will be invoked, which may prompt the
user for a path.  If the path does not lead to a valid project,
an error will be signaled.  \"Transient\" project instances are
not considered valid.

If the directory provided is not actually the root directory, the
slot will also be changed to the detected root.

Additionally, the project will be force-remembered as a known
project as a last step of initialization."
  (let* ((provided-root (if (slot-boundp obj 'root)
                            (oref obj root)
                          (project-root (project-current t))))
         (project (oset obj instance (project-current nil provided-root))))
    (unless project
      (error "Root directory does not lead to valid project: %s" provided-root))
    ;; The provided root may be a sub-directory, so we re-set it to the root
    ;; determined by `project.el'.
    (oset obj root (project-root project))
    ;; Remember the project in case it's not in `project-known-project-roots'.
    (project-remember-project project)))

(defun disproject-project-or-nil (&optional directory)
  "Return a `disproject-project' instance for DIRECTORY, or maybe nil.

DIRECTORY is passed to `project-current' to detect a project."
  (if-let* ((project (project-current nil directory)))
      (disproject-project :root (project-root project))))

(cl-defmethod disproject-project-backend ((obj disproject-project))
  "Return the OBJ project backend.

This internally uses `project-try-vc' to determine the backend."
  (if (slot-boundp obj 'backend)
      (oref obj backend)
    ;; XXX: `project-find-functions' (used in `project-current') doesn't enforce
    ;; a project instance format, so we can't expect the VC backend to be in the
    ;; same place in `disproject-project-instance'.  Instead, we specifically
    ;; rely on `project-try-vc' (`project-vc-backend-markers-alist') to get the
    ;; backend.
    (oset obj backend (let* ((root (disproject-project-root obj))
                             (instance (project-try-vc root)))
                        ;; Expect index 1 to be the VC backend of the project
                        ;; instance.
                        (nth 1 instance)))))

(cl-defmethod disproject-project-custom-suffixes ((obj disproject-project))
  "Return the OBJ project custom suffixes."
  (if (slot-boundp obj 'custom-suffixes)
      (oref obj custom-suffixes)
    (oset obj
          custom-suffixes
          (if-let*
              ((project (disproject-project-instance obj))
               (root (disproject-project-root obj))
               (suffixes
                ;; Retrieve custom suffixes without triggering dir-locals
                ;; permissions prompt.
                (alist-get 'disproject-custom-suffixes
                           (with-temp-buffer
                             (let ((default-directory root))
                               (hack-dir-local--get-variables nil)))))
               ((disproject--assert-type 'disproject-custom-suffixes suffixes))
               ((disproject-custom--suffixes-allowed? project suffixes)))
              suffixes
            (default-value 'disproject-custom-suffixes)))))

;;;;; Scope class.

(defclass disproject-scope ()
  ((selected-project :initarg :selected-project
                     :accessor disproject-scope-selected-project
                     :initform nil
                     :type (or null disproject-project)
                     :documentation "\
Currently selected project object in the transient menu, if any.
If no value is provided during initialization, the function
`project-current' is used to find one for initializing a
`disproject-project' object.  This slot may be nil.")
   (default-project :reader disproject-scope-default-project
                    :initform nil
                    :type (or null disproject-project)
                    :documentation "\
Project object belonging to `default-directory' at the time of
initialization (or the current buffer, in other words), if any.")
   (prefer-other-window? :initarg :prefer-other-window?
                         :accessor disproject-scope-prefer-other-window?
                         :initform nil
                         :documentation "Non-nil to prefer other window."))
  "Class representing a Disproject menu's transient scope.

Objects of this type are intended to be used in a transient
prefix's `:scope' slot, and contains information regarding the
default project, selected project, and other state like option
values that should be shared with other menus.

In Disproject prefixes, this scope object is normally fetched via
the function `disproject--scope'.")

(cl-defmethod initialize-instance :after ((obj disproject-scope) &rest _slots)
  "Do additional initialization for scope OBJ."
  (let* ((default-project-obj
          (disproject-project-or-nil default-directory))
         (selected-project-obj
          ;; `project-current' may read other variables like
          ;; `project-current-directory-override', which may make the initial
          ;; selected project different from the default project (only
          ;; `default-directory' is read for the latter).
          (if-let* ((current-project (project-current))
                    ;; Use `default-project-obj' if the projects happen to be
                    ;; the same so cached values are shared.
                    ((or (not default-project-obj)
                         (not (file-equal-p
                               (project-root current-project)
                               (disproject-project-root default-project-obj))))))
              (disproject-project :root (project-root current-project))
            default-project-obj)))
    (when default-project-obj
      (oset obj default-project default-project-obj))
    (when selected-project-obj
      (oset obj selected-project selected-project-obj))))

(cl-defmethod disproject-scope-selected-project ((obj disproject-scope))
  "Return scope OBJ selected project.  May be nil."
  (if (slot-boundp obj 'selected-project)
      (oref obj selected-project)))

(cl-defmethod disproject-scope-selected-project-ensure ((obj disproject-scope))
  "Return scope OBJ selected project.

If the selected-project slot is nil, a new instance of
`disproject-project' will be initialized and written to the slot.
The user may be prompted for a project."
  (or (disproject-scope-selected-project obj)
      (oset obj selected-project (disproject-project))))

(cl-defmethod disproject-scope-default-project ((obj disproject-scope))
  "Return scope OBJ default project.  May be nil."
  (if (slot-boundp obj 'default-project)
      (oref obj default-project)))

(cl-defmethod disproject-scope-project-is-default? ((obj disproject-scope))
  "Return non-nil if the OBJ scope's selected and default projects are the same."
  (and-let* ((default-project (disproject-scope-default-project obj))
             (selected-project (disproject-scope-selected-project obj)))
    (file-equal-p (disproject-project-root default-project)
                  (disproject-project-root selected-project))))

;;;; Getters for infix arguments.

(defun disproject--state-prefer-other-window? ()
  "Return whether other window should be preferred when displaying buffers."
  (if (eq transient-current-command 'disproject-dispatch)
      (let ((args (transient-args transient-current-command)))
        (and args (transient-arg-value "--prefer-other-window" args)))
    (disproject-scope-prefer-other-window? (disproject--scope))))


;;;
;;; Suffix handling.
;;;

(defun disproject-process-buffer-name (project-dir &optional identifier)
  "Return a project's process buffer name corresponding to IDENTIFIER.

PROJECT-DIR is the project directory, which will be used to give
project buffers a unique namespace.

IDENTIFIER is an optional string argument that can be specified
to make the buffer name unique to the project's process buffers.
If non-nil, \"default\" is used as the identifier.

This function is *not* meant to be used like
`project-prefixed-buffer-name', although it is similar in
functionality; the identifier should not be tied to the buffer
mode in any way.  It should be the only means of making a name
unique in the context of a project.  This allows users to track
buffers based on just an identifier and also allow specifying
incompatible commands (e.g. if two commands use the same buffer
name, they should not be allowed to run at the same time)."
  (concat "*"
          (file-name-nondirectory (directory-file-name project-dir))
          "-process|"
          (or identifier "default")
          "*"))

(defun disproject-add-sentinel-refresh-transient (buffer-name)
  "Add function to a buffer's process sentinel to refresh transient, if active.

BUFFER-NAME is the name of the buffer with a process sentinel the
function will be added to."
  (when-let* ((buffer (get-buffer buffer-name))
              (process (get-buffer-process buffer))
              ((not (advice-function-member-p
                     #'disproject--refresh-transient
                     (process-sentinel process)))))
    (add-function
     :before (process-sentinel process)
     #'disproject--refresh-transient)))

(defun disproject-custom--suffix (spec-entry)
  "Construct and return a suffix to be parsed by `transient-parse-suffixes'.

SPEC-ENTRY is a single entry from the specification described by
`disproject-custom-suffixes'."
  (pcase spec-entry
    (`( ,key ,description
        .
        ,(map :command-type :command :identifier))
     (let* ((project (disproject-scope-selected-project-ensure
                      (disproject--scope)))
            ;; Fall back to description if identifier is not provided.
            ;; Uniqueness is preferred over the name looking nice to prevent
            ;; unintentionally making commands incompatible.
            (identifier (or identifier description))
            (disproject-process-buffer-name (disproject-process-buffer-name
                                             (disproject-project-root project)
                                             identifier)))
       `(,key
         ,(disproject-custom--suffix-description
           (get-buffer disproject-process-buffer-name)
           description)
         (lambda ()
           (interactive)
           ;; Expose buffer name to the user; see note in
           ;; `disproject-custom-suffixes'.
           (let ((disproject-process-buffer-name ,disproject-process-buffer-name))
             ,(disproject-custom--suffix-command command-type command)
             (disproject-add-sentinel-refresh-transient
              disproject-process-buffer-name))))))))

(defun disproject-custom--suffix-command (command-type command)
  "Dispatch a command s-expression to be evaluated in a custom suffix.

COMMAND-TYPE is a symbol corresponding to a command type
documented in `disproject-custom-suffixes'.

COMMAND is an yet-to-be-evaluated s-expression which is inserted
appropriately according to the command type.

Note that the returned s-expressions may expect
`disproject-process-buffer-name' to be set when evaluated; this
value is expected to be the name of the buffer which processes
will run."
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
     `(disproject-with-environment
        (let ((command ,command))
          (cond
           ((commandp command t)
            (call-interactively command))
           (t
            ,(disproject-custom--suffix-command-type-error
              "Not an interactive function" command-type command))))))
    ('compile
     `(disproject-with-environment
        (let* ((compilation-buffer-name-function
                (lambda (&rest _ignore) disproject-process-buffer-name))
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
                       command)))))))
    ('run
     `(disproject-with-environment
        (let ((shell-command-buffer-name-async disproject-process-buffer-name)
              (command ,command))
          (async-shell-command
           (cond ((stringp command)
                  command)
                 ((commandp command t)
                  (if-let* ((result (call-interactively command))
                            ((stringp result)))
                      result
                    ,(disproject-custom--suffix-command-type-error
                      "Function does not return string"
                      command-type
                      command)))
                 (t
                  ,(disproject-custom--suffix-command-type-error
                    "Not a string or interactive function"
                    command-type
                    command)))))))
    (_
     (display-warning
      'disproject
      (format-message "Custom suffix command type not recognized: `%s'"
                      command-type)))))

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

BUFFER is the associated custom suffix buffer.  It may be nil.

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

(defun disproject--refresh-transient (&rest _ignore)
  "Refresh the currently active transient, if available."
  (when (transient-active-prefix)
    (transient--refresh-transient)))

(defun disproject--switch-project (search-directory)
  "Modify the Transient scope to switch to another project.

Look for a valid project root directory in SEARCH-DIRECTORY.  If
one is found, update the Transient scope to switch the selected
project."
  (setf (disproject-scope-selected-project (disproject--scope))
        (disproject-project :root search-directory)))

;;;; Suffix environment.

(defvar disproject--environment-scope nil
  "Current disproject scope in `disproject-with-environment'.

This is for suffixes that use `disproject-with-environment',
normally by specifying the class as `disproject-suffix' or a
subclass of it.  It is preferred to use this when possible over
`disproject--scope' to avoid cases where there is no scope,
causing a new `disproject-scope' to be initialized on every call
and potentially resulting in duplicate prompts.")

(defmacro disproject-with-environment (&rest body)
  "Run BODY with `disproject' \"environment\" options set.

The \"environment\" consists of the following overrides:

`default-directory', `project-current-directory-override': Set to
the project's root directory.

`display-buffer-overriding-action': Set to display in another
window if \"--prefer-other-window\" is enabled."
  (declare (indent 0) (debug t))
  `(let* ((disproject--environment-scope (disproject--scope))
          (project (disproject-project-instance
                    (disproject-scope-selected-project-ensure
                     disproject--environment-scope)))
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
         (hack-dir-local-variables-non-file-buffer)
         ;; Make sure commands are run in the correct direnv environment
         ;; if envrc-mode is enabled.
         (when enable-envrc (funcall enable-envrc))
         ;; Make sure commands are run in the correct mise environment
         ;; if mise-mode is enabled.
         (when enable-mise (funcall enable-mise))
         ,@body))))

;;;; Suffix classes.

;;;;; Main Disproject suffix class.

(defclass disproject-suffix (transient-suffix) ()
  "Class for Disproject suffixes.

This is the top-level class that simply applies options from
`disproject-with-environment' when the command is run.

The `disproject-suffix-wrappers' method is intended for
modification of the suffix command's behavior.  Classes may
inherit from this class to, for example, set a variable to be
available in the environment.")

(cl-defmethod initialize-instance :before ((obj disproject-suffix) &optional slots)
  "Do additional initialization for OBJ before everything else.

Wrap the command in SLOTS with wrappers from `disproject-suffix-wrappers'."
  ;; We should avoid adding advice directly to the initial command, since the
  ;; command values may reference commands used in other cases where advice
  ;; shouldn't be run.
  (let* ((sym (plist-get slots :command))
         (old-command (symbol-function sym))
         (new-command (seq-reduce (lambda (command wrapper)
                                    (lambda (&rest _r) (interactive)
                                      (funcall wrapper command)))
                                  (disproject-suffix-wrappers obj)
                                  old-command)))
    ;; This may produce incorrect results.  If a new prefix is defined that uses
    ;; this suffix with another class, for example, this can affect the suffix's
    ;; behavior in other prefixes.
    (advice-remove sym 'disproject-suffix)
    (advice-add sym :override new-command '((name . disproject-suffix)))))


(cl-defmethod disproject-suffix-wrappers ((_obj disproject-suffix))
  "Return a list of functions to wrap the initial suffix command.

The functions should take as argument a 0-arity interactive
command to wrap, calling interactively where appropriate.  The
first function in the list will be the innermost wrapper."
  (list (lambda (command)
          (disproject-with-environment
            (call-interactively command)))))

;;;;; Abstract suffix class for commands that spawn a process.

(defclass disproject-process-suffix (disproject-suffix)
  ((buffer-id :initarg :buffer-id
              :initform nil
              :documentation "\
String.  Unique identifier, used to construct the name of the
process buffer associated with this suffix command.

Users may set the same identifier for multiple commands to mark
them as incompatible (only one can run at a given time).  This
relies on commands like `compile' to notify the user that a
buffer with the same name already has a process running.

If the `description' slot of the instance is a string, it may be
used as the default value instead for uniqueness.  Otherwise -
assuming that if the description is not a string, it's a function
- \"default\" will be used, since there is no way to guarantee
that a function will always return the same identifier.")
   (display-status? :initarg :display-status?
                    :initform t
                    :documentation "\
Non-nil to display status of process in associated buffer."))
  "Class for Disproject suffixes that spawn a process that should be tracked.

This provides methods for managing things related to the
associated command's process buffer.

Classes that inherit from this must still implement their own
logic to guarantee that the associated process buffer has the
correct name."
  :abstract t)

(cl-defmethod initialize-instance :after ((obj disproject-process-suffix)
                                          &rest _slots)
  "Do additional initialization for OBJ."
  (when (null (oref obj buffer-id))
    (let ((description (oref obj description)))
      (oset obj buffer-id (if (stringp description)
                              description
                            "default")))))

;; TODO: This should be renamed to `disproject-process-buffer-name' to indicate
;; it can be used by other packages, but the name is currently occupied; do so
;; once the old function is removed.
(cl-defmethod disproject--process-buffer-name ((obj disproject-process-suffix)
                                               project-name)
  "Return the OBJ suffix's process's buffer name associated with PROJECT-NAME.

PROJECT-NAME is the project name, which will be used to give a
unique namespace to the project's process buffers."
  (concat "*"
          project-name
          "-process|"
          (oref obj buffer-id)
          "*"))

(cl-defmethod transient-format-description ((obj disproject-process-suffix))
  "Format description for OBJ.

If the `display-status?' slot is non-nil, the description will be
formatted with an indicator that tracks the associated process
buffer's status."
  ;; Preserve the transient "bug" warning if there is no description.
  (if-let* ((description (cl-call-next-method)))
      (if-let* (((oref obj display-status?))
                (project (disproject-scope-selected-project (disproject--scope)))
                (buffer (get-buffer (disproject--process-buffer-name
                                     obj
                                     (project-name
                                      (disproject-project-instance project))))))
          (concat (cond
                   ((null buffer)
                    "")
                   ((get-buffer-process buffer)
                    (concat (propertize "[a]" 'face 'transient-enabled-suffix)
                            " "))
                   (t
                    (concat (propertize "[i]" 'face 'transient-inactive-value)
                            " ")))
                  description)
        description)))

(cl-defmethod disproject-suffix-wrappers ((obj disproject-process-suffix))
  "Return a list of wrappers for the initial command of OBJ after adding its own.

When the `display-status?' slot is non-nil, add a sentinel to
refresh the transient on completion so the description can update
to reflect the correct status."
  (cons (lambda (command)
          (call-interactively command)
          (when (oref obj display-status?)
            (disproject-add-sentinel-refresh-transient
             (disproject--process-buffer-name
              obj
              (project-name (disproject-project-instance
                             (disproject-scope-selected-project-ensure
                              disproject--environment-scope)))))))
        (cl-call-next-method)))

;;;;; Suffix class for compilation commands.

(defclass disproject-compilation-suffix (disproject-process-suffix) ()
  "Disproject suffix class for compilation commands.

When using this class, the `command' slot should be a function
that returns a string or nil.  The string will be passed to
`compile'; otherwise, if the value is nil, `compile' will be
called interactively.")

(cl-defmethod disproject-suffix-wrappers ((obj disproject-compilation-suffix))
  "Return a list of wrappers for the initial command of OBJ after adding its own.

Set `compilation-buffer-name-function' and `compile' the
command's return value."
  (cons (lambda (command)
          (let* ((buf-name
                  (disproject--process-buffer-name
                   obj
                   (project-name (disproject-project-instance
                                  (disproject-scope-selected-project-ensure
                                   disproject--environment-scope)))))
                 (compilation-buffer-name-function
                  (cl-constantly buf-name)))
            (if-let* ((shell-command (call-interactively command)))
                (compile shell-command)
              (call-interactively #'compile))))
        (cl-call-next-method)))

;;;;; Suffix class for shell commands.

(defclass disproject-shell-command-suffix (disproject-process-suffix)
  ((new-process-buffer :initarg :new-process-buffer
                       :initform 'confirm-kill-process
                       :type (or null symbol)
                       :documentation "\
Value passed to `async-shell-command-buffer'.

`disproject-process-suffix' is intended to be used with only a
single process buffer, so `confirm-kill-process' is the default
value to prevent other buffers (and processes) from being
existing simultaneously.  In cases where this is not desired, the
value may be set to another symbol recognized by
`async-shell-command-buffer'.

If the value is nil, the current value of
`async-shell-command-buffer' will be used instead."))
  "Disproject suffix class for shell commands.

When using this class, the `command' slot should be a function
that returns a string or nil.  If the value is a string, it will
be passed to `async-shell-command'; otherwise, nil causes
`async-shell-command' to be called interactively.")

(cl-defmethod disproject-suffix-wrappers ((obj disproject-shell-command-suffix))
  "Return a list of wrappers for the initial command for OBJ after adding its own.

Set `shell-command-buffer-name-async' and
`async-shell-command-buffer' and apply `async-shell-command' to
the command's return value."
  (cons (lambda (command)
          (let* ((buf-name
                  (disproject--process-buffer-name
                   obj
                   (project-name (disproject-project-instance
                                  (disproject-scope-selected-project-ensure
                                   disproject--environment-scope)))))
                 (shell-command-buffer-name-async
                  buf-name)
                 (async-shell-command-buffer
                  (if-let* ((new-process-buffer
                             (oref obj new-process-buffer)))
                      new-process-buffer
                    async-shell-command-buffer)))
            (if-let* ((shell-command (call-interactively command)))
                (async-shell-command shell-command)
              (call-interactively #'async-shell-command))))
        (cl-call-next-method)))

;;;; Suffix setup functions.

(defun disproject-custom--old-form? (sexp)
  "Return non-nil if SEXP seems like the old syntax for custom suffixes.

This assumes that SEXP conforms to the old syntax if it is a list
of lists, where the first list element has the `:command-type'
keyword."
  (and (listp sexp)
       (listp (car sexp))
       (memq :command-type (car sexp))))

(defun disproject-custom--setup-suffixes (_)
  "Set up suffixes according to `disproject-custom-suffixes'."
  (transient-parse-suffixes
   'disproject-custom-dispatch
   (let ((custom-suffixes (disproject-project-custom-suffixes
                           (disproject-scope-selected-project-ensure
                            (disproject--scope)))))
     (if (disproject-custom--old-form? custom-suffixes)
         (list (vconcat (mapcar #'disproject-custom--suffix custom-suffixes)))
       ;; Value can omit vectorizing value if only one column of suffixes is
       ;; specified.
       (if (and (listp custom-suffixes) (listp (car custom-suffixes)))
           (list (vconcat custom-suffixes))
         custom-suffixes)))))

;;;; Suffixes.

(transient-define-suffix disproject-dired ()
  "Open Dired in project root."
  :class disproject-suffix
  (interactive)
  (call-interactively #'project-dired))

(transient-define-suffix disproject-dir-locals ()
  "Open `dir-locals-file' in the project root.

If prefix arg is non-nil, open the personal secondary
file (\".dir-locals-2.el\" by default)."
  :class disproject-suffix
  (interactive)
  (find-file (if current-prefix-arg
                 (concat (file-name-base dir-locals-file)
                         "-2."
                         (file-name-extension dir-locals-file))
               dir-locals-file)))

(transient-define-suffix disproject-execute-extended-command ()
  "Execute an extended command in project root."
  :class disproject-suffix
  (interactive)
  (call-interactively #'execute-extended-command))

(transient-define-suffix disproject-find-dir ()
  "Find directory in project.

The command used can be customized with
`disproject-find-dir-command'."
  :class disproject-suffix
  (interactive)
  (call-interactively disproject-find-dir-command))

(transient-define-suffix disproject-find-file ()
  "Find file in project.

The command used can be customized with
`disproject-find-file-command'."
  :class disproject-suffix
  (interactive)
  (call-interactively disproject-find-file-command))

(transient-define-suffix disproject-find-line ()
  "Find matching line in project's open buffers."
  :class disproject-suffix
  (interactive)
  (call-interactively disproject-find-line-command))

(transient-define-suffix disproject-find-regexp ()
  "Search project for regexp.

The command used can be customized with
`disproject-find-regexp-command'."
  :class disproject-suffix
  (interactive)
  (call-interactively disproject-find-regexp-command))

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

(transient-define-suffix disproject-git-clone-fallback (repository
                                                        directory
                                                        &optional
                                                        arguments)
  "Git-clone REPOSITORY into DIRECTORY.

ARGUMENTS is \"git clone\" by default.  If prefix arg is non-nil,
prompt to modify ARGUMENTS options.

\" -- <repository> <directory>\" is appended to ARGUMENTS, which
is executed as a shell command.

This command relies on the \"git\" executable being in the
programs path."
  (interactive "GRepository: \nGDirectory: ")
  (let* ((directory (expand-file-name directory))
         (arguments (or arguments
                        (if current-prefix-arg
                            (read-shell-command "git arguments: " "git clone ")
                          "git clone ")))
         (buf-name (disproject-process-buffer-name directory "git")))
    (async-shell-command (concat arguments " -- " repository " " directory)
                         buf-name)
    (switch-to-buffer-other-window buf-name)
    (setq default-directory directory)))

(transient-define-suffix disproject-git-init-fallback (directory
                                                       &optional
                                                       arguments)
  "Initialize a git repository in DIRECTORY.

ARGUMENTS is \"git init\" by default.  If prefix arg is non-nil,
prompt to modify ARGUMENTS.

\" -- <directory>\" is appended to ARGUMENTS, which is executed
as a shell command.

This command relies on the \"git\" executable being in the
programs path."
  (interactive "GDirectory: ")
  (let* ((directory (expand-file-name directory))
         (arguments (or arguments
                        (if current-prefix-arg
                            (read-shell-command "git arguments: " "git init ")
                          "git init ")))
         (buf-name (disproject-process-buffer-name directory "git")))
    (async-shell-command (concat arguments " -- " directory) buf-name)
    (switch-to-buffer-other-window buf-name)
    (setq default-directory directory)))

(transient-define-suffix disproject-kill-buffers ()
  "Kill all buffers related to project."
  :class disproject-suffix
  (interactive)
  (call-interactively #'project-kill-buffers))

(transient-define-suffix disproject-list-buffers ()
  "Display a list of open buffers for project."
  :class disproject-suffix
  (interactive)
  (call-interactively #'project-list-buffers))

;; DEPRECATED: Remove at least 1 month after earliest release with deprecation.
(define-obsolete-function-alias 'disproject-magit-status
  #'disproject-vc-status "after v1.2")

(transient-define-suffix disproject-magit-todos-list ()
  "Open a `magit-todos-list' buffer for project."
  :class disproject-suffix
  (interactive)
  (declare-function magit-todos-list-internal "magit-todos")
  (magit-todos-list-internal default-directory))

(transient-define-suffix disproject-or-external-find-file ()
  "Find file in project or external roots.

The command used can be customized with
`disproject-or-external-find-file-command'."
  :class disproject-suffix
  (interactive)
  (call-interactively disproject-or-external-find-file-command))

(transient-define-suffix disproject-or-external-find-regexp ()
  "Find regexp in project or external roots.

The command used can be customized with
`disproject-or-external-find-regexp-command'."
  :class disproject-suffix
  (interactive)
  (call-interactively disproject-or-external-find-regexp-command))

(transient-define-suffix disproject-compile ()
  "Call `project-compile' in project.

The buffer name is determined by
`disproject-process-buffer-name', which will be used to track the
process status."
  :class disproject-compilation-suffix
  :buffer-id "default-compile"
  (interactive))

(transient-define-suffix disproject-remember-projects-open ()
  "Remember projects with open buffers."
  (interactive)
  (when-let* ((open-projects (disproject--open-projects)))
    (seq-each (lambda (project)
                (project-remember-project project t))
              open-projects)
    (project--write-project-list)))

;; DEPRECATED: Remove at least 1 month after deprecation.
(define-obsolete-function-alias 'disproject-remember-projects-active
  #'disproject-remember-projects-open "after v1.1")

(transient-define-suffix disproject-remember-projects-under ()
  "Remember projects under a directory with `project-remember-projects-under'."
  (interactive)
  (call-interactively #'project-remember-projects-under))

(transient-define-suffix disproject-shell ()
  "Start a shell in project.

The command used can be customized with the variable
`disproject-shell-command'."
  :class disproject-suffix
  (interactive)
  (call-interactively disproject-shell-command))

(transient-define-suffix disproject-shell-command ()
  "Run a shell command asynchronously in a project."
  :class disproject-shell-command-suffix
  :new-process-buffer nil
  :display-status? nil
  :buffer-id "default-shell-command"
  (interactive))

(transient-define-suffix disproject-switch-project ()
  "Switch project to dispatch commands on.

Uses `project-prompt-project-dir' to switch project root
directories."
  (interactive)
  (disproject--switch-project (project-prompt-project-dir)))

(transient-define-suffix disproject-switch-project-open ()
  "Switch to an open project to dispatch commands on.

This is equivalent to `disproject-switch-project' but only shows
projects with open buffers when prompting for projects to switch
to."
  (interactive)
  (let* ((open-projects (mapcar #'project-root (disproject--open-projects)))
         ;; `project--file-completion-table' seems to accept any collection as
         ;; defined by `completing-read'.
         (completion-table (project--file-completion-table open-projects))
         (project-directory (completing-read "Select open project: "
                                             completion-table nil t)))
    (disproject--switch-project project-directory)))

;; DEPRECATED: Remove at least 1 month after deprecation.
(define-obsolete-function-alias 'disproject-switch-project-active
  #'disproject-switch-project-open "after v1.1")

(transient-define-suffix disproject-switch-to-buffer ()
  "Switch to buffer in project.

The command used can be customized with
`disproject-switch-to-buffer-command'."
  :class disproject-suffix
  (interactive)
  (call-interactively disproject-switch-to-buffer-command))

;; DEPRECATED: Remove at least 1 month after earliest release with deprecation.
(define-obsolete-function-alias 'disproject-vc-dir
  #'disproject-vc-status "after v1.2")

(transient-define-suffix disproject-vc-status ()
  "Dispatch a VC status command depending on the project backend.

The status command used depends on the variable
`disproject-vc-status-commands' - see its documentation for
configuring this function's behavior.  The chosen function will
be called interactively."
  :class disproject-suffix
  :description
  (lambda ()
    (concat (if-let* ((project (disproject-scope-selected-project
                                (disproject--scope)))
                      (backend (disproject-project-backend project)))
                ;; The number chosen for this is somewhat arbitrary, but should
                ;; be fine as long as the end result is around the same size as
                ;; the other descriptions in its column.
                (truncate-string-to-width (symbol-name backend) 6 nil nil t)
              "VC")
            " status"))
  (interactive)
  (let* ((project (disproject-scope-selected-project-ensure
                   disproject--environment-scope))
         (backend (disproject-project-backend project)))
    (unless backend
      (user-error "No backend found for project: %s"
                  (disproject-project-root project)))
    (call-interactively
     (if-let* ((command (alist-get backend disproject-vc-status-commands))
               ((fboundp command)))
         command
       (alist-get nil disproject-vc-status-commands)))))

(provide 'disproject)
;;; disproject.el ends here
