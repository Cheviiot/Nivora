#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d)"

cleanup() {
    find "$test_root" -mindepth 1 -delete
    rmdir "$test_root"
}
trap cleanup EXIT

install -d "${test_root}/bin" "${test_root}/repo/example"
cat >"${test_root}/bin/stplr-spec" <<'EOF'
#!/bin/bash
set -euo pipefail
[[ "$1" == get-field && "$2" == --path ]]
field="$4"
[[ "$field" != "${TEST_FAIL_FIELD:-}" ]] || exit 42
case "$field" in
compatible_with) printf '%s\n' "${TEST_COMPATIBLE:-}" ;;
incompatible_with) printf '%s\n' "${TEST_INCOMPATIBLE:-}" ;;
*) exit 2 ;;
esac
EOF
chmod 0755 "${test_root}/bin/stplr-spec"
export PATH="${test_root}/bin:${PATH}"

# shellcheck source=.github/tools/lib/package_compatibility.sh
source "${repo_root}/.github/tools/lib/package_compatibility.sh"
cd "${test_root}/repo"

: >example/Staplerfile
nivora_package_supports_distro example ubuntu

printf "compatible_with=('altlinux')\n" >example/Staplerfile
TEST_COMPATIBLE=altlinux nivora_package_supports_distro example altlinux
if TEST_COMPATIBLE=altlinux nivora_package_supports_distro example ubuntu; then
    echo 'altlinux-only package unexpectedly supports Ubuntu' >&2
    exit 1
else
    [[ "$?" -eq 1 ]]
fi

if TEST_FAIL_FIELD=compatible_with \
    nivora_package_supports_distro example ubuntu 2>"${test_root}/error.log"; then
    echo 'declared compatibility parser failure was accepted' >&2
    exit 1
else
    [[ "$?" -eq 2 ]]
fi
grep -Fq 'cannot read declared compatible_with' "${test_root}/error.log"

printf "incompatible_with=('alpine')\n" >example/Staplerfile
TEST_INCOMPATIBLE=alpine nivora_package_supports_distro example ubuntu
if TEST_INCOMPATIBLE=alpine nivora_package_supports_distro example alpine; then
    echo 'explicitly incompatible distro was accepted' >&2
    exit 1
else
    [[ "$?" -eq 1 ]]
fi

echo 'OK: package compatibility selection is fail-closed'
