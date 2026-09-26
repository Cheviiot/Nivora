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

# Nivora used to assign the Tailscale operator here. It cannot work: the
# operator is a per-profile preference, a freshly installed node has no
# profile yet, and `tailscale login` creates one — which drops the setting
# again. Verified against tailscaled's own log: EditPrefs sets
# OperatorUser, the next PUT /localapi/v0/profiles/ clears it. The operator
# has to be assigned after the first login, so the package points at the
# right order instead of silently doing something that gets undone.
if [[ "$transaction_count" -le 1 ]]; then
    cat >&2 <<'HINT'

Tailscale установлен, служба tailscaled запущена.

Первый вход выполняется от root, и только потом назначается оператор —
иначе назначение будет стёрто при создании профиля:

    sudo tailscale up
    sudo tailscale set --operator=$USER

После этого команда tailscale работает без sudo.
HINT
fi
