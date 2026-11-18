#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PACKAGE_UPDATES_LIB_ONLY=1
# shellcheck source=.github/tools/package_updates.sh
source "${repo_root}/.github/tools/package_updates.sh"

version_is_newer 2.0.0 1.9.9
version_is_newer 1.10.0 1.9.9
version_is_newer 150-105a 150-104a
if version_is_newer 1.9.9 2.0.0; then
    echo 'downgrade was incorrectly accepted' >&2
    exit 1
fi
if version_is_newer 2.0.0 2.0.0; then
    echo 'equal version was incorrectly accepted' >&2
    exit 1
fi
if version_is_newer 1.0.0-rc.1 1.0.0; then
    echo 'prerelease was incorrectly treated as newer than stable' >&2
    exit 1
fi

echo 'OK: package updater rejects downgrades'

# Some repositories publish bare numeric tags, others prefix them with v.
# Match ls-remote's optional ref filter so an accidental v-only lookup fails.
(
    fixture="$(mktemp -d)"
    trap 'find "$fixture" -mindepth 1 -delete; rmdir "$fixture"' EXIT
    cat >"$fixture/git" <<'EOF'
#!/bin/bash
set -euo pipefail
[[ "$1" == ls-remote && "$2" == --tags && "$3" == --refs ]]
patterns=("${@:5}")
for ref in refs/tags/v1.9.0 refs/tags/2.0.0 refs/tags/v2.1.0-rc.1 refs/tags/archive; do
    selected=0
    [[ "${#patterns[@]}" -gt 0 ]] || selected=1
    for pattern in "${patterns[@]}"; do
        case "$ref" in $pattern) selected=1 ;; esac
    done
    [[ "$selected" == 1 ]] || continue
    printf '%040d\t%s\n' 1 "$ref"
done
EOF
    chmod 0755 "$fixture/git"
    [[ "$(PATH="$fixture:$PATH" git_latest_stable_tag example/app)" == 2.0.0 ]]
)

# The API's release flags are authoritative when it returns releases. A bare
# numeric prerelease tag must not bypass them through the Git fallback.
(
    fixture="$(mktemp -d)"
    trap 'find "$fixture" -mindepth 1 -delete; rmdir "$fixture"' EXIT
    github_json() {
        printf '%s\n' "$MOCK_RELEASES"
        return "${MOCK_API_EXIT:-0}"
    }
    git_latest_stable_tag() {
        printf 'fallback\n' >>"$fixture/fallback-calls"
        printf '9.0.0\n'
    }
    MOCK_RELEASES='[
        {"draft":false,"prerelease":false,"tag_name":"v1.9.0"},
        {"draft":false,"prerelease":false,"tag_name":"2.0.0"},
        {"draft":false,"prerelease":true,"tag_name":"v3.0.0"},
        {"draft":true,"prerelease":false,"tag_name":"v4.0.0"},
        {"draft":false,"prerelease":false,"tag_name":"v5.0.0-rc.1"}
    ]'
    [[ "$(github_latest_release example/app)" == 2.0.0 ]]
    [[ ! -e "$fixture/fallback-calls" ]]

    for MOCK_RELEASES in \
        '[{"draft":false,"prerelease":true,"tag_name":"v2.0.0"}]' \
        '[{"draft":true,"prerelease":false,"tag_name":"v2.0.0"}]' \
        '[{"draft":false,"prerelease":false,"tag_name":"v2.0.0-rc.1"}]' \
        "$(jq -cn '[range(1;31) | {draft:false, prerelease:true, tag_name:("v2.0." + tostring)}]')"; do
        if github_latest_release example/app >"$fixture/output" 2>"$fixture/error"; then
            echo 'API-rejected releases were promoted through the Git fallback' >&2
            exit 1
        fi
        [[ ! -s "$fixture/output" && ! -e "$fixture/fallback-calls" ]]
        grep -Fq 'no eligible stable release among the first 30 releases' "$fixture/error"
    done

    # Preserve tag-only repositories and the existing API outage/malformed
    # response fallback. No HTTP calls or live repositories are used here.
    for MOCK_RELEASES in '[]' '{' '{"message":"rate limited"}' \
        '[{"draft":false,"tag_name":"v2.0.0"}]'; do
        [[ "$(github_latest_release example/app)" == 9.0.0 ]]
    done
    MOCK_RELEASES='[{"draft":false,"prerelease":true,"tag_name":"v2.0.0"}]'
    [[ "$(MOCK_API_EXIT=22 github_latest_release example/app)" == 9.0.0 ]]
    [[ "$(wc -l <"$fixture/fallback-calls")" -eq 5 ]]
)

