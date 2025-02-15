;;; Directory Local Variables         -*- no-byte-compile: t; -*-
;;; For more information see (info "(emacs) Directory Variables")

((nil
  .
  ((disproject-custom-suffixes
    .
    (("t c" "Time-machine: Compile to Guix profile" disproject-compile
      :cmd "\
profile=.time-machine-guix-profile
[ -e $profile ] && rm $profile
guix time-machine --channels=channels.scm -- \\
	shell --development --file=guix.scm --file=guix.scm \\
	--manifest=manifest.scm emacs \\
	--root=$profile --search-paths"
      :buffer-id "time-machine-profile")
     ("t r" "Time-machine: Run Emacs" disproject-compile
      :cmd "\
guix shell --pure --profile=.time-machine-guix-profile -- \\
	emacs --no-init-file --eval \"(require 'disproject)\""
      :buffer-id "time-machine-profile")
     ("l c" "Latest: Compile to Guix profile" disproject-compile
      :cmd "\
profile=.latest-guix-profile
[ -e $profile ] && rm $profile
guix shell --development --file=guix.scm --file=guix.scm \\
	--manifest=manifest.scm emacs-next \\
	--root=$profile --search-paths"
      :buffer-id "latest-profile")
     ("l r" "Latest: Run Emacs" disproject-compile
      :cmd "\
guix shell --pure --profile=.latest-guix-profile -- \\
	emacs --no-init-file --eval \"(require 'disproject)\""
      :buffer-id "latest-profile"))))))
