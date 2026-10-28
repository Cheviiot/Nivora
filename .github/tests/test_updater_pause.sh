#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/nivora-pause-test.XXXXXX")"
cleanup() {
    find "$fixture" -mindepth 1 -delete
    rmdir "$fixture"
}
trap cleanup EXIT

install -d "$fixture/bin"
cat >"$fixture/bin/gh" <<'MOCK_GH'
#!/bin/bash
set -euo pipefail

if [[ "${MOCK_GH_FAIL:-false}" == true ]]; then
    echo 'mock GitHub API failure' >&2
    exit 13
fi
if [[ "${1:-}" == api && "${2:-}" == --paginate ]]; then
    printf '%s\n' "${MOCK_GH_ISSUES_JSON:-[]}"
    exit 0
fi
if [[ "${1:-}" == api ]]; then
    if [[ "${2:-}" != --method ]]; then
        echo "unexpected gh api arguments: $*" >&2
        exit 2
    fi
    method="$3"
    endpoint="$4"
    state=''
    body=''
    shift 4
    while (($#)); do
        if [[ "$1" == -f ]]; then
            case "$2" in
                state=*) state="${2#state=}" ;;
                body=*) body="${2#body=}" ;;
            esac
            shift 2
        else
            shift
        fi
    done
    printf '%s %s %s\n' "$method" "$endpoint" "$state" \
        >>"${MOCK_GH_MUTATIONS:?}"
    printf '%s\n' "$body" >>"${MOCK_GH_BODIES:?}"
    exit 0
fi
echo "unexpected gh command: $*" >&2
exit 2
MOCK_GH
chmod 0755 "$fixture/bin/gh"

sha='0123456789abcdef0123456789abcdef01234567'
other_sha='abcdef0123456789abcdef0123456789abcdef01'
title='[autoupdate] обновления приостановлены'
marker='<!-- nivora-updater-paused -->'
sha_marker="<!-- nivora-updater-paused-sha: ${sha} -->"

make_issue() {
    local number="$1" login="$2" state="$3" body="$4"
    jq -nc \
        --argjson number "$number" \
        --arg title "$title" \
        --arg login "$login" \
        --arg state "$state" \
        --arg body "$body" \
        '{number: $number, title: $title, user: {login: $login}, state: $state, body: $body}'
}

as_pages() {
    jq -nc --argjson issues "$1" '[$issues]'
}

get_pause() {
    PATH="$fixture/bin:$PATH" \
    GITHUB_REPOSITORY='Cheviiot/Nivora' \
    MOCK_GH_ISSUES_JSON="$1" \
        "$repo_root/.github/tools/get_updater_pause.sh"
}

assert_paused() {
    local result="$1" expected_sha="$2"
    jq -e --arg sha "$expected_sha" '.paused == true and .sha == $sha' \
        <<<"$result" >/dev/null
}

assert_unpaused() {
    jq -e '.paused == false and .sha == ""' <<<"$1" >/dev/null
}

assert_fails() {
    local output
    if output="$(get_pause "$1" 2>&1)"; then
        echo "expected pause lookup to fail, got: ${output}" >&2
        exit 1
    fi
}

unpaused="$(get_pause '[]')"
assert_unpaused "$unpaused"

human_issue="$(make_issue 7 'octocat' open "$marker
$sha_marker
")"
assert_unpaused "$(get_pause "$(as_pages "[$human_issue]")")"

bot_issue="$(make_issue 8 'github-actions[bot]' open "$marker
$sha_marker

old recovery issue
")"
assert_paused "$(get_pause "$(as_pages "[$bot_issue]")")" "$sha"

legacy_body="$marker

Автоматические обновления приостановлены после сбоя проверки точного commit **${other_sha}**.
"
legacy_issue="$(make_issue 9 'github-actions[bot]' open "$legacy_body")"
assert_paused "$(get_pause "$(as_pages "[$legacy_issue]")")" "$other_sha"

malformed_body="$marker
<!-- nivora-updater-paused-sha: bad -->
Автоматические обновления приостановлены после сбоя проверки точного commit **${sha}**.
"
malformed_issue="$(make_issue 10 'github-actions[bot]' open "$malformed_body")"
assert_fails "$(as_pages "[$malformed_issue]")"
assert_fails "$(as_pages "[$bot_issue,$legacy_issue]")"
assert_fails '{}'

# A long issue list must not overflow an environment-variable/exec argument.
large_response="$fixture/large-response.json"
jq -nc --argjson issue "$bot_issue" \
    '[[{body: ("x" * 150000)}, $issue]]' >"$large_response"
cat >"$fixture/bin/gh-large" <<'LARGE_GH'
#!/bin/bash
cat "$MOCK_GH_LARGE_RESPONSE"
LARGE_GH
chmod 0755 "$fixture/bin/gh-large"
mv "$fixture/bin/gh" "$fixture/bin/gh-small"
ln -s gh-large "$fixture/bin/gh"
large_result="$(PATH="$fixture/bin:$PATH" GITHUB_REPOSITORY='owner/repo' \
    MOCK_GH_LARGE_RESPONSE="$large_response" \
    "$repo_root/.github/tools/get_updater_pause.sh")"
assert_paused "$large_result" "$sha"
rm "$fixture/bin/gh"
mv "$fixture/bin/gh-small" "$fixture/bin/gh"

if api_output="$(
    PATH="$fixture/bin:$PATH" \
    GITHUB_REPOSITORY='Cheviiot/Nivora' \
    MOCK_GH_FAIL=true \
        "$repo_root/.github/tools/get_updater_pause.sh" 2>&1
)"; then
    echo "expected GitHub API failure to fail closed, got: ${api_output}" >&2
    exit 1
fi

mutations="$fixture/mutations"
mutation_bodies="$fixture/mutation-bodies"
: >"$mutations"
: >"$mutation_bodies"
pause() {
    local state="$1" issue_list="$2"
    PATH="$fixture/bin:$PATH" \
    GITHUB_REPOSITORY='Cheviiot/Nivora' \
    GITHUB_RUN_ID=12345 \
    MOCK_GH_ISSUES_JSON="$issue_list" \
    MOCK_GH_MUTATIONS="$mutations" \
    MOCK_GH_BODIES="$mutation_bodies" \
        "$repo_root/.github/tools/set_updater_pause.sh" \
            "$state" "$sha" 'post-push verification failed'
}

pause true '[]'
closed_issue="$(make_issue 11 'github-actions[bot]' closed "$legacy_body")"
pause true "$(as_pages "[$closed_issue]")"
open_issue="$(make_issue 11 'github-actions[bot]' open "$marker
$sha_marker
")"
pause true "$(as_pages "[$open_issue]")"
pause false "$(as_pages "[$open_issue]")"

test "$(wc -l <"$mutations")" -eq 4
grep -Fq -- 'POST repos/Cheviiot/Nivora/issues' "$mutations"
grep -Fq -- 'PATCH repos/Cheviiot/Nivora/issues/11 open' "$mutations"
grep -Fq -- 'PATCH repos/Cheviiot/Nivora/issues/11 closed' "$mutations"
grep -Fq -- "$sha_marker" "$mutation_bodies"
grep -Fq -- 'Recovery проверит все пакеты' "$mutation_bodies"
if grep -Fq -- 'variable ' "$mutations"; then
    echo 'pause helper must not access repository variables' >&2
    exit 1
fi

echo 'OK: updater pause issue lifecycle'
