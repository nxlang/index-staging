#!/bin/sh
# Runs a command with no network (nxpkg spec 5.10 rule 8, 6.31 rule 6): in an empty
# network namespace, where only a loopback that is down exists.
#
# Unprivileged when the kernel allows it (a user namespace mapping this user to root);
# else, as on GitHub's Ubuntu runners, which restrict unprivileged user namespaces,
# through sudo, then back to this user with setpriv. The environment the command needs
# is passed on explicitly: sudo resets it.
set -eu
if unshare --user --map-root-user --net true 2>/dev/null; then
    exec unshare --user --map-root-user --net -- "$@"
fi
uid="$(id -u)"
gid="$(id -g)"
exec sudo unshare --net -- setpriv --reuid="$uid" --regid="$gid" --init-groups -- \
    env PATH="$PATH" HOME="$HOME" NEXUS_STD_BIN="${NEXUS_STD_BIN:-}" NEXUS_STD_LIB="${NEXUS_STD_LIB:-}" "$@"
