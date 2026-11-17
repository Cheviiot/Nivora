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
    curl() { printf '%b' "${MOCK_HTTP_HEADERS:?}"; }
    MOCK_HTTP_HEADERS='HTTP/2 200\r\ncontent-length: 1048576\r\n\r\n' \
        upstream_source_published 'https://example.invalid/payload'
    if MOCK_HTTP_HEADERS='HTTP/2 404\r\n\r\n' \
        upstream_source_published 'https://example.invalid/payload'; then
        echo 'unpublished source was accepted' >&2
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
