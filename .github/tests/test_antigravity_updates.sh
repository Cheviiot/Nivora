#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixture="$(mktemp -d)"
cleanup() {
    find "$fixture" -mindepth 1 -delete
    rmdir "$fixture"
}
trap cleanup EXIT
install -d "$fixture/bin" "$fixture/repo/.github/tools" \
    "$fixture/repo/antigravity/.stapler"
cp "$repo_root/.github/tools/package_updates.sh" \
    "$repo_root/.github/tools/check_source_availability.sh" \
    "$fixture/repo/.github/tools/"
cp "$repo_root/antigravity/.stapler/update-run" \
    "$fixture/repo/antigravity/.stapler/"

export ANTIGRAVITY_TEST_HTML="$fixture/download.html"
export ANTIGRAVITY_TEST_REQUESTS="$fixture/requests"
export ANTIGRAVITY_TEST_CHECKSUMS="$fixture/checksums"
export ANTIGRAVITY_TEST_ORIGINAL="$fixture/repo/antigravity/Staplerfile"
export ANTIGRAVITY_TEST_BACKUP="$fixture/Staplerfile.before"
cat >"$fixture/bin/curl" <<'EOF'
#!/bin/bash
set -euo pipefail
url="${!#}"
case "$url" in
https://antigravity.google/download/)
    cat "$ANTIGRAVITY_TEST_HTML"
    if [[ -n "${ANTIGRAVITY_TEST_NEXT_HTML:-}" ]]; then
        cp "$ANTIGRAVITY_TEST_NEXT_HTML" "$ANTIGRAVITY_TEST_HTML"
    fi
    ;;
