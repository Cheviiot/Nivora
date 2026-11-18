#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixture="$(mktemp -d)"
cleanup() {
    find "$fixture" -mindepth 1 -delete
    rmdir "$fixture"
}
trap cleanup EXIT

install -d "$fixture/repo/.github/tools" "$fixture/repo/anidesk" "$fixture/bin"
cp "$repo_root/.github/tools/check_source_availability.sh" "$fixture/repo/.github/tools/"
cat >"$fixture/repo/anidesk/Staplerfile" <<'EOF'
name='anidesk'
version='0.0.1-beta.7'
debian_version='0.0.1.beta.7'
release=1
architectures=('amd64')
sources=(
 "https://example.invalid/releases/v${version}/anidesk_${debian_version}_amd64.deb?~archive=false&~name=anidesk.deb"
)
checksums=(
 'sha256:0000000000000000000000000000000000000000000000000000000000000001'
)
EOF
cp "$fixture/repo/anidesk/Staplerfile" "$fixture/before"

cat >"$fixture/bin/curl" <<'EOF'
#!/bin/bash
set -euo pipefail
url="${!#}"
grep -Fxq -- "$url" <<<"$SOURCE_PROBE_EXPECTED_URL" || {
    echo "unexpected source URL: $url" >&2
    exit 1
}
printf '%s\n' "$url" >>"$SOURCE_PROBE_REQUESTS"
if [[ "${SOURCE_PROBE_GET_HEADERS:-}" != '' && " $* " == *' --range '* ]]; then
    printf '%b' "$SOURCE_PROBE_GET_HEADERS"
else
    printf '%b' "$SOURCE_PROBE_HEADERS"
fi
exit "${SOURCE_PROBE_CURL_EXIT:-0}"
EOF
chmod 0755 "$fixture/bin/curl"
export PATH="$fixture/bin:$PATH"
export SOURCE_PROBE_REQUESTS="$fixture/requests"
export SOURCE_PROBE_EXPECTED_URL SOURCE_PROBE_HEADERS
probe="$fixture/repo/.github/tools/check_source_availability.sh"

for version in 0.0.1-beta.8 0.0.2; do
    SOURCE_PROBE_EXPECTED_URL="https://example.invalid/releases/v${version}/anidesk_${version/-beta./.beta.}_amd64.deb"
    SOURCE_PROBE_HEADERS='HTTP/2 200\r\ncontent-length: 1048576\r\n\r\n'
    : >"$SOURCE_PROBE_REQUESTS"
    "$probe" anidesk "$version" >/dev/null
    [[ "$(cat "$SOURCE_PROBE_REQUESTS")" == "$SOURCE_PROBE_EXPECTED_URL" ]]
    cmp "$fixture/before" "$fixture/repo/anidesk/Staplerfile"
done

for response in \
    'HTTP/2 404\r\n\r\n' \
    'HTTP/2 200\r\ncontent-length: 64\r\n\r\n' \
    'HTTP/2 200\r\ncontent-length: invalid\r\n\r\n' \
    'HTTP/2 200\r\ncontent-length: 1048576\r\n\r\nHTTP/2 404\r\n\r\n' \
    'content-length: 1048576\r\n\r\n'; do
    SOURCE_PROBE_HEADERS="$response"
    if "$probe" anidesk 0.0.2 >"$fixture/failure.log" 2>&1; then
        echo 'source probe accepted a missing or undersized payload' >&2
        exit 1
    fi
    cmp "$fixture/before" "$fixture/repo/anidesk/Staplerfile"
done

# A small redirect response must not be confused with the actual payload.
# The final response may omit Content-Length (e.g. a chunked download), or
# supply a new decimal size. Only the final response controls the size gate.
for response in \
    'HTTP/2 302\r\ncontent-length: 64\r\n\r\nHTTP/2 200\r\ntransfer-encoding: chunked\r\n\r\n' \
    'HTTP/2 302\r\ncontent-length: 64\r\n\r\nHTTP/2 200\r\ncontent-length: 0001048576\r\n\r\n'; do
    SOURCE_PROBE_HEADERS="$response"
    "$probe" anidesk 0.0.2 >/dev/null
done
SOURCE_PROBE_HEADERS='HTTP/2 302\r\ncontent-length: 1048576\r\n\r\nHTTP/2 200\r\ncontent-length: 64\r\n\r\n'
if "$probe" anidesk 0.0.2 >"$fixture/failure.log" 2>&1; then
    echo 'source probe accepted an undersized final response after a large redirect' >&2
    exit 1
fi
SOURCE_PROBE_HEADERS='HTTP/2 200\r\ncontent-length: 1048576\r\n\r\n'
if SOURCE_PROBE_CURL_EXIT=22 "$probe" anidesk 0.0.2 >"$fixture/failure.log" 2>&1; then
    echo 'source probe accepted partial output from a failed HTTP request' >&2
    exit 1
fi

# A failed/empty architecture-specific get-field must not turn a partial
# source check into success. Keep the real parser for every unaffected field.
export SOURCE_PROBE_REAL_STPLR
SOURCE_PROBE_REAL_STPLR="$(command -v stplr-spec)"
cat >"$fixture/bin/probe-stplr" <<'EOF'
#!/bin/bash
set -euo pipefail
if [[ "$1" == get-field && "${!#}" == sources_arm64 ]]; then
    case "${SOURCE_PROBE_FIELD_MODE:-ok}" in
    fail) exit 42 ;;
    partial)
        printf 'https://example.invalid/arm64\n'
        exit 42
        ;;
    empty) exit 0 ;;
    whitespace) printf '  \t\n'; exit 0 ;;
    esac
