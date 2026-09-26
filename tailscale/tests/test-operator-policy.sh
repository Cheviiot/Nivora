#!/bin/bash
# The operator must not be assigned from the install hook.
#
# OperatorUser is a per-profile preference. A freshly installed node has no
# profile, `tailscale login` creates one, and creating it clears the operator
# again — verified offline against tailscaled's own log:
#
#   EditPrefs: MaskedPrefs{OperatorUser="..."}     the setting lands
#   localapi: [PUT] /localapi/v0/profiles/         the profile is created
#                                                  and the setting is gone
#
# So anything the hook sets is erased by the user's first login, and the user
# is left with "Access denied" from a package that claimed to have arranged
# access. The package points at the right order instead.
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
postinstall="${package_dir}/postinstall.sh"
readme="${package_dir}/README.md"

# Look at what the hook actually runs: drop comments and the heredoc that
# only prints the hint, so the literal inside it is not mistaken for a call.
executable_lines() {
    awk '
        /<<.?HINT.?$/ { inside = 1; next }
        inside && /^HINT$/ { inside = 0; next }
        inside { next }
        /^[[:space:]]*#/ { next }
        { print }
    ' "$1"
}

if executable_lines "$postinstall" |
    grep -Eq 'tailscale[[:space:]]+set[[:space:]].*--operator'; then
    echo 'postinstall назначает оператора: это стирается первым же tailscale login' >&2
    exit 1
fi

# The hook must still tell the user the order that does work.
grep -Fq 'sudo tailscale up' "$postinstall"
# The hint is a literal the user retypes; $USER must not expand here.
# shellcheck disable=SC2016
grep -Fq 'sudo tailscale set --operator=$USER' "$postinstall"

# And the documentation must not promise the automatic assignment again.
if grep -q 'автоматически назначается' "$readme"; then
    echo 'README обещает автоматическое назначение оператора' >&2
    exit 1
fi
grep -Fq 'sudo tailscale up' "$readme"

# Upgrades must not re-enable a unit the user switched off.
grep -Fq 'try-restart' "$postinstall"

echo 'OK: оператор не назначается из хука, порядок входа задокументирован'
