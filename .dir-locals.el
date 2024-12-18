;;; Directory Local Variables         -*- no-byte-compile: t; -*-
;;; For more information see (info "(emacs) Directory Variables")

((nil
  .
  ((disproject-custom-suffixes
    .
    (("t c" "Time-machine: Compile to Guix profile"
      (lambda () (interactive)
        (let ((command "\
profile=.time-machine-guix-profile
[ -e $profile ] && rm $profile
guix time-machine --channels=channels.scm -- \\
	shell --development --file=guix.scm --file=guix.scm \\
	--manifest=manifest.scm emacs \\
	--root=$profile --search-paths"))
          (if current-prefix-arg
              (read-shell-command "Command: " command)
            command)))
      :class disproject-shell-command-suffix
      :buffer-id "time-machine-profile")
     ("t r" "Time-machine: Run Emacs"
      (lambda () (interactive)
        (let ((command "\
guix shell --pure --profile=.time-machine-guix-profile -- \\
	emacs --no-init-file --eval \"(require 'disproject)\""))
          (if current-prefix-arg
              (read-shell-command "Command: " command)
            command)))
      :class disproject-shell-command-suffix
      :buffer-id "time-machine-profile")
     ("l c" "Latest: Compile to Guix profile"
      (lambda () (interactive)
        (let ((command "\
profile=.latest-guix-profile
[ -e $profile ] && rm $profile
guix shell --development --file=guix.scm --file=guix.scm \\
	--manifest=manifest.scm emacs-next \\
	--root=$profile --search-paths"))
          (if current-prefix-arg
              (read-shell-command "Command: " command)
            command)))
      :class disproject-shell-command-suffix
      :buffer-id "latest-profile")
     ("l r" "Latest: Run Emacs"
      (lambda () (interactive)
        (let ((command "\
guix shell --pure --profile=.latest-guix-profile -- \\
	emacs --no-init-file --eval \"(require 'disproject)\""))
          (if current-prefix-arg
              (read-shell-command "Command: " command)
            command)))
      :class disproject-shell-command-suffix
      :buffer-id "latest-profile"))))))
