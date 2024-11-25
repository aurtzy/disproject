;;; Directory Local Variables         -*- no-byte-compile: t; -*-
;;; For more information see (info "(emacs) Directory Variables")

((nil
  .
  ((disproject-custom-suffixes
    .
    (("t c" "Time-machine: Compile to Guix profile"
      :command-type run
      :command "\
profile=.time-machine-guix-profile
[ -e $profile ] && rm $profile
guix time-machine --channels=channels.scm -- \\
	shell emacs --manifest=manifest.scm --file=guix.scm --root=$profile \\
	--search-paths"
      :identifier "time-machine-profile")
     ("t r" "Time-machine: Run Emacs"
      :command-type run
      :command "\
guix shell --pure --profile=.time-machine-guix-profile -- \\
	emacs --no-init-file --eval \"(require 'disproject)\""
      :identifier "time-machine-profile")
     ("l c" "Latest: Compile to Guix profile"
      :command-type run
      :command "\
profile=.latest-guix-profile
[ -e $profile ] && rm $profile
guix shell emacs-next --manifest=manifest.scm --file=guix.scm --root=$profile \\
	--search-paths"
      :identifier "latest-profile")
     ("l r" "Latest: Run Emacs"
      :command-type run
      :command "\
guix shell --pure --profile=.latest-guix-profile -- \\
	emacs --no-init-file --eval \"(require 'disproject)\""
      :identifier "latest-profile"))))))
