#!/bin/bash
# The PAM stack is the one file of the payload that Nivora replaces, and the
# reason is not cosmetic: upstream ships Debian's common-auth stack, ALT has no
# such service files, and pam_start would fail — logging into SubnetDesk with a
# system account would be impossible. This test keeps the upstream file from
# quietly coming back with the next version bump.
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
recipe="${package_dir}/Staplerfile"
pam_file="${package_dir}/subnetdesk.pam"

fail() {
    echo "test-pam-stack: $*" >&2
    exit 1
}

[[ -f "$pam_file" ]] || fail 'subnetdesk.pam отсутствует'

# Only executable directives count; the file explains the Debian stack in a
# comment, and the comment must stay allowed.
directives="$(grep -vE '^[[:space:]]*(#|$)' "$pam_file" || true)"
[[ -n "$directives" ]] || fail 'в subnetdesk.pam нет ни одной директивы'

if grep -qF 'common-' <<<"$directives"; then
    fail 'директива ссылается на common-* — такого сервиса на ALT нет'
fi

for phase in auth account password session; do
    grep -qE "^${phase}[[:space:]]+include[[:space:]]+system-auth\$" \
        <<<"$directives" ||
        fail "нет include system-auth для фазы ${phase}"
done

# shellcheck disable=SC2016  # the literal recipe line is matched, not expanded
grep -qF 'install -Dm644 "${srcdir}/subnetdesk.pam" "${pkgdir}/etc/pam.d/subnetdesk"' \
    "$recipe" ||
    fail 'рецепт не устанавливает свой subnetdesk.pam в /etc/pam.d'

grep -qF "'/etc/pam.d/subnetdesk'" "$recipe" ||
    fail 'PAM-файл не объявлен конфигурационным в backup'

if grep -qF 'extracted/etc/pam.d' "$recipe"; then
    fail 'рецепт снова берёт PAM-файл из payload upstream'
fi

echo 'OK: PAM-стек SubnetDesk собран под ALT (system-auth), upstream не протекает'
