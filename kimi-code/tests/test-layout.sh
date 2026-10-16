#!/bin/bash
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
staplerfile="${package_dir}/Staplerfile"

# The recipe must contain this literal shell code.
# shellcheck disable=SC2016
grep -Fq '${pkgdir}/opt/Kimi Code' "$staplerfile"
# shellcheck disable=SC2016
grep -Fq "ln -sfn '/opt/Kimi Code/kimi-code'" "$staplerfile"
grep -Fq 'install-desktop' "$staplerfile"
grep -Fq 'appstream_app_id='"'"'com.kimi.code.desktop'"'"'' "$staplerfile"
grep -Fq 'provides=()' "$staplerfile"
grep -Fq 'replaces=('"'"'kimi-code'"'"')' "$staplerfile"
grep -Fq 'conflicts=()' "$staplerfile"
grep -Fq '/etc/apparmor.d/kimi-code' "$staplerfile"
# The AppArmor profile must keep granting user namespaces to the real binary.
grep -Fq '"/opt/Kimi Code/kimi-code"' "$staplerfile"
# These patterns intentionally contain literal recipe variables.
# shellcheck disable=SC2016
source_pattern='KimiCode-linux-amd64.deb?nivora=${source_fingerprint_amd64}'
grep -Fq "$source_pattern" "$staplerfile"
if grep -Fq '/usr/lib/kimi-code' "$staplerfile"; then
    exit 1
fi
if grep -Fq 'postupgrade' "$staplerfile"; then
    # Stapler v0.1.1 ignores postupgrade on RPM/DEB; %post covers upgrades.
    exit 1
fi
