#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d)"

cleanup() {
    find "$test_root" -mindepth 1 -delete
    rmdir "$test_root"
}
trap cleanup EXIT

install -d \
    "${test_root}/bin" \
    "${test_root}/repo/example" \
    "${test_root}/work"
touch "${test_root}/repo/example/Staplerfile"

source_url='https://example.invalid/source.bin?~archive=false&~name=source.bin'
source_hash="$(printf '%s' "$source_url" | sha256sum)"
source_hash="${source_hash%% *}"
install -d "${test_root}/cache/${source_hash}"
printf 'verified fixture\n' >"${test_root}/cache/${source_hash}/source.bin"
source_checksum="$(sha256sum "${test_root}/cache/${source_hash}/source.bin")"
source_checksum="${source_checksum%% *}"

cat >"${test_root}/bin/stplr-spec" <<'EOF'
#!/bin/bash
set -euo pipefail
[[ "$1" == get-field && "$2" == --path ]]
case "$4" in
name) printf '%s\n' example ;;
version) printf '%s\n' 1.0.0 ;;
sources) printf '%s\n' "$TEST_SOURCE_URL" ;;
checksums) printf 'sha256:%s\n' "$TEST_SOURCE_CHECKSUM" ;;
*) exit 2 ;;
esac
EOF
chmod 0755 "${test_root}/bin/stplr-spec"

cat >"${test_root}/bin/fake-engine" <<'EOF'
#!/bin/bash
set -euo pipefail
[[ "$1" == run ]]
shift
manifest=''
cache_db=''
while [[ "$#" -gt 0 ]]; do
    case "$1" in
    -v)
        case "$2" in
        *:/manifest:ro) manifest="${2%:/manifest:ro}" ;;
        *:/cache-db:ro) cache_db="${2%:/cache-db:ro}" ;;
        esac
        shift 2
        ;;
    *) shift ;;
    esac
done
[[ -s "$manifest" && -s "$cache_db" ]]
[[ "$(sqlite3 "$cache_db" 'SELECT count(*) FROM cache_record;')" == 1 ]]
printf '%s\t%s\n' "$manifest" "$cache_db" >>"$TEST_ENGINE_LOG"
[[ "${TEST_ENGINE_FAIL:-0}" != 1 ]] || exit 37
EOF
chmod 0755 "${test_root}/bin/fake-engine"

export PATH="${test_root}/bin:${PATH}"
export TEST_SOURCE_URL="$source_url"
export TEST_SOURCE_CHECKSUM="$source_checksum"
export TEST_ENGINE_LOG="${test_root}/engine.log"

# shellcheck source=.github/tools/lib/source_cache.sh
source "${repo_root}/.github/tools/lib/source_cache.sh"
cd "${test_root}/repo"

import_stplr_source_cache \
    fake-engine image-deb cache-deb "${test_root}/work" "${test_root}/cache" \
    example
import_stplr_source_cache \
    fake-engine image-rpm cache-rpm "${test_root}/work" "${test_root}/cache" \
    example

[[ "$(wc -l <"$TEST_ENGINE_LOG")" -eq 2 ]]
[[ "$(cut -f 1 "$TEST_ENGINE_LOG" | sort -u | wc -l)" -eq 2 ]]
[[ "$(find "${test_root}/work" -mindepth 1 -print -quit)" == '' ]]

if TEST_ENGINE_FAIL=1 import_stplr_source_cache \
    fake-engine image-fail cache-fail "${test_root}/work" "${test_root}/cache" \
    example; then
    echo 'source cache import unexpectedly accepted an engine failure' >&2
    exit 1
else
    status=$?
fi
[[ "$status" -eq 37 ]]
[[ "$(find "${test_root}/work" -mindepth 1 -print -quit)" == '' ]]

echo 'OK: source cache imports are isolated and failure-safe'
