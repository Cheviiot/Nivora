#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
helper="${repo_root}/.github/tools/lib/alt_apt_network.sh"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/nivora-alt-apt-test.XXXXXX")"
cleanup_test_root() {
    find "$test_root" -mindepth 1 -delete
    rmdir -- "$test_root"
}
trap cleanup_test_root EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_contains() {
    local file="$1" pattern="$2"
    grep -Fq -- "$pattern" "$file" || fail "missing '${pattern}' in ${file}"
}

setup_case() {
    local case_dir="$1" tag="$2" suite="$3"
    mkdir -p "${case_dir}/apt/sources.list.d" "${case_dir}/lists" \
        "${case_dir}/bin"
    cat >"${case_dir}/apt/sources.list.d/alt.list" <<EOF
# Official ALT primary
rpm [${tag}] http://ftp.altlinux.org/pub/distributions/ALTLinux ${suite}/x86_64 classic
rpm [${tag}] http://ftp.altlinux.org/pub/distributions/ALTLinux ${suite}/x86_64-i586 classic
rpm [${tag}] http://ftp.altlinux.org/pub/distributions/ALTLinux ${suite}/noarch classic
EOF
    cat >"${case_dir}/apt/sources.list.d/yandex.list" <<EOF
# Official ALT mirror
#rpm [${tag}] http://mirror.yandex.ru/altlinux ${suite}/x86_64 classic
#rpm [${tag}] http://mirror.yandex.ru/altlinux ${suite}/x86_64-i586 classic
#rpm [${tag}] http://mirror.yandex.ru/altlinux ${suite}/noarch classic
EOF
    cat >"${case_dir}/bin/timeout" <<'EOF'
#!/bin/bash
set -euo pipefail
while [[ "${1:-}" == --* ]]; do shift; done
duration="$1"
shift
printf 'timeout=%s\n' "$duration" >>"${NIVORA_ALT_APT_TIMEOUT_LOG:?}"
exec "$@"
EOF
    chmod +x "${case_dir}/bin/timeout"
    cat >"${case_dir}/bin/apt-get" <<'EOF'
#!/bin/bash
set -euo pipefail
source_list=''
args=()
while (($#)); do
    if [[ "$1" == -o ]]; then
        option="$2"
        args+=("$option")
        [[ "$option" == Dir::Etc::sourcelist=* ]] && source_list="${option#*=}"
        shift 2
    else
        args+=("$1")
        shift
    fi
done
printf '%s\n' "${args[@]}" >>"${NIVORA_ALT_APT_ARGS_LOG:?}"
cat "$source_list" >>"${NIVORA_ALT_APT_SOURCE_LOG:?}"
printf '\n---attempt---\n' >>"${NIVORA_ALT_APT_SOURCE_LOG:?}"
if [[ "${NIVORA_ALT_APT_ALWAYS_FAIL:-0}" == 1 ]]; then
    echo 'temporary mirror failure' >&2
    exit 1
fi
if grep -q 'http://ftp.altlinux.org' "$source_list"; then
    if [[ "${NIVORA_ALT_APT_GPG_WARNING:-0}" == 1 ]]; then
        echo 'W: Signature verification failed' >&2
        exit 0
    fi
    # Simulate apt-rpm's exit-zero partial-index warning. The helper must still
    # reject this attempt and try another official source.
    echo 'W: Failed to fetch index from primary mirror' >&2
    echo 'W: Some index files failed to download' >&2
    exit 0
fi
if grep -q 'http://mirror.yandex.ru/altlinux' "$source_list"; then
    echo 'Fetched signed ALT indexes from mirror'
    exit 0
fi
echo 'temporary mirror failure' >&2
exit 1
EOF
    chmod +x "${case_dir}/bin/apt-get"
}

run_update() {
    local case_dir="$1" always_fail="${2:-0}" gpg_warning="${3:-0}"
    env \
        NIVORA_ALT_APT_ROOT="${case_dir}/apt" \
        NIVORA_ALT_APT_LISTS="${case_dir}/lists" \
        NIVORA_ALT_APT_ACTIVE_SOURCE="${case_dir}/apt/sources.list.d/alt.list" \
        NIVORA_ALT_APT_GET="${case_dir}/bin/apt-get" \
        NIVORA_ALT_APT_TIMEOUT_BIN="${case_dir}/bin/timeout" \
        NIVORA_ALT_APT_TIMEOUT_LOG="${case_dir}/timeouts" \
        NIVORA_ALT_APT_ARGS_LOG="${case_dir}/args" \
        NIVORA_ALT_APT_SOURCE_LOG="${case_dir}/sources-seen" \
        NIVORA_ALT_APT_ALWAYS_FAIL="$always_fail" \
        NIVORA_ALT_APT_GPG_WARNING="$gpg_warning" \
        NIVORA_ALT_APT_ATTEMPT_TIMEOUT_SECONDS=5 \
        NIVORA_ALT_APT_TOTAL_TIMEOUT_SECONDS=20 \
        bash "$helper" update
}

run_apt_transaction() {
    local case_dir="$1"
    env \
        NIVORA_ALT_APT_ROOT="${case_dir}/apt" \
        NIVORA_ALT_APT_LISTS="${case_dir}/lists" \
        NIVORA_ALT_APT_ACTIVE_SOURCE="${case_dir}/apt/sources.list.d/alt.list" \
        NIVORA_ALT_APT_GET="${case_dir}/bin/apt-get" \
        NIVORA_ALT_APT_TIMEOUT_BIN="${case_dir}/bin/timeout" \
        NIVORA_ALT_APT_TIMEOUT_LOG="${case_dir}/timeouts" \
        NIVORA_ALT_APT_ARGS_LOG="${case_dir}/args" \
        NIVORA_ALT_APT_SOURCE_LOG="${case_dir}/sources-seen" \
        NIVORA_ALT_APT_COMMAND_TIMEOUT_SECONDS=300 \
        bash "$helper" run install -y fixture-package
}

for branch_case in 'p11|p11|p11/branch' 'sisyphus|alt|Sisyphus'; do
    IFS='|' read -r branch tag suite <<<"$branch_case"
    case_dir="${test_root}/${branch}"
    setup_case "$case_dir" "$tag" "$suite"
    if [[ "$branch" == sisyphus ]]; then
        gpg_warning=1
    else
        gpg_warning=0
    fi
    if ! run_update "$case_dir" 0 "$gpg_warning" >"${case_dir}/stdout" 2>"${case_dir}/stderr"; then
        cat "${case_dir}/stderr" >&2
        fail "${branch} did not fall back to the supplied mirror"
    fi
    active="${case_dir}/apt/sources.list.d/alt.list"
    [[ "$(grep -c '^rpm ' "$active")" == 3 ]] || fail "${branch} changed the source architecture count"
    assert_contains "$active" "rpm [${tag}] http://mirror.yandex.ru/altlinux ${suite}/x86_64 classic"
    assert_contains "$active" "rpm [${tag}] http://mirror.yandex.ru/altlinux ${suite}/x86_64-i586 classic"
    assert_contains "$active" "rpm [${tag}] http://mirror.yandex.ru/altlinux ${suite}/noarch classic"
    assert_contains "${case_dir}/sources-seen" 'http://ftp.altlinux.org'
    assert_contains "${case_dir}/sources-seen" 'http://mirror.yandex.ru/altlinux'
    primary_http_line="$(grep -n -m1 'http://ftp.altlinux.org' "${case_dir}/sources-seen" | cut -d: -f1)"
    mirror_http_line="$(grep -n -m1 'http://mirror.yandex.ru/altlinux' "${case_dir}/sources-seen" | cut -d: -f1)"
    ((primary_http_line < mirror_http_line)) ||
        fail "${branch} did not preserve primary-then-mirror ordering"
    ! grep -Fq 'https://' "${case_dir}/sources-seen" ||
        fail "${branch} attempted HTTPS before CA certificates were installed"
    assert_contains "${case_dir}/args" 'Acquire::Retries=0'
    assert_contains "${case_dir}/args" 'Acquire::http::Timeout=15'
    if [[ "$branch" == sisyphus ]]; then
        assert_contains "${case_dir}/stderr" 'selected http://mirror.yandex.ru/altlinux'
    fi
    if [[ "$branch" == p11 ]]; then
        run_apt_transaction "$case_dir" >"${case_dir}/transaction.stdout" \
            2>"${case_dir}/transaction.stderr" || {
            cat "${case_dir}/transaction.stderr" >&2
            fail 'bounded apt transaction failed after mirror selection'
        }
        assert_contains "${case_dir}/timeouts" 'timeout=300s'
        assert_contains "${case_dir}/args" 'Dir::Etc::sourceparts=-'
        assert_contains "${case_dir}/args" 'install'
    fi
    ! grep -Eiq 'trusted=yes|AllowInsecure|allow-unauthenticated' "${case_dir}/args" ||
        fail "${branch} disabled repository signature checks"
done

failure_case="${test_root}/permanent-failure"
setup_case "$failure_case" p11 p11/branch
if run_update "$failure_case" 1 >"${failure_case}/stdout" 2>"${failure_case}/stderr"; then
    fail 'permanent mirror failure unexpectedly succeeded'
fi
assert_contains "${failure_case}/stderr" 'all configured mirrors failed within 20s total'
[[ "$(grep -c '^timeout=' "${failure_case}/timeouts")" -le 4 ]] ||
    fail 'permanent mirror failure exceeded the bounded candidate count'
[[ "$(grep -c '^rpm ' "${failure_case}/apt/sources.list.d/alt.list")" == 3 ]] ||
    fail 'permanent failure replaced the original source configuration'

echo 'OK: ALT apt mirror failover, branch/architecture preservation and bounded failure'
