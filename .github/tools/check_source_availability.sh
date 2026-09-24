#!/bin/bash
# Verify that every remote source of a recipe is actually published before the
# updater is allowed to pin a checksum over it.
#
# Stapler v0.1.1 does not look at the HTTP status code at all: pkg/dl/file.go
# hands res.Body straight to the writer, so a 404 page is stored as the source
# and stplr-spec update-checksums happily pins its SHA-256. The recipe then
# looks perfectly valid and only fails later, during the build, if package()
# happens to unpack the payload. This gate moves that failure to the front and
# makes it explicit.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
stplr_spec_command="${STPLR_SPEC_COMMAND:-stplr-spec}"

# An HTML error page is small; a real payload never is. Keep the floor low
# enough for tiny legitimate sources such as a LICENSE file.
readonly MIN_SOURCE_BYTES="${NIVORA_MIN_SOURCE_BYTES:-512}"

die() {
    echo "check_source_availability: $*" >&2
    exit 1
}

usage() {
    echo 'usage: check_source_availability.sh <package> [version]' >&2
    exit 2
}

[[ "$#" -ge 1 && "$#" -le 2 ]] || usage
package="$1"
version="${2:-}"

recipe="${repo_root}/${package}/Staplerfile"
[[ -f "$recipe" ]] || die "unknown package: ${package}"

work_dir="$(mktemp -d)"
cleanup() {
    find "$work_dir" -mindepth 1 -delete
    rmdir "$work_dir"
}
trap cleanup EXIT

probe_recipe="${work_dir}/Staplerfile"
install -m644 "$recipe" "$probe_recipe"
if [[ -n "$version" ]]; then
    [[ "$version" =~ ^[A-Za-z0-9._+~-]+$ ]] || die "invalid version: ${version}"
    "$stplr_spec_command" set-field --path "$probe_recipe" version "$version" ||
        die "cannot set probe version ${version}"
fi

# Every sources array in the recipe, including per-architecture overrides.
mapfile -t source_fields < <(
    grep -oE '^sources(_[a-z0-9_]+)?=\(' "$recipe" |
        sed 's/=($//;s/=(//' |
        sort -u
)
[[ "${#source_fields[@]}" -gt 0 ]] || die "${package}: no sources array found"

# Mirror FileDownloader.parseURLAndParams: only ~name and ~archive are stripped
# before the request, every other query parameter is sent to the server.
strip_stplr_params() {
    python3 - "$1" <<'PY'
import sys
from urllib.parse import urlsplit, urlunsplit, parse_qsl, urlencode

parts = urlsplit(sys.argv[1])
query = [(k, v) for k, v in parse_qsl(parts.query, keep_blank_values=True)
         if k not in {"~name", "~archive"}]
print(urlunsplit(parts._replace(query=urlencode(query))))
PY
}

probe_url() {
    local url="$1"
    local headers status length

    headers="$(
        curl --retry 3 --retry-delay 2 --retry-all-errors \
            --connect-timeout 30 --max-time 120 -sSIL "$url" 2>/dev/null
    )" || {
        echo "unreachable"
        return 1
    }

    status="$(
        awk 'toupper($1) ~ /^HTTP/ { code = $2 } END { print code }' <<<"$headers"
    )"
    [[ "$status" =~ ^2[0-9][0-9]$ ]] || {
        echo "HTTP ${status:-unknown}"
        return 1
    }

    length="$(
        awk '
            tolower($1) == "content-length:" { value = $2; gsub(/\r/, "", value) }
            END { if (value != "") print value }
        ' <<<"$headers"
    )"
    if [[ -n "$length" && "$length" -lt "$MIN_SOURCE_BYTES" ]]; then
        echo "only ${length} bytes"
        return 1
    fi

    return 0
}

failures=0
checked=0
declare -A seen=()

for field in "${source_fields[@]}"; do
    read -ra urls <<<"$(
        "$stplr_spec_command" get-field --path "$probe_recipe" "$field"
    )" || die "${package}: cannot read ${field}"

    for source in "${urls[@]}"; do
        [[ "$source" == local://* ]] && continue
        [[ -n "${seen["$source"]:-}" ]] && continue
        seen["$source"]=1

        url="$(strip_stplr_params "$source")"
        checked=$((checked + 1))
        if reason="$(probe_url "$url")"; then
            printf 'OK   %s\n' "$url"
        else
            printf 'FAIL %s (%s)\n' "$url" "$reason" >&2
            failures=$((failures + 1))
        fi
    done
done

[[ "$checked" -gt 0 ]] || die "${package}: no remote sources to verify"
[[ "$failures" -eq 0 ]] || die \
    "${package}${version:+ ${version}}: ${failures} source(s) are not published"

echo "OK: ${package}${version:+ ${version}} — ${checked} источник(ов) доступны"
