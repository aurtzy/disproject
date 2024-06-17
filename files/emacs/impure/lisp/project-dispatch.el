;;; project-dispatch.el --- Dispatch project commands with transient  -*- lexical-binding: t; -*-

;; Copyright (C) 2024  aurtzy

;; Author: aurtzy <aurtzy@gmail.com>
;; Keywords: convenience

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

;; 

;;; Code:

(require 'consult)
(require 'eat)
(require 'magit)
(require 'project)
(require 'transient)

(transient-define-prefix project-dispatch ()
  "Dispatch some command for a project."
  ["Options"
   (project-dispatch:--root-directory)]
  ["Commands"
   ("b" "Buffer" project-dispatch-buffer)
   ("D" "Dired" project-dispatch-project-dired)
   ("f" "Find" project-dispatch-find)
   ("m" "Magit status" project-dispatch-magit-status)
   ("s" "Shell (Eat)" project-dispatch-shell-eat)
   ("!" "Run" project-dispatch-project-shell-command)
   ("M-x" "Extended command" project-dispatch-project-execute-extended-command)])

(transient-define-prefix project-dispatch-buffer ()
  "Dispatch commands for buffer management in a project."
  ["Buffer"
   ("b" "Switch" project-dispatch-consult-project-buffer)
   ("B" "List all" project-dispatch-project-list-buffers)
   ("K" "Kill all" project-dispatch-project-kill-buffers)])

(transient-define-prefix project-dispatch-find ()
  "Dispatch commands for finding stuff in a project."
  ["Find"
   ("d" "Directory" project-dispatch-project-find-dir)
   ("f" "File" project-dispatch-project-find-file)
   ("F" "File (incl. external)" project-dispatch-project-or-external-find-file)])

(defun project-dispatch--read-root-directory (&rest _ignore)
  "Reader function for project root directory."
  (expand-file-name (project-prompt-project-dir)))

(transient-define-infix project-dispatch:--root-directory ()
  :description "Root directory"
  :class 'transient-option
  :key "-d"
  :argument "--root-directory="
  :init-value (lambda (obj)
                (oset obj value (project-root (project-current t))))
  :always-read t
  :allow-empty nil
  :reader #'project-dispatch--read-root-directory)

(defun project-dispatch--root-directory-arg ()
  "Return the project root directory defined in transient arguments."
  (let* ((args (transient-args transient-current-command)))
    (if args
        (transient-arg-value "--root-directory=" args)
      (project-root (project-current t)))))

;; TODO Some of these suffixes are stubs and not used (yet?)

(transient-define-suffix project-dispatch-consult-project-buffer ()
  "Consult buffers in project."
  (interactive)
  (let ((project-current-directory-override
         (project-dispatch--root-directory-arg)))
    (consult-project-buffer)))

(transient-define-suffix project-dispatch-project-list-buffers ()
  "Display a list of open buffers for project."
  (interactive)
  (let ((project-current-directory-override
         (project-dispatch--root-directory-arg)))
    (project-list-buffers)))

(transient-define-suffix project-dispatch-project-find-dir ()
  "Find directory in project."
  (interactive)
  (let ((project-current-directory-override
         (project-dispatch--root-directory-arg)))
    (project-find-dir)))

(transient-define-suffix project-dispatch-project-dired ()
  "Open Dired in project root."
  (interactive)
  (let ((project-current-directory-override
         (project-dispatch--root-directory-arg)))
    (project-dired)))

(transient-define-suffix project-dispatch-project-find-file ()
  "Find file in project."
  (interactive)
  (let ((project-current-directory-override
         (project-dispatch--root-directory-arg)))
    (project-find-file)))

(transient-define-suffix project-dispatch-project-or-external-find-file ()
  "Find file in project or related external roots."
  (interactive)
  (let ((project-current-directory-override
         (project-dispatch--root-directory-arg)))
    (project-or-external-find-file)))

(transient-define-suffix project-dispatch-project-kill-buffers ()
  "Kill all buffers related to project."
  (interactive)
  (let ((project-current-directory-override
         (project-dispatch--root-directory-arg)))
    (call-interactively #'project-kill-buffers)))

(transient-define-suffix project-dispatch-magit-status ()
  "Show status of Git repository of project with Magit."
  (interactive)
  (let ((project-current-directory-override
         (project-dispatch--root-directory-arg)))
    (magit-project-status)))

(transient-define-suffix project-dispatch-shell-eat ()
  "Start an Eat terminal emulator in project."
  (interactive)
  (let* ((project-current-directory-override
          (project-dispatch--root-directory-arg)))
    (eat-project t)))

(transient-define-suffix project-dispatch-project-shell-command ()
  "Run a shell command asynchronously in a project."
  (interactive)
  (let ((project-current-directory-override
         (project-dispatch--root-directory-arg)))
    (call-interactively #'project-async-shell-command)))

(transient-define-suffix project-dispatch-project-execute-extended-command ()
  "Execute an extended command in project root."
  (interactive)
  (let ((project-current-directory-override
         (project-dispatch--root-directory-arg)))
    (call-interactively #'project-execute-extended-command)))

(transient-define-suffix project-dispatch-project-query-replace-regexp ()
  ""
  (interactive)
  (let ((project-current-directory-override
         (project-dispatch--root-directory-arg)))
    nil))

(transient-define-suffix project-dispatch-project-find-regexp ()
  ""
  (interactive)
  (let ((project-current-directory-override
         (project-dispatch--root-directory-arg)))
    nil))

(transient-define-suffix project-dispatch-project-shell ()
  ""
  (interactive)
  (let ((project-current-directory-override
         (project-dispatch--root-directory-arg)))
    nil))

(transient-define-suffix project-dispatch-project-eshell ()
  ""
  (interactive)
  (let ((project-current-directory-override
         (project-dispatch--root-directory-arg)))
    nil))

(transient-define-suffix project-dispatch-project-compile ()
  ""
  (interactive)
  (let ((project-current-directory-override
         (project-dispatch--root-directory-arg)))
    nil))

(transient-define-suffix project-dispatch-project-vc-dir ()
  ""
  (interactive)
  (let ((project-current-directory-override
         (project-dispatch--root-directory-arg)))
    nil))

(provide 'project-dispatch)
;;; project-dispatch.el ends here