https://storage.googleapis.com/antigravity-public/antigravity-hub/*/linux-*/Antigravity.tar.gz)
    printf '%s\n' "$url" >>"$ANTIGRAVITY_TEST_REQUESTS"
    if [[ "${ANTIGRAVITY_TEST_UNPUBLISHED:-0}" == 1 && "$url" == */linux-arm/* ]]; then
        printf 'HTTP/2 404\r\ncontent-length: 64\r\n\r\n'
        exit 22
    fi
    printf 'HTTP/2 200\r\ncontent-length: 1048576\r\n\r\n'
    ;;
*) echo "unexpected URL: $url" >&2; exit 1 ;;
esac
EOF
cat >"$fixture/bin/stplr-spec" <<'EOF'
#!/usr/bin/env python3
import os
from pathlib import Path
import re
import sys

command = sys.argv[1]
assert sys.argv[2] == "--path"
path = Path(sys.argv[3])
text = path.read_text()
fields = dict(re.findall(r"^([a-z0-9_]+)=[\"']?([^\"'\n]+?)[\"']?$", text, re.M))
if command == "get-field":
    name = sys.argv[4]
    if name.startswith("sources"):
        entries = re.search(r"^" + name + r"=\(\n(.*?)\n\)", text, re.M | re.S)[1]
        entries = re.findall(r"^[ \t]*[\"'](.*?)[\"']$", entries, re.M)
        for entry in entries:
            for key, value in fields.items():
                entry = entry.replace("${" + key + "}", value)
            print(entry)
    else:
        print(fields[name])
elif command == "set-field":
    name, value = sys.argv[4:6]
    text, count = re.subn(r"^" + name + r"=.*$", name + "=" + value, text, flags=re.M)
    assert count == 1
    path.write_text(text)
elif command == "update-checksums":
    assert path != Path(os.environ["ANTIGRAVITY_TEST_ORIGINAL"])
    assert (path.parent / "local.txt").read_text() == "local payload\n"
    assert fields["upstream_hub"].rsplit("-", 1)[0] == fields["version"]
    assert Path(os.environ["ANTIGRAVITY_TEST_ORIGINAL"]).read_bytes() == Path(
        os.environ["ANTIGRAVITY_TEST_BACKUP"]
    ).read_bytes()
    with open(os.environ["ANTIGRAVITY_TEST_CHECKSUMS"], "a") as log:
        log.write(fields["upstream_hub"] + "\n")
    path.write_text(text.replace("sha256:" + "0" * 64, "sha256:" + "1" * 64))
    if os.environ.get("ANTIGRAVITY_TEST_CHECKSUM_FAILURE") == "1":
        raise SystemExit(42)
else:
    raise SystemExit("unexpected stplr-spec command")
EOF
chmod 0755 "$fixture/bin/curl" "$fixture/bin/stplr-spec"
export PATH="$fixture/bin:$PATH"
updater="$fixture/repo/.github/tools/package_updates.sh"
hook="$fixture/repo/antigravity/.stapler/update-run"
recipe="$fixture/repo/antigravity/Staplerfile"

page() {
    local x64="$1" arm="$2"
    # Minified markup, reordered attributes, duplicate links and IDE downloads
    # must not select the wrong product or throw away the full App build ID.
    printf '<a href="https://example.invalid/antigravity/99.0.0/IDE.tar.gz">IDE</a>'
    printf '<a data-os="linux" href="https://storage.googleapis.com/antigravity-public/antigravity-hub/%s/linux-x64/Antigravity.tar.gz">x64</a>' "$x64"
    printf '<a href="https://storage.googleapis.com/antigravity-public/antigravity-hub/%s/linux-arm/Antigravity.tar.gz" data-os="linux">arm64</a>' "$arm"
    printf '<a href="https://storage.googleapis.com/antigravity-public/antigravity-hub/%s/linux-x64/Antigravity.tar.gz">x64 again</a>\n' "$x64"
}

expect_failure() {
    if "$@" >"$fixture/failure.log" 2>&1; then
        echo "unexpected success: $*" >&2
        exit 1
    fi
}

page 2.33.0-700 2.33.0-700 >"$ANTIGRAVITY_TEST_HTML"
[[ "$("$updater" antigravity-hub)" == 2.33.0-700 ]]
[[ "$("$updater" antigravity-hub 2.33.0)" == 2.33.0-700 ]]
expect_failure "$updater" antigravity-hub 2.32.1
page 2.33.0-700 2.33.0-701 >"$ANTIGRAVITY_TEST_HTML"
expect_failure "$updater" antigravity-hub
page 2.33.0-700 2.32.1-600 >"$ANTIGRAVITY_TEST_HTML"
expect_failure "$updater" antigravity-hub
page 2.33.0-700 2.33.0-700 | \
    sed 's|https://storage.googleapis.com/|https://storage.googleapis.com.example.invalid/|g' \
    >"$ANTIGRAVITY_TEST_HTML"
expect_failure "$updater" antigravity-hub
printf '<a href="https://antigravity.google/ide">IDE only</a>\n' >"$ANTIGRAVITY_TEST_HTML"
expect_failure "$updater" antigravity-hub
page 2.33.0-700 2.33.0-700 >"$ANTIGRAVITY_TEST_HTML"
page 2.34.0-800 2.34.0-800 >>"$ANTIGRAVITY_TEST_HTML"
expect_failure "$updater" antigravity-hub

reset_recipe() {
    cat >"$recipe" <<'EOF'
name='antigravity'
version='2.32.1'
release=5
upstream_hub='2.32.1-600'
sources=(
 'https://storage.googleapis.com/antigravity-public/antigravity-hub/${upstream_hub}/linux-x64/Antigravity.tar.gz?~archive=false&~name=Antigravity.tar.gz'
 'local:///local.txt'
)
sources_arm64=(
 'https://storage.googleapis.com/antigravity-public/antigravity-hub/${upstream_hub}/linux-arm/Antigravity.tar.gz?~archive=false&~name=Antigravity.tar.gz'
 'local:///local.txt'
)
checksums=(
 'sha256:0000000000000000000000000000000000000000000000000000000000000000'
)
EOF
    printf 'local payload\n' >"$fixture/repo/antigravity/local.txt"
    cp "$recipe" "$ANTIGRAVITY_TEST_BACKUP"
    : >"$ANTIGRAVITY_TEST_REQUESTS"
    : >"$ANTIGRAVITY_TEST_CHECKSUMS"
}

reset_recipe
page 2.33.0-700 2.33.0-700 >"$ANTIGRAVITY_TEST_HTML"
[[ "$("$updater" check antigravity)" == '2.32.1 2.33.0' ]]
expected="$(printf '%s' 2.33.0-700 | sha256sum | awk '{print $1}')"
[[ "$("$updater" fingerprints antigravity)" == "source_fingerprint"$'\t'"$expected" ]]
"$fixture/repo/.github/tools/check_source_availability.sh" antigravity 2.33.0 >/dev/null
[[ "$(wc -l <"$ANTIGRAVITY_TEST_REQUESTS")" -eq 2 ]]
if grep -q '/2.32.1-600/' "$ANTIGRAVITY_TEST_REQUESTS"; then
    echo 'source preflight checked the obsolete hub' >&2
    exit 1
fi
cmp "$recipe" "$ANTIGRAVITY_TEST_BACKUP"
ANTIGRAVITY_EXPECTED_FINGERPRINT="$expected" "$hook" 2.33.0
[[ "$(stplr-spec get-field --path "$recipe" version)" == 2.33.0 ]]
[[ "$(stplr-spec get-field --path "$recipe" upstream_hub)" == 2.33.0-700 ]]
[[ "$(stplr-spec get-field --path "$recipe" release)" == 1 ]]
[[ "$(cat "$ANTIGRAVITY_TEST_CHECKSUMS")" == 2.33.0-700 ]]

# A rebuild keeps the App version and increments the packaging release.
reset_recipe
page 2.32.1-601 2.32.1-601 >"$ANTIGRAVITY_TEST_HTML"
"$hook" 2.32.1
[[ "$(stplr-spec get-field --path "$recipe" upstream_hub)" == 2.32.1-601 ]]
[[ "$(stplr-spec get-field --path "$recipe" release)" == 6 ]]
cp "$recipe" "$ANTIGRAVITY_TEST_BACKUP"
"$hook" 2.32.1
cmp "$recipe" "$ANTIGRAVITY_TEST_BACKUP"
[[ "$(wc -l <"$ANTIGRAVITY_TEST_CHECKSUMS")" -eq 1 ]]

# Missing source, changed detection snapshot, invalid input, downgrade and
# checksum failure (after the staging file is edited) all preserve the recipe.
reset_recipe
page 2.33.0-700 2.33.0-700 >"$ANTIGRAVITY_TEST_HTML"
expect_failure env ANTIGRAVITY_TEST_UNPUBLISHED=1 "$hook" 2.33.0
cmp "$recipe" "$ANTIGRAVITY_TEST_BACKUP"
test ! -s "$ANTIGRAVITY_TEST_CHECKSUMS"
expect_failure env ANTIGRAVITY_EXPECTED_FINGERPRINT=wrong "$hook" 2.33.0
cmp "$recipe" "$ANTIGRAVITY_TEST_BACKUP"
expect_failure env ANTIGRAVITY_TEST_CHECKSUM_FAILURE=1 "$hook" 2.33.0
cmp "$recipe" "$ANTIGRAVITY_TEST_BACKUP"
[[ -z "$(find "$fixture/repo/antigravity" -name '.Staplerfile.update.*' -print -quit)" ]]
page 2.31.0-500 2.31.0-500 >"$ANTIGRAVITY_TEST_HTML"
expect_failure "$hook" 2.31.0
cmp "$recipe" "$ANTIGRAVITY_TEST_BACKUP"
expect_failure "$hook" '2.33.0;touch nope'

reset_recipe
page 2.32.1-601 2.32.1-601 >"$ANTIGRAVITY_TEST_HTML"
(
    PACKAGE_UPDATES_LIB_ONLY=1
    # shellcheck source=.github/tools/package_updates.sh
    source "$updater"
    is_mutable_source_package antigravity
    # Other package feeds are irrelevant to this fixture; keep the production
    # detector and fingerprint comparison for Antigravity itself.
    is_mutable_source_package() { [[ "$1" == antigravity ]]; }
    # Called indirectly by the sourced check_package function.
    # shellcheck disable=SC2329
    current_version() {
        if [[ "$1" == antigravity ]]; then
            stplr-spec get-field --path "$recipe" version
        else
            printf '1\n'
        fi
    }
    # shellcheck disable=SC2329
    latest_version() {
        if [[ "$1" == antigravity ]]; then
            latest_antigravity
        else
            printf '1\n'
        fi
    }
    current_fingerprint="$(printf '%s' 2.32.1-600 | sha256sum | awk '{print $1}')"
    fingerprints_match_recipe antigravity \
        "{\"source_fingerprint\":\"$current_fingerprint\"}"
    source_fingerprint_drifted antigravity
    export PACKAGE_UPDATE_PLAN_FILE="$fixture/plan"
    export PACKAGE_UPDATE_FAILURES_FILE="$fixture/detection-failures"
    [[ "$(outdated_packages)" == antigravity ]]
    IFS=$'\t' read -r package current latest fingerprints <"$PACKAGE_UPDATE_PLAN_FILE"
    [[ "$package" == antigravity && "$current" == 2.32.1 && "$latest" == 2.32.1 ]]
    expected="$(printf '%s' 2.32.1-601 | sha256sum | awk '{print $1}')"
    [[ "$(jq -r .source_fingerprint <<<"$fingerprints")" == "$expected" ]]
    : >"$PACKAGE_UPDATE_PLAN_FILE"
    page 2.32.1-602 2.32.1-602 >"$fixture/next.html"
    export ANTIGRAVITY_TEST_NEXT_HTML="$fixture/next.html"
    [[ -z "$(outdated_packages 2>"$fixture/detection.log")" ]]
    test ! -s "$PACKAGE_UPDATE_PLAN_FILE"
    grep -Fxq antigravity "$PACKAGE_UPDATE_FAILURES_FILE"
)

echo 'OK: Antigravity updates pin matching architectures and commit recipe changes atomically'
