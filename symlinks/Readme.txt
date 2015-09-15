OPAM Cygwin Symlink Experiments

CYGWIN can be set winsymlinks:native or winsymlinks:nativestrict

There are two problems:
a) Because Windows differentiates SYMLINK and SYMLINKD, symlinks created with an invalid target cause problems. nativestrict will display an error and native will fallback to system files (big problem when un-tarring - tar expects ln to work even if the target is extracted later)
b) The Cygwin Setup program ignores the variable

There are two further problems to do with Cygwin executables being run outside of bash:
c) Symlinks for programs must point to a .exe and the symlink name must end in .exe itself
d) Scripts can't be invoked directly

This directory contains three experiments solving all four of these problems:

convert-symlinks.sh - takes a root PATH as a parameter and scans for symbolic links. It converts them to native symlinks if their target exists and can also correct symlinks whose target type has changed (i.e. a SYMLINKD which now points to a file and vice versa). Ensures target refers to .exe if necessary and re-creates links with .exe in the symlink name.

wrap-scripts.sh - takes a root PATH as a parameter and scans for scripts by looking for the "#!" header (assumes all files are executable). For each of these scripts, it looks to see if an equivalent .cmd file exists and if not it creates it - this script is responsible for invoking bash on the command using bash -c.

symlink.c - this sample tests two OPAM functions: determining if the current user can create native symbolic links and providing functions to grant the privilege which is tested by toggling the SeCreateSymbolicLinkPrivilege for the Users group on the local computer. Note that elevation is required or the second part will fail. The toggling provides the same functionality which can be achieved using the User Rights Assignment section of Local Policies in secpol.msc.

Integration notes
=================
symlink.c expects #define UNICODE. This seems like a good idea anyway - rebase the C stubs to be Unicode by default.

wrap-scripts.sh /bin and convert-symlinks.sh / should be run after any Cygwin change (so first setup or installing a package). Additionally, convert-symlinks.sh should be executed immediately after an untar operation. The default CYGWIN should execute under winsymlinks:native (which can be achieved, as shown in convert-symlinks.sh, by running CYGWIN=$CYGWIN winsymlinks:native) to deal with dangling symlinks. wrap-scripts.sh should also be invoked on the switch bin directory after any action which may have installed programs - i.e. at the end of a transaction.

OPAM should always check if native symlinks are supported and display a warning if it detects that they aren't (we'll have an environment variable / configuration option which can suppress this). There should also be an environment variable/config option which allows to bootstrap itself using runas - i.e. allow an administrator to nominate an equivalent account to use runas for. runas should be invoked using /savecred (documentation warning that we use this)

Note on passwords: we could use LogonUser and CreateProcessAsUser to permit opam to spawn itself with a plaintext password. runas doesn't support /savecred on Starter/Home editions of Windows XP, Windows 7 and Windows Vista (these editions can be detected by looking for VER_SUITE_PERSONAL in GetVersionEx). It appears to be the case that it is supported on all editions of Windows 8 onwards. However, if the user is running a home edition of Windows, then they can't possibly be attached to a domain - which means that they must be able to run elevated or grant SeCreateSymbolicLinkPrivilege to a user and come up with some alternative.

Home editions of Windows do not have secpol.msi. An alternative is to point users to polsedit (http://www.southsoftware.com/) but because of this, we'll add the following opam commands:

opam windows symlinks show -> will display all principals who have SeCreateSymbolicLinkPrivilege
opam windows symlinks grant/deny principal -> will edit the setting

Might want to pull this OCaml too: http://caml.inria.fr/mantis/view.php?id=6120
