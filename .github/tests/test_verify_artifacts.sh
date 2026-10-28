#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -r -- "$fixture"' EXIT
install -d "$fixture/repo/.github/tools" "$fixture/repo/demo" "$fixture/bin"
cp "$repo_root/.github/tools/verify_artifacts.sh" "$fixture/repo/.github/tools/"
touch "$fixture/repo/demo/Staplerfile" "$fixture/repo/demo/demo.rpm"

cat >"$fixture/bin/stplr-spec" <<'EOF'
#!/bin/bash
case "$4" in
name) echo demo ;;
version) echo 1 ;;
release) echo 1 ;;
architectures) echo amd64 ;;
*) exit 1 ;;
esac
EOF
cat >"$fixture/bin/rpm" <<'EOF'
#!/bin/bash
set -euo pipefail
case "$*" in
*'--queryformat %{NAME}'*) echo 'demo+stplr-default|0|1|alt1|x86_64' ;;
*'-qlp'*)
    printf '%s\n' '/opt/Kimi Code/kimi-code' /usr/bin/demo /usr/share/licenses/demo/LICENSE
    [[ -z "${TEST_UNIT_PATH:-}" ]] || printf '%s\n' "$TEST_UNIT_PATH"
    ;;
*'--queryformat [%{FILEMODES:octal}'*)
    [[ "${TEST_METADATA_FAILURE:-0}" != 1 ]] || exit 42
    printf '100644\t%s\t%s\t/opt/Kimi Code/resources/app file\n' \
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
    "$fixture/repo/.github/tools/verify_artifacts.sh" demo >"$fixture/output" 2>&1
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
grep -Fq 'user:root у /opt/Kimi Code/resources/app file' "$fixture/output"
TEST_FILE_GROUP=users expect_failure 'non-root group'
TEST_BINARY_MODE=100644 expect_failure 'non-executable command'
TEST_BINARY_MODE=104755 expect_failure 'setuid command'
TEST_METADATA_FAILURE=1 expect_failure 'RPM metadata query failure'

printf 'files() {\n    files-find-systemd-user\n}\n' >"$fixture/repo/demo/Staplerfile"
TEST_UNIT_PATH=/usr/lib/systemd/user/demo.service verify
TEST_UNIT_PATH=/usr/lib/systemd/system/demo.service expect_failure 'system unit cannot satisfy user unit helper'
grep -Fq 'files-find-systemd-user не добавил user unit-файл' "$fixture/output"
printf 'files() {\n    files-find-systemd\n}\n' >"$fixture/repo/demo/Staplerfile"
TEST_UNIT_PATH=/usr/lib/systemd/system/demo.service verify
TEST_UNIT_PATH=/usr/lib/systemd/user/demo.service expect_failure 'user unit cannot satisfy system unit helper'
grep -Fq 'files-find-systemd не добавил unit-файл' "$fixture/output"

echo 'OK: RPM metadata preserves spaces, validates unit scopes and rejects unsafe ownership and modes'
