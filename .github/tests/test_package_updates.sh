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

# The mutable download's ETag must come from the final successful response.
(
    curl() {
        printf '%b' "${MOCK_HTTP_HEADERS:?}"
        return "${MOCK_CURL_EXIT:-0}"
    }
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

(
    curl() {
        [[ "${!#}" == 'https://github.com/telegramdesktop/tdesktop/releases/download/v7.4.3/td-setup-linux-x64-7.4.3.tar.xz' ]] || return 22
        [[ " $* " == *" -w %{http_code} "* ]] || return 22
        printf '%s' "$MOCK_HTTP_STATUS"
        return "${MOCK_CURL_EXIT:-0}"
    }
    current_version() { printf '%s\n' '7.2.5'; }
    [[ "$(MOCK_HTTP_STATUS=200 check_package telegram)" == '7.2.5 7.4.3' ]]
    for MOCK_HTTP_STATUS in 404 410; do
        [[ "$(check_package telegram 2>/dev/null)" == '7.2.5 7.2.5' ]]
    done
    for MOCK_HTTP_STATUS in 429 503; do
        if check_package telegram 2>/dev/null; then
            echo "Telegram was reported current after HTTP ${MOCK_HTTP_STATUS}" >&2
            exit 1
        fi
    done
    if MOCK_HTTP_STATUS=404 MOCK_CURL_EXIT=28 check_package telegram 2>/dev/null; then
        echo 'Telegram was reported current after a transport timeout' >&2
        exit 1
    fi
)
echo 'OK: catalog removal and official Telegram release assets stay synchronized'

(
    fixture="$(mktemp -d)"
    trap 'find "$fixture" -mindepth 1 -delete; rmdir "$fixture"' EXIT
    cd "$fixture"
    printf '2.0\n' >debian-binary
    truncate -s 3M data.tar.xz
    make_deb() {
        local target="$1" architecture="$2" version="$3"
        printf 'Package: chatgpt\nVersion: %s\nArchitecture: %s\n' "$version" "$architecture" >control
        tar -cJf control.tar.xz ./control
        rm -f "$target"
        ar rc "$target" debian-binary control.tar.xz data.tar.xz
    }
    curl() {
        local output='' url="${!#}"
        [[ " $* " == *" --range 0-2097151 "* ]] || return 22
        while (($#)); do
            if [[ "$1" == -o ]]; then output="$2"; break; fi
            shift
        done
        case "$url" in
        'https://persistent.oaistatic.com/codex-app-prod/linux/deb/latest/chatgpt_amd64.deb' | \
        'https://persistent.oaistatic.com/codex-app-prod/linux/deb/latest/chatgpt_arm64.deb')
            head -c 2097152 "${url##*/}" >"$output" ;;
        *) return 22 ;;
        esac
    }
    current_version() { printf '1.0\n'; }
    make_deb chatgpt_amd64.deb amd64 2.0
    make_deb chatgpt_arm64.deb arm64 2.0
    [[ "$(check_package chatgpt)" == '1.0 2.0' ]]
    make_deb chatgpt_arm64.deb arm64 1.0
    if check_package chatgpt >result 2>error; then exit 1; fi
    [[ ! -s result ]]
    grep -Fq 'amd64=2.0, arm64=1.0' error
    make_deb chatgpt_arm64.deb amd64 2.0
    if check_package chatgpt >result 2>error; then exit 1; fi
    [[ ! -s result ]]
    grep -Fq 'architecture for arm64' error
)
echo 'OK: ChatGPT release detection requires matching amd64 and arm64 DEB metadata'
