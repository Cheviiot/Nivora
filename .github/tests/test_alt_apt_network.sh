#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
helper="${repo_root}/.github/tools/lib/alt_apt_network.sh"
preferred_url='http://mirror.datacenter.by/pub/ALTLinux'
image_url='http://ftp.altlinux.org/pub/distributions/ALTLinux'
alternate_url='http://mirror.yandex.ru/altlinux'
catalog=("$preferred_url" "$image_url" "$alternate_url")
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

assert_mirrors() {
    local case_dir="$1"
    shift
    diff -u <(printf '%s\n' "$@") "${case_dir}/sources-seen.mirrors" ||
        fail "unexpected order or number of mirror attempts in ${case_dir##*/}"
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
if [[ "${NIVORA_ALT_APT_TEST_CASE:-}" == deadline ]]; then
    # Consume the small test budget as a real timed-out attempt would.
    sleep 1
    exit 124
fi
exec "$@"
EOF
    chmod +x "${case_dir}/bin/timeout"
    cat >"${case_dir}/bin/apt-get" <<'EOF'
#!/bin/bash
set -euo pipefail
source_list=''
args=()
is_update=0
while (($#)); do
    if [[ "$1" == -o ]]; then
        option="$2"
        args+=("$option")
        [[ "$option" == Dir::Etc::sourcelist=* ]] && source_list="${option#*=}"
        shift 2
    else
        [[ "$1" != update ]] || is_update=1
        args+=("$1")
        shift
    fi
done
printf '%s\n' "${args[@]}" >>"${NIVORA_ALT_APT_ARGS_LOG:?}"
cat "$source_list" >>"${NIVORA_ALT_APT_SOURCE_LOG:?}"
printf '\n---attempt---\n' >>"${NIVORA_ALT_APT_SOURCE_LOG:?}"
if [[ "$is_update" == 0 ]]; then
    exit "${NIVORA_ALT_APT_TRANSACTION_EXIT:-0}"
fi
mirror="$(awk '$1 == "rpm" {print $3; exit}' "$source_list")"
printf '%s\n' "$mirror" >>"${NIVORA_ALT_APT_SOURCE_LOG}.mirrors"
if [[ -n "$(find "${NIVORA_ALT_APT_LISTS:?}" -mindepth 1 -type f -print -quit)" ]]; then
    printf 'stale indexes reached apt\n' >>"${NIVORA_ALT_APT_SOURCE_LOG}.dirty"
    exit 1
fi
[[ -d "${NIVORA_ALT_APT_LISTS}/partial" ]]
printf 'old release\n' >"${NIVORA_ALT_APT_LISTS}/release"
printf 'partial index\n' >"${NIVORA_ALT_APT_LISTS}/partial/index"
if [[ -n "${NIVORA_ALT_APT_TEST_MISMATCH:-}" ]]; then
    # No generic failed-to-fetch warning: these zero-exit integrity errors
    # themselves must prevent selection of the mixed repository snapshot.
    printf 'W: %s\n' "$NIVORA_ALT_APT_TEST_MISMATCH"
    exit 0
fi
if [[ "${NIVORA_ALT_APT_TEST_CASE:-}" == recover ]]; then
    # The preferred mirror recovers on its own second request, independent
    # of the number or order of the other mirrors offered by the image.
    if [[ "$mirror" == "$NIVORA_ALT_APT_TEST_PREFERRED" ]] &&
        [[ "$(grep -Fxc -- "$mirror" "${NIVORA_ALT_APT_SOURCE_LOG}.mirrors")" == 2 ]]; then
        echo 'Fetched signed ALT indexes after synchronization'
        exit 0
    fi
    exit 1
fi
if [[ "${NIVORA_ALT_APT_ALWAYS_FAIL:-0}" == 1 ]]; then
    echo 'temporary mirror failure' >&2
    exit 1
fi
if [[ "$mirror" == "${NIVORA_ALT_APT_TEST_ACCEPT:-http://mirror.yandex.ru/altlinux}" ]]; then
    echo 'Fetched signed ALT indexes'
    exit 0
fi
if [[ "${NIVORA_ALT_APT_GPG_WARNING:-0}" == 1 ]]; then
    echo 'W: Signature verification failed' >&2
    exit 0
fi
if [[ "$mirror" == 'http://ftp.altlinux.org/pub/distributions/ALTLinux' ]]; then
    # Simulate apt-rpm's exit-zero partial-index warning. The helper must still
    # reject this attempt and try another official source.
    echo 'W: Failed to fetch index from primary mirror' >&2
    echo 'W: Some index files failed to download' >&2
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
        NIVORA_ALT_APT_TEST_PREFERRED="$preferred_url" \
        NIVORA_ALT_APT_ALWAYS_FAIL="$always_fail" \
        NIVORA_ALT_APT_GPG_WARNING="$gpg_warning" \
        NIVORA_ALT_APT_ATTEMPT_TIMEOUT_SECONDS="${NIVORA_ALT_APT_ATTEMPT_TIMEOUT_SECONDS-5}" \
        NIVORA_ALT_APT_TOTAL_TIMEOUT_SECONDS="${NIVORA_ALT_APT_TEST_TOTAL_TIMEOUT_SECONDS:-20}" \
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

# Derive the preferred mirror from the active signed distributions. Preserve
# components exactly and ignore disabled lines when building its source list.
preferred_case="${test_root}/preferred"
setup_case "$preferred_case" p11 p11/branch
active="${preferred_case}/apt/sources.list.d/alt.list"
cat >"$active" <<EOF
rpm [p11] $image_url p11/branch/x86_64 classic debuginfo
rpm [p11] $image_url p11/branch/x86_64-i586 classic
rpm [p11] $image_url p11/branch/i586 classic
rpm [p11] $image_url p11/branch/noarch classic
#rpm [p11] $image_url p11/branch/aarch64 classic
EOF
cp "$active" "${preferred_case}/original-source"
selected="${preferred_case}/apt/nivora-p11.list"
NIVORA_ALT_APT_TEST_ACCEPT="$preferred_url" run_update "$preferred_case" \
    >"${preferred_case}/stdout" 2>"${preferred_case}/stderr"
assert_mirrors "$preferred_case" "$preferred_url"
diff -u <(sed -n "/^rpm /s|$image_url|$preferred_url|p" "${preferred_case}/original-source") <(grep '^rpm ' "$selected") ||
    fail 'preferred mirror changed signed suites or components'
cmp "$active" "${preferred_case}/original-source" || fail 'selection overwrote image sources'
run_apt_transaction "$preferred_case"
assert_contains "${preferred_case}/args" "Dir::Etc::sourcelist=$selected"
if grep -Eiq 'trusted=yes|AllowInsecure|allow-unauthenticated' "${preferred_case}/args"; then
    fail 'preferred mirror disabled repository signature checks'
fi

# A signature warning from Minsk on a later update must fall back to the
# original image URL without losing it after the first selection.
NIVORA_ALT_APT_TEST_ACCEPT="$image_url" run_update "$preferred_case" 0 1 \
    >"${preferred_case}/repeat.stdout" 2>"${preferred_case}/repeat.stderr"
assert_mirrors "$preferred_case" "$preferred_url" "$preferred_url" "$image_url"
diff -u <(grep '^rpm ' "${preferred_case}/original-source") <(grep '^rpm ' "$selected") || fail 'could not return to the image mirror'
cmp "$active" "${preferred_case}/original-source" || fail 'fallback overwrote image sources'

# A mirror without aarch64 or the requested branch/key must never receive a
# synthesized subset of the active configuration.
for reason in architecture signature suite; do
    untouched_case="${test_root}/original-${reason}"
    setup_case "$untouched_case" p11 p11/branch
    active="${untouched_case}/apt/sources.list.d/alt.list"
    case "$reason" in
    architecture) echo "rpm [p11] $image_url p11/branch/aarch64 classic" >>"$active" ;;
    signature)    echo "rpm [p10] $image_url p11/branch/noarch classic" >>"$active" ;;
    suite)        echo "rpm [p11] $image_url p10/branch/noarch classic" >>"$active" ;;
    esac
    grep '^rpm ' "$active" >"${untouched_case}/original-rpm-lines"
    NIVORA_ALT_APT_TEST_ACCEPT="$image_url" run_update "$untouched_case" \
        >"${untouched_case}/stdout" 2>"${untouched_case}/stderr"
    assert_mirrors "$untouched_case" "$image_url"
    diff -u "${untouched_case}/original-rpm-lines" <(grep '^rpm ' "${untouched_case}/apt/nivora-p11.list") ||
        fail "unsupported ${reason} changed the original distributions"