fi
exec "$SOURCE_PROBE_REAL_STPLR" "$@"
EOF
chmod 0755 "$fixture/bin/probe-stplr"
install -d "$fixture/repo/demo"
cat >"$fixture/repo/demo/Staplerfile" <<'EOF'
name='demo'
version='1.0.0'
architectures=('amd64' 'arm64')
sources=(
 'https://example.invalid/amd64'
)
sources_arm64=(
 'https://example.invalid/arm64'
)
EOF
SOURCE_PROBE_EXPECTED_URL=$'https://example.invalid/amd64\nhttps://example.invalid/arm64'
: >"$SOURCE_PROBE_REQUESTS"
STPLR_SPEC_COMMAND="$fixture/bin/probe-stplr" "$probe" demo >/dev/null
[[ "$(cat "$SOURCE_PROBE_REQUESTS")" == "$SOURCE_PROBE_EXPECTED_URL" ]]
for mode in fail partial empty whitespace; do
    : >"$SOURCE_PROBE_REQUESTS"
    if SOURCE_PROBE_FIELD_MODE="$mode" STPLR_SPEC_COMMAND="$fixture/bin/probe-stplr" \
        "$probe" demo >"$fixture/failure.log" 2>&1; then
        echo "source probe silently skipped an architecture: ${mode}" >&2
        exit 1
    fi
    grep -Fq 'sources_arm64' "$fixture/failure.log"
    [[ "$(cat "$SOURCE_PROBE_REQUESTS")" == https://example.invalid/amd64 ]]
done

# Snapshot sources use the candidate commit, never the previous recipe pin.
plugin=gnome-software-plugin-stplr
install -d "$fixture/repo/$plugin/.stapler"
cat >"$fixture/repo/$plugin/Staplerfile" <<'EOF'
name='gnome-software-plugin-stplr'
version='0.3.0.git20260525192209'
upstream_commit='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
sources=(
 "https://altlinux.space/api/v1/repos/stapler/gnome-software-plugin-stplr/archive/${upstream_commit}.tar.gz?~archive=false&~name=source.tar.gz"
)
EOF
cat >"$fixture/repo/$plugin/.stapler/update-run" <<'EOF'
#!/bin/bash
[[ "$1" == --snapshot ]] || exit 2
printf '%s\n' '{"version":"0.3.0.git20260526192209","commit":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","created":"2026-05-26T19:22:09Z"}'
EOF
chmod 0755 "$fixture/repo/$plugin/.stapler/update-run"
cp "$fixture/repo/$plugin/Staplerfile" "$fixture/plugin-before"
SOURCE_PROBE_EXPECTED_URL='https://altlinux.space/api/v1/repos/stapler/gnome-software-plugin-stplr/archive/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.tar.gz'
: >"$SOURCE_PROBE_REQUESTS"
"$probe" "$plugin" 0.3.0.git20260526192209 >/dev/null
[[ "$(cat "$SOURCE_PROBE_REQUESTS")" == "$SOURCE_PROBE_EXPECTED_URL" ]]
cmp "$fixture/plugin-before" "$fixture/repo/$plugin/Staplerfile"
: >"$SOURCE_PROBE_REQUESTS"
if "$probe" "$plugin" 0.3.0.git20260527192209 >"$fixture/failure.log" 2>&1; then
    echo 'source probe accepted plugin snapshot drift' >&2
    exit 1
fi
test ! -s "$SOURCE_PROBE_REQUESTS"
cmp "$fixture/plugin-before" "$fixture/repo/$plugin/Staplerfile"

# The immutable Forgejo archive supports GET while rejecting HEAD. Other
# errors, failed downloads and undersized GET responses remain failures.
SOURCE_PROBE_HEADERS='HTTP/2 405\r\n\r\n'
export SOURCE_PROBE_GET_HEADERS='HTTP/2 200\r\ncontent-length: 38962\r\n\r\n'
: >"$SOURCE_PROBE_REQUESTS"
"$probe" "$plugin" 0.3.0.git20260526192209 >/dev/null
[[ "$(wc -l <"$SOURCE_PROBE_REQUESTS")" -eq 2 ]]
for response in 'HTTP/2 404\r\n\r\n' 'HTTP/2 200\r\ncontent-length: 64\r\n\r\n'; do
    SOURCE_PROBE_GET_HEADERS="$response"
    if "$probe" "$plugin" 0.3.0.git20260526192209 >"$fixture/failure.log" 2>&1; then
        echo 'plugin GET fallback accepted a missing or undersized source' >&2
        exit 1
    fi
done
SOURCE_PROBE_HEADERS='HTTP/2 403\r\n\r\n'
SOURCE_PROBE_GET_HEADERS='HTTP/2 200\r\ncontent-length: 38962\r\n\r\n'
: >"$SOURCE_PROBE_REQUESTS"
if "$probe" "$plugin" 0.3.0.git20260526192209 >"$fixture/failure.log" 2>&1; then
    echo 'plugin probe bypassed a non-method HTTP rejection' >&2
    exit 1
fi
[[ "$(wc -l <"$SOURCE_PROBE_REQUESTS")" -eq 1 ]]
cmp "$fixture/plugin-before" "$fixture/repo/$plugin/Staplerfile"

echo 'OK: source probes validate requested filenames, pinned snapshots, final HTTP metadata and every architecture'
