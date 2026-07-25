# Firejail profile for MAX Messenger (Nivora package)
# MAX is a proprietary Russian messenger; this profile keeps it away from
# the rest of the user's files and system, and blocks its standalone
# crash-report uploader.

include max.local
include globals.local

noblacklist ${HOME}/.config/max
noblacklist ${HOME}/.cache/max
noblacklist ${HOME}/.local/share/max

include disable-common.inc
include disable-devel.inc
include disable-exec.inc
include disable-interpreters.inc
include disable-programs.inc
include landlock-common.inc

mkdir ${HOME}/.config/max
mkdir ${HOME}/.cache/max
mkdir ${HOME}/.local/share/max
whitelist ${HOME}/.config/max
whitelist ${HOME}/.cache/max
whitelist ${HOME}/.local/share/max
include whitelist-common.inc
include whitelist-run-common.inc
include whitelist-usr-share-common.inc
include whitelist-var-common.inc

caps.drop all
netfilter
nodvd
nogroups
nonewprivs
noroot
notv
nou2f
protocol unix,inet,inet6
seccomp
restrict-namespaces

disable-mnt
private-dev
private-tmp

# Chromium/Qt-style standalone crash uploader: no messaging function, only
# phones home with crash dumps. Block it outright rather than trust a
# network-level filter.
blacklist /usr/share/max/bin/crashpad_handler
blacklist /usr/share/max/bin/max-service/bin/crashpad_handler

dbus-system none