done

budget_case="${test_root}/mirror-budgets"
setup_case "$budget_case" p11 p11/branch
NIVORA_ALT_APT_ATTEMPT_TIMEOUT_SECONDS='' NIVORA_ALT_APT_TEST_TOTAL_TIMEOUT_SECONDS=210 \
    run_update "$budget_case" >"${budget_case}/stdout" 2>"${budget_case}/stderr"
diff -u <(printf 'timeout=%ss\n' 60 30 30) "${budget_case}/timeouts"

for failure_mode in download signature; do
    case_dir="${test_root}/${failure_mode}"
    setup_case "$case_dir" p11 p11/branch
    if [[ "$failure_mode" == signature ]]; then
        gpg_warning=1
    else
        gpg_warning=0
    fi
    if ! run_update "$case_dir" 0 "$gpg_warning" >"${case_dir}/stdout" 2>"${case_dir}/stderr"; then
        cat "${case_dir}/stderr" >&2
        fail "${failure_mode}: p11 did not fall back to the supplied mirror"
    fi
    selected="${case_dir}/apt/nivora-p11.list"
    [[ "$(grep -c '^rpm ' "$selected")" == 3 ]] || fail "${failure_mode}: changed the source architecture count"
    assert_contains "$selected" 'rpm [p11] http://mirror.yandex.ru/altlinux p11/branch/x86_64 classic'
    assert_contains "$selected" 'rpm [p11] http://mirror.yandex.ru/altlinux p11/branch/x86_64-i586 classic'
    assert_contains "$selected" 'rpm [p11] http://mirror.yandex.ru/altlinux p11/branch/noarch classic'
    assert_mirrors "$case_dir" "${catalog[@]}"
    ! grep -Fq 'https://' "${case_dir}/sources-seen" ||
        fail "${failure_mode}: attempted HTTPS before CA certificates were installed"
    assert_contains "${case_dir}/args" 'Acquire::Retries=0'
    assert_contains "${case_dir}/args" 'Acquire::http::Timeout=15'
    assert_contains "${case_dir}/stderr" 'selected http://mirror.yandex.ru/altlinux'
    if [[ "$failure_mode" == download ]]; then
        run_apt_transaction "$case_dir" >"${case_dir}/transaction.stdout" \
            2>"${case_dir}/transaction.stderr" || {
            cat "${case_dir}/transaction.stderr" >&2
            fail 'bounded apt transaction failed after mirror selection'
        }
        assert_contains "${case_dir}/timeouts" 'timeout=300s'
        assert_contains "${case_dir}/args" 'Dir::Etc::sourceparts=-'
        assert_contains "${case_dir}/args" 'Acquire::Retries=2'
        assert_contains "${case_dir}/args" 'install'
    fi
    ! grep -Eiq 'trusted=yes|AllowInsecure|allow-unauthenticated' "${case_dir}/args" ||
        fail "${failure_mode}: disabled repository signature checks"
