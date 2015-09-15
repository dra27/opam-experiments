Cygwin repository downloader

make test.exe will build a program which will create (or erase) cygrepo in the current directory and place the latest setup-x86.exe installer along with a complete repository filtered according to Test.ml downloaded from a random UK-based mirror

The intention is that this will form the basis of the opam cygwin command:

opam cygwin init --site={mirror} --only-site --arch=x86|x64 [default = x86]
	-> downloads Cygwin'. If --only-site specified, --site must be given.
	-> if --only-site not given, download mirrors.lst and save it to .opam/cygrepo
	-> if --only-site is given, write --site to .opam/cygrepo
	-> if --site was not given, randomly select a mirror
	-> download setup.ini, parse and limit it and write for the required arch to ./opam/cygrepo/escaped-url/arch/setup.ini

CygRepostory.download_repository includes a lot of machinery for downloading a list of files (with sizes and checksums) using a global set of mirrors
  -> this functionality may be useful elsewhere; if OPAM doesn't already do so, it would be good to hoist all internet activity (i.e. download tarballs and then install)
