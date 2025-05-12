;;; disproject-test.el --- Tests for Disproject      -*- lexical-binding: t; -*-

;; Copyright (C) 2025 aurtzy

;; Author: aurtzy <aurtzy@gmail.com>

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

;;; Code:

(require 'ert)
(require 'eieio)
(require 'project)
(require 'disproject)

(defmacro disproject-with-temp-dir (&rest body)
  "Create an temporary empty directory to do tests in.

Set `default-directory' to the new directory before executing
BODY.  Clean up the directory after completion."
  (declare (indent 1))
  `(let ((default-directory (file-name-as-directory
                             (make-temp-file "disproject-test-" t))))
     (message "TEST DIR: %s" default-directory)
     ,@body
     (delete-directory default-directory t)))

(ert-deftest disproject-numbers ()
  (should (eql 1 2)))

;;; TODO: Convert everything below to ERT tests.

;;; Test `disproject-project'

;; (message "-----
;; START: `disproject-project'")

;; (defvar test-project nil)
;; (setq test-project (disproject-project :root "~/src/disproject"))

;; (message "[project] %s" test-project)
;; (message "[root] %s" (disproject-project-root test-project))
;; (message "[instance] %s" (disproject-project-instance test-project))
;; (message "[backend] %s" (disproject-project-backend test-project))
;; (message "[custom-suffixes] %s" (disproject-project-custom-suffixes test-project))
;; (message "[project] %s" test-project)

;; (message "END: `disproject-project'")

;; ;;; Test `disproject-scope'

;; (message "-----
;; START: `disproject-scope'")

;; (defvar test-scope nil)
;; (setq test-scope (disproject-scope))

;; (message "[scope] %s" test-scope)
;; (message "[selected project] %s" (disproject-scope-selected-project test-scope))
;; (message "[default project] %s" (disproject-scope-default-project test-scope))
;; (message "[prefer-other-window] %s" (disproject-scope-prefer-other-window? test-scope))
;; (disproject-project-custom-suffixes (disproject-scope-selected-project test-scope))
;; (message "[scope] %s" test-scope)
;; (setf (disproject-scope-selected-project test-scope) (disproject-project))
;; (message "[scope] %s" test-scope)

;; (message "END: `disproject-scope'")

(provide 'disproject-test)
;;; disproject-tests.el ends here
