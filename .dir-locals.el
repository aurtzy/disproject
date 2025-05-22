;;; Directory Local Variables         -*- no-byte-compile: t; -*-
;;; For more information see (info "(emacs) Directory Variables")

((nil
  .
  ((disproject-custom-suffixes
    .
    (["Options"
      ("-nc" "Without pinned channels" "--without-pinned-channels")]
     ["Commands"
      ("c" "Configure profile" disproject-compile
       :cmd (lambda (args)
              (interactive (list (transient-args transient-current-command)))
              (let* ((pinned? (not (transient-arg-value
                                    "--without-pinned-channels" args)))
                     (profile (if pinned? ".pinned-guix-profile"
                                ".latest-guix-profile"))
                     (guix-cmd (if pinned?
                                   "guix time-machine --channels=channels.scm --"
                                 "guix"))
                     (emacs-package (if pinned? "emacs" "emacs-next")))
                (concat "\
profile=" profile "
[ -e $profile ] && rm $profile
export GUIX_PACKAGE_PATH=''
" guix-cmd " shell --development --file=guix.scm --manifest=manifest.scm \\
	" emacs-package " \\
	--root=$profile --search-paths")))
       :buffer-id "profile")
      ("d t" "Doc: texi" disproject-compile
       :cmd "make texi"
       :buffer-id "doc")
      ("d i" "Doc: info" disproject-compile
       :cmd "make info"
       :buffer-id "doc")
      ("r" "Run Emacs" disproject-compile
       :cmd (lambda (args)
              (interactive (list (transient-args transient-current-command)))
              (let* ((pinned? (not (transient-arg-value
                                    "--without-pinned-channels" args)))
                     (profile (if pinned? ".pinned-guix-profile"
                                ".latest-guix-profile")))
                (concat "\
profile=" profile "
guix shell --pure --profile=$profile -- make run")))
       :buffer-id "run-emacs"
       :allow-multiple-buffers? t)
      ("s" "Shell with package" disproject-compile
       :cmd (lambda (args)
              (interactive (list (transient-args transient-current-command)))
              (let* ((pinned? (not (transient-arg-value
                                    "--without-pinned-channels" args)))
                     (guix-cmd (if pinned?
                                   "guix time-machine --channels=channels.scm --"
                                 "guix"))
                     (emacs-package (if pinned? "emacs" "emacs-next")))
                (concat "\
" guix-cmd " shell --pure --file=guix.scm --manifest=manifest.scm " emacs-package)))
       :buffer-id "package-emacs"
       :comint? t)
      ("t" "Run tests" disproject-compile
       :cmd (lambda (args)
              (interactive (list (transient-args transient-current-command)))
              (let* ((pinned? (not (transient-arg-value
                                    "--without-pinned-channels" args)))
                     (profile (if pinned? ".pinned-guix-profile"
                                ".latest-guix-profile")))
                (concat "\
profile=" profile "
guix shell --pure --profile=$profile -- make check")))
       :buffer-id "test-emacs")])))))
