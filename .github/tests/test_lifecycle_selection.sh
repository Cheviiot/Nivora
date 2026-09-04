#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
lifecycle="${script_dir}/../tools/test_package_lifecycle.sh"

assert_rejected() {
    local selection="$1"
    local expected="$2"
    local output status

    set +e
    output="$(NIVORA_LIFECYCLE_PACKAGES="$selection" bash "$lifecycle" 2>&1)"
    status=$?
    set -e
    [[ "$status" -eq 2 ]]
    grep -Fq "$expected" <<<"$output"
}

assert_rejected 'missing-package' 'Неизвестный lifecycle package: missing-package'
assert_rejected 'github-desktop,github-desktop' \
    'Повторяющийся lifecycle package: github-desktop'
assert_rejected 'GitHub Desktop' \
    'Некорректный package ID в NIVORA_LIFECYCLE_PACKAGES: GitHub Desktop'

plan="$(
    NIVORA_LIFECYCLE_PACKAGES=distroshelf \
        NIVORA_LIFECYCLE_PLAN_ONLY=1 \
        bash "$lifecycle"
)"
grep -Fxq 'DEB:' <<<"$plan"
grep -Fxq 'RPM:distroshelf' <<<"$plan"

echo 'OK: lifecycle package selection is fail-closed'
