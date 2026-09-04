#!/bin/bash
set -euo pipefail

case "${1:-}" in
1 | upgrade)
    # During an upgrade the new package's postinstall has already reloaded the
    # profile before the old RPM %preun/DEB prerm runs. Do not unload it again.
    exit 0
    ;;
esac

profile=/etc/apparmor.d/chatgpt
disabled=/etc/apparmor.d/disable/chatgpt

if [[ -L "$disabled" && "$(readlink "$disabled")" == '.././chatgpt' ]]; then
    rm -f "$disabled"
fi
if [[ -f "$profile" && -f /etc/apparmor.d/abi/4.0 ]] &&
    command -v aa-enabled >/dev/null 2>&1 &&
    command -v apparmor_parser >/dev/null 2>&1 &&
    aa-enabled --quiet; then
    apparmor_parser -R "$profile" || true
fi