# The desktop package follows the same stable-release selector as other apps.
github_latest_release() {
    case "$1" in
    anomalyco/opencode) printf '%s\n' '2.2.7' ;;
    telegramdesktop/tdesktop) printf '%s\n' '7.4.3' ;;
    *) return 1 ;;
    esac
}
require_package opencode
[[ "$(latest_version opencode)" == '2.2.7' ]]
for removed in kimi-code unsloth casement distroshelf github-desktop; do
    if (require_package "$removed" >/dev/null 2>&1); then
        echo "removed package was accepted: $removed" >&2
        exit 1
    fi
done

# curl emits CRLF headers; HTTP/2 has no reason phrase after the status code.
# A successful source probe must not silently suppress a published update.
(
    curl() {
        printf '%b' "${MOCK_HTTP_HEADERS:?}"
        return "${MOCK_CURL_EXIT:-0}"
    }
    MOCK_HTTP_HEADERS='HTTP/2 200\r\ncontent-length: 1048576\r\n\r\n' \
        upstream_source_published 'https://example.invalid/payload'
    if MOCK_HTTP_HEADERS='HTTP/2 404\r\n\r\n' \
        upstream_source_published 'https://example.invalid/payload'; then
        echo 'unpublished source was accepted' >&2
        exit 1
    fi

    expected_fingerprint="$(printf 'payload-tag' | sha256sum | awk '{print $1}')"
    MOCK_HTTP_HEADERS='HTTP/2 302\r\netag: "redirect-tag"\r\n\r\nHTTP/2 200\r\netag: "payload-tag"\r\n\r\n'
    [[ "$(http_etag_fingerprint https://example.invalid/latest)" == "$expected_fingerprint" ]]
    for MOCK_HTTP_HEADERS in \
        'HTTP/2 302\r\netag: "redirect-tag"\r\n\r\nHTTP/2 200\r\n\r\n' \
        'HTTP/2 200\r\netag: "prior-tag"\r\n\r\nHTTP/2 404\r\netag: "error-tag"\r\n\r\n' \
        'etag: "orphan-tag"\r\n\r\n' \
        'HTTP/2 invalid\r\netag: "payload-tag"\r\n\r\n'; do
        if http_etag_fingerprint https://example.invalid/latest >/dev/null 2>&1; then
            echo 'fingerprint accepted metadata without a successful final response ETag' >&2
            exit 1
        fi
    done
    MOCK_HTTP_HEADERS='HTTP/2 200\r\netag: "payload-tag"\r\n\r\n'
    if MOCK_CURL_EXIT=22 http_etag_fingerprint https://example.invalid/latest >/dev/null 2>&1; then
        echo 'fingerprint accepted a failed HTTP request' >&2
        exit 1
    fi
)

upstream_source_published() {
    [[ "$1" == 'https://github.com/telegramdesktop/tdesktop/releases/download/v7.4.3/td-setup-linux-x64-7.4.3.tar.xz' ]]
    [[ "${MOCK_TELEGRAM_PUBLISHED:-1}" == 1 ]]
}
current_version() { printf '%s\n' '7.2.5'; }
[[ "$(latest_telegram)" == '7.4.3' ]]
[[ "$(MOCK_TELEGRAM_PUBLISHED=0 latest_telegram 2>/dev/null)" == '7.2.5' ]]
echo 'OK: catalog removal and official Telegram release assets stay synchronized'