done

# Download retry policy is independent from index retries and stays within a
# single apt-get transaction and its original 300-second deadline.
for command_retries in 0 4; do
    transaction_case="${test_root}/transaction-retries-${command_retries}"
    setup_case "$transaction_case" p11 p11/branch
    NIVORA_ALT_APT_RETRIES=7 NIVORA_ALT_APT_COMMAND_RETRIES="$command_retries" \
        run_apt_transaction "$transaction_case" \
        >"${transaction_case}/stdout" 2>"${transaction_case}/stderr"
    assert_contains "${transaction_case}/args" "Dir::Etc::sourcelist=${transaction_case}/apt/sources.list.d/alt.list"
    [[ "$(grep '^Acquire::Retries=' "${transaction_case}/args")" == "Acquire::Retries=${command_retries}" ]] ||
        fail 'transaction retry policy inherited the index setting'
    [[ "$(cat "${transaction_case}/timeouts")" == timeout=300s ]] ||
        fail 'transaction retries reset or changed the command deadline'
done

# A nonzero apt-get result may already include a failed RPM scriptlet. The
# helper must preserve its exit status and must not repeat the transaction.
transaction_failure="${test_root}/transaction-failure"
setup_case "$transaction_failure" p11 p11/branch
status=0
NIVORA_ALT_APT_TRANSACTION_EXIT=100 run_apt_transaction "$transaction_failure" \
    >"${transaction_failure}/stdout" 2>"${transaction_failure}/stderr" || status=$?
[[ "$status" == 100 ]] || fail 'failed transaction exit status was not preserved'
[[ "$(grep -c '^install$' "${transaction_failure}/args")" == 1 ]] ||
    fail 'failed apt transaction was repeated'
[[ "$(cat "${transaction_failure}/timeouts")" == timeout=300s ]] ||
    fail 'failed apt transaction received another timeout budget'
assert_contains "${transaction_failure}/args" 'Acquire::Retries=2'

for invalid_retries in -1 invalid 1.5; do
    invalid_case="${test_root}/invalid-command-retries-${invalid_retries}"
    setup_case "$invalid_case" p11 p11/branch
    if NIVORA_ALT_APT_COMMAND_RETRIES="$invalid_retries" \
        run_apt_transaction "$invalid_case" \
        >"${invalid_case}/stdout" 2>"${invalid_case}/stderr"; then
        fail 'invalid transaction retry setting was accepted'
    fi
    assert_contains "${invalid_case}/stderr" 'command_retries must be a non-negative integer'
    [[ ! -e "${invalid_case}/args" && ! -e "${invalid_case}/timeouts" ]] ||
        fail 'invalid transaction retry setting reached apt-get'
