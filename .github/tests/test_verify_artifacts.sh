#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -r -- "$fixture"' EXIT
install -d "$fixture/repo/.github/tools" "$fixture/repo/demo" \
    "$fixture/repo/tailscale" "$fixture/bin"
cp "$repo_root/.github/tools/verify_artifacts.sh" "$fixture/repo/.github/tools/"
touch "$fixture/repo/demo/Staplerfile" "$fixture/repo/demo/demo.rpm"
touch "$fixture/repo/tailscale/Staplerfile" "$fixture/repo/tailscale/tailscale.rpm"

cat >"$fixture/bin/stplr-spec" <<'EOF'
#!/bin/bash
case "$4" in
name) echo "${TEST_PACKAGE:-demo}" ;;
version) echo 1 ;;
release) echo 1 ;;
architectures) echo amd64 ;;
*) exit 1 ;;
esac
EOF
cat >"$fixture/bin/rpm" <<'EOF'
#!/bin/bash
set -euo pipefail
package="${TEST_PACKAGE:-demo}"
case "$*" in
*'--queryformat %{NAME}'*)
    echo "${package}+stplr-default|0|1|alt1|x86_64"
    [[ "${TEST_IDENTITY_FAILURE:-0}" != 1 ]] || exit 42
    ;;
*'-qlp'*)
    printf '%s\n' '/opt/Demo App/demo' "/usr/bin/$package" "/usr/share/licenses/$package/LICENSE"
    [[ -z "${TEST_UNIT_PATH:-}" ]] || printf '%s\n' "$TEST_UNIT_PATH"
    [[ "${TEST_PAYLOAD_FAILURE:-0}" != 1 ]] || exit 42
    ;;
*'--queryformat [%{FILEFLAGS}'*)
    [[ "${TEST_CONFIG_METADATA_FAILURE:-0}" != 1 ]] || exit 42
    printf '17\t/etc/default/unrelated\n'
    if [[ "${TEST_CONFIG_PRESENT:-1}" == 1 ]]; then
        printf '%s\t/etc/default/tailscaled\n' "${TEST_CONFIG_FLAGS:-17}"
    fi
    ;;
*'--queryformat [%{FILEMODES:octal}'*)
    [[ "${TEST_METADATA_FAILURE:-0}" != 1 ]] || exit 42
    printf '100644\t%s\t%s\t/opt/Demo App/resources/app file\n' \
        "${TEST_FILE_OWNER:-root}" "${TEST_FILE_GROUP:-root}"
    printf '%s\troot\troot\t/usr/bin/demo\n' "${TEST_BINARY_MODE:-100755}"
    ;;
*) echo "unexpected RPM query: $*" >&2; exit 1 ;;
esac
EOF
chmod 0755 "$fixture/bin/"*
export PATH="$fixture/bin:$PATH"
export NIVORA_EXPECTED_ARCH=amd64
unset NIVORA_EXPECTED_REPOSITORY NIVORA_EXPECTED_EPOCH NIVORA_RPM_RELEASE_PREFIX

verify() {
    "$fixture/repo/.github/tools/verify_artifacts.sh" "${TEST_PACKAGE:-demo}" >"$fixture/output" 2>&1
}
expect_failure() {
    if verify; then
        echo "artifact verification unexpectedly accepted: $*" >&2
        exit 1
    fi
}

verify
TEST_BINARY_MODE=120000 verify
TEST_FILE_OWNER=user expect_failure 'non-root owner'
grep -Fq 'user:root у /opt/Demo App/resources/app file' "$fixture/output"
TEST_FILE_GROUP=users expect_failure 'non-root group'
TEST_BINARY_MODE=100644 expect_failure 'non-executable command'
TEST_BINARY_MODE=104755 expect_failure 'setuid command'
TEST_METADATA_FAILURE=1 expect_failure 'RPM metadata query failure'
TEST_IDENTITY_FAILURE=1 expect_failure 'RPM identity query fails after printing plausible values'
TEST_PAYLOAD_FAILURE=1 expect_failure 'RPM payload query fails after printing plausible paths'

printf 'files() {\n    files-find-systemd-user\n}\n' >"$fixture/repo/demo/Staplerfile"
TEST_UNIT_PATH=/usr/lib/systemd/user/demo.service verify
TEST_UNIT_PATH=/usr/lib/systemd/system/demo.service expect_failure 'system unit cannot satisfy user unit helper'
grep -Fq 'files-find-systemd-user не добавил user unit-файл' "$fixture/output"
printf 'files() {\n    files-find-systemd\n}\n' >"$fixture/repo/demo/Staplerfile"
TEST_UNIT_PATH=/usr/lib/systemd/system/demo.service verify
TEST_UNIT_PATH=/usr/lib/systemd/user/demo.service expect_failure 'user unit cannot satisfy system unit helper'
grep -Fq 'files-find-systemd не добавил unit-файл' "$fixture/output"

# Check the actual metadata query, independently of a recipe's backup field.
# Either config or noreplace alone is insufficient; flags on another path
# must not satisfy the Tailscale gate.
TEST_PACKAGE=tailscale verify
TEST_PACKAGE=tailscale TEST_CONFIG_FLAGS=49 verify
for flags in 0 1 16 invalid; do
    TEST_PACKAGE=tailscale TEST_CONFIG_FLAGS="$flags" \
        expect_failure 'tailscaled defaults without config+noreplace'
    grep -Fq '/etc/default/tailscaled must have RPM config+noreplace flags' "$fixture/output"
done
TEST_PACKAGE=tailscale TEST_CONFIG_PRESENT=0 expect_failure 'missing tailscaled defaults metadata'
TEST_PACKAGE=tailscale TEST_CONFIG_METADATA_FAILURE=1 expect_failure 'RPM file flags query failure'

# The graphical-package gate runs against the actual artifact, while CLI-only
# packages above do not require graphical metadata or native desktop validators.
cat >"$fixture/repo/.github/tools/validate_appstream.py" <<'PY'
import os
import sys
from pathlib import Path

assert sys.argv[1:] == ["--rpm", "demo/demo.rpm", "demo"], sys.argv
Path(os.environ["TEST_APPSTREAM_MARKER"]).write_text("called", encoding="utf-8")
raise SystemExit(int(os.environ.get("TEST_APPSTREAM_FAILURE", "0")))
PY
printf "appstream_app_id='com.example.Demo'\n" >"$fixture/repo/demo/Staplerfile"
export TEST_APPSTREAM_MARKER="$fixture/appstream-called"
verify
[[ -f "$TEST_APPSTREAM_MARKER" ]]
TEST_APPSTREAM_FAILURE=1 expect_failure 'native AppStream or desktop payload gate failure'

echo 'OK: RPM metadata validates query status, ownership, modes, unit scopes, config flags and desktop integration'
