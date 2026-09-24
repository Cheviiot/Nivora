#!/bin/bash

set -euo pipefail

# Stapler maps this script to RPM %post, which runs on a first install and on
# every upgrade alike. RPM passes the resulting number of installed instances:
# 1 on a first install, 2 or more on an upgrade.
transaction_count="${1:-1}"

optional_step() {
    local label=$1
    shift
    if ! "$@"; then
        echo "Предупреждение: ${label}." >&2
    fi
}

if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
    optional_step 'не удалось перечитать unit-файлы' systemctl daemon-reload
    if [[ "$transaction_count" -le 1 ]]; then
        optional_step 'не удалось включить tailscaled.service' \
            systemctl enable --now tailscaled.service
    else
        # Never re-enable a unit the user deliberately switched off. The
        # running daemon still holds the previous binary, so an active service
        # is restarted onto the new one and an inactive one is left alone.
        optional_step 'не удалось перезапустить tailscaled.service' \
            systemctl try-restart tailscaled.service
    fi
fi

# The operator is a user-visible choice. Set it once, while the package is
# genuinely new, so a later upgrade cannot silently take it back from whoever
# the user assigned it to.
if [[ "$transaction_count" -gt 1 ]]; then
    exit 0
fi

REAL_USER="${SUDO_USER:-}"
if [[ -z "$REAL_USER" ]] && [[ -n "${PKEXEC_UID:-}" ]]; then
    REAL_USER=$(id -nu "$PKEXEC_UID")
fi
if [[ -z "$REAL_USER" ]] && command -v logname >/dev/null 2>&1; then
    REAL_USER=$(logname 2>/dev/null) || REAL_USER=""
fi

if [[ -n "$REAL_USER" ]] && [[ "$REAL_USER" != "root" ]] &&
    id "$REAL_USER" >/dev/null 2>&1 &&
    command -v tailscale >/dev/null 2>&1; then
    for _ in 1 2 3 4 5; do
        tailscale status --json >/dev/null 2>&1 && break
        sleep 1
    done
    optional_step "не удалось назначить Tailscale operator для ${REAL_USER}" \
        tailscale set --operator="$REAL_USER"
fi