done

# All candidates fail initially. The second pass starts with the preferred
# mirror again after clearing every complete and partial index.
recovery_case="${test_root}/second-pass-recovery"
setup_case "$recovery_case" p11 p11/branch
printf 'pre-existing index\n' >"${recovery_case}/lists/old-index"
if ! NIVORA_ALT_APT_TEST_CASE=recover run_update "$recovery_case" \
    >"${recovery_case}/stdout" 2>"${recovery_case}/stderr"; then
    cat "${recovery_case}/stderr" >&2
    fail 'temporary failure of all mirrors did not recover on the second pass'
fi
assert_mirrors "$recovery_case" "${catalog[@]}" "$preferred_url"
assert_contains "${recovery_case}/stderr" "selected $preferred_url"
[[ ! -e "${recovery_case}/sources-seen.dirty" ]] ||
    fail 'recovery reused complete or partial indexes from a previous attempt'

failure_case="${test_root}/permanent-failure"
setup_case "$failure_case" p11 p11/branch
# Duplicate configured URLs must not multiply attempts within either pass.
cp "${failure_case}/apt/sources.list.d/yandex.list" \
    "${failure_case}/apt/sources.list.d/duplicate.list"
# The image can already list the preferred mirror among its disabled choices.
sed "s|$alternate_url|$preferred_url/|g" "${failure_case}/apt/sources.list.d/yandex.list" \
    >"${failure_case}/apt/sources.list.d/preferred.list"
cp "${failure_case}/apt/sources.list.d/alt.list" "${failure_case}/original-source"
if run_update "$failure_case" 1 >"${failure_case}/stdout" 2>"${failure_case}/stderr"; then
    fail 'permanent mirror failure unexpectedly succeeded'
fi
assert_contains "${failure_case}/stderr" 'all configured mirrors failed within 20s total'
assert_mirrors "$failure_case" "${catalog[@]}" "${catalog[@]}"
[[ ! -e "${failure_case}/apt/nivora-p11.list" ]] || fail 'permanent failure published an unverified mirror'
cmp -s "${failure_case}/original-source" "${failure_case}/apt/sources.list.d/alt.list" ||
    fail 'permanent failure replaced the original source configuration'
[[ -z "$(find "${failure_case}/lists" -mindepth 1 -type f -print -quit)" ]] ||
    fail 'permanent failure left mixed indexes behind'

for mismatch in 'Checksum mismatch' 'Hash mismatch' 'Hash Sum mismatch' 'Size mismatch'; do
    mismatch_case="${test_root}/${mismatch// /-}"
    setup_case "$mismatch_case" p11 p11/branch
    if NIVORA_ALT_APT_TEST_MISMATCH="$mismatch" run_update "$mismatch_case" \
        >"${mismatch_case}/stdout" 2>"${mismatch_case}/stderr"; then
        fail "zero-exit ${mismatch} was accepted as a verified repository"
    fi
    assert_mirrors "$mismatch_case" "${catalog[@]}" "${catalog[@]}"
    ! grep -Fq 'ALT apt: selected' "${mismatch_case}/stderr" ||
        fail "${mismatch}: selected inconsistent indexes"
    [[ ! -e "${mismatch_case}/sources-seen.dirty" ]] ||
        fail "${mismatch}: carried mixed indexes into a retry"
done

# The total budget applies across all mirrors and both passes. A consumed
# one-second budget clips the first attempt and prevents any further attempt.
deadline_case="${test_root}/deadline"
setup_case "$deadline_case" p11 p11/branch
if NIVORA_ALT_APT_TEST_CASE=deadline NIVORA_ALT_APT_TEST_TOTAL_TIMEOUT_SECONDS=1 \
    run_update "$deadline_case" >"${deadline_case}/stdout" 2>"${deadline_case}/stderr"; then
    fail 'an exhausted total deadline unexpectedly succeeded'
fi
[[ "$(cat "${deadline_case}/timeouts")" == 'timeout=1s' ]] ||
    fail 'an exhausted deadline allowed another mirror or reset for a second pass'
assert_contains "${deadline_case}/stderr" 'all configured mirrors failed within 1s total (1 attempts)'

if NIVORA_ALT_APT_COMMAND_TIMEOUT_SECONDS=0 bash "$helper" run install fixture-package \
    >"${test_root}/zero-timeout.stdout" 2>"${test_root}/zero-timeout.stderr"; then
    fail 'zero transaction timeout unexpectedly disabled the deadline'
fi
assert_contains "${test_root}/zero-timeout.stderr" 'timeouts must be positive'

echo 'OK: ALT p11 prefers a compatible signed mirror and bounds retries without repeating RPM transactions'
