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
[[ "$url" == "$SOURCE_PROBE_EXPECTED_URL" ]] || {
    echo "unexpected source URL: $url" >&2
    exit 1
}
printf '%s\n' "$url" >>"$SOURCE_PROBE_REQUESTS"
printf '%b' "$SOURCE_PROBE_HEADERS"
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

for response in 'HTTP/2 404\r\n\r\n' 'HTTP/2 200\r\ncontent-length: 64\r\n\r\n'; do
    SOURCE_PROBE_HEADERS="$response"
    if "$probe" anidesk 0.0.2 >"$fixture/failure.log" 2>&1; then
        echo 'source probe accepted a missing or undersized payload' >&2
        exit 1
    fi
    cmp "$fixture/before" "$fixture/repo/anidesk/Staplerfile"
done

echo 'OK: AniDesk probes the requested Debian filename without changing its recipe'
