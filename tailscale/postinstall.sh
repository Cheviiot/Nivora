#!/bin/bash

set -euo pipefail

if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
    systemctl daemon-reload
    systemctl enable --now tailscaled.service
fi

REAL_USER="${SUDO_USER:-}"
if [[ -z "$REAL_USER" ]] && [[ -n "${PKEXEC_UID:-}" ]]; then
    REAL_USER=$(id -nu "$PKEXEC_UID")
fi
if [[ -z "$REAL_USER" ]] && command -v logname &>/dev/null; then
    REAL_USER=$(logname 2>/dev/null) || REAL_USER=""
fi

if [[ -n "$REAL_USER" ]] && [[ "$REAL_USER" != "root" ]] && id "$REAL_USER" &>/dev/null && command -v tailscale &>/dev/null; then
    for _ in 1 2 3 4 5; do
        tailscale status --json &>/dev/null && break
        sleep 1
    done
    if ! tailscale set --operator="$REAL_USER"; then
        echo "Предупреждение: не удалось назначить Tailscale operator для $REAL_USER." >&2
    fi
fi
