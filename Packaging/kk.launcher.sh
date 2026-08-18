#!@PREFIX@/bin/sh
#
# SwiftPM resolves Bundle.module against the directory holding the running
# executable, and kk's model catalog lives in the bundle beside it. A symlink
# from /usr/bin would make that lookup land in /usr/bin instead and the CLI
# would start with no providers at all, so the real binary stays next to its
# bundle in libexec and this launcher execs it by path.
#
# @PREFIX@ is substituted at package time: empty for roothide, whose package is
# relocated into the jbroot it picked this boot and whose programs resolve
# unprefixed paths inside it, and /var/jb for a rootless bootstrap, where every
# path has to be spelled out — including this script's own interpreter.
exec @PREFIX@/usr/libexec/kk/kk "$@"
