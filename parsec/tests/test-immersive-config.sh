#!/bin/bash
# The wrapper may seed client_immersive once, but must never overrule a value
# the user already chose, and must not rewrite the config file for nothing.
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wrapper="${package_dir}/parsecd-wrapper"
temp_dir="$(mktemp -d)"
cleanup() {
    find "$temp_dir" -mindepth 1 -delete
    rmdir "$temp_dir"
}
trap cleanup EXIT

cat >"${temp_dir}/parsecd" <<'STUB'
#!/bin/bash
(("$#" == 0)) || printf '%s\n' "$@" >>"$PARSEC_TEST_ARGS"
STUB
chmod 0755 "${temp_dir}/parsecd"

run_wrapper() {
    local profile_dir="$1"
    shift
    : >"${temp_dir}/args"
    PARSEC_TEST_ARGS="${temp_dir}/args" \
        PARSEC_BINARY="${temp_dir}/parsecd" \
        PARSEC_CONFIG_HOME="$profile_dir" \
        PATH="${PARSEC_TEST_PATH:-$PATH}" \
        bash "$wrapper" "$@"
}

run_unchanged_profile() {
    local profile_dir="$1" snapshot
    shift
    snapshot="$(mktemp -d "${temp_dir}/snapshot.XXXXXX")"
    cp -a "$profile_dir/." "$snapshot/"
    run_wrapper "$profile_dir" "$@"
    diff -r "$snapshot" "$profile_dir"
}

# 1. Nothing configured yet: the wrapper seeds the immersive default.
fresh="${temp_dir}/fresh"
run_wrapper "$fresh"
grep -Fxq 'client_immersive=2' "${temp_dir}/args"
grep -Fq '"client_immersive"' "${fresh}/config.json"

# 2. An explicit 1 is honoured, not replaced by the wrapper's own default.
chosen="${temp_dir}/chosen"
mkdir -p "$chosen"
printf '%s\n' '["notice", {"client_immersive": {"value": 1}}]' \
    >"${chosen}/config.json"
before="$(sha256sum "${chosen}/config.json" | cut -d' ' -f1)"
run_wrapper "$chosen"
grep -Fxq 'client_immersive=1' "${temp_dir}/args"
after="$(sha256sum "${chosen}/config.json" | cut -d' ' -f1)"
[[ "$before" == "$after" ]] || {
    echo 'Обёртка переписала конфиг, в котором ничего не менялось' >&2
    exit 1
}

# 3. A saved zero remains the effective value; the wrapper does not enable
#    immersive mode or rewrite the user's profile.
disabled="${temp_dir}/disabled"
mkdir -p "$disabled"
printf '%s\n' '["notice", {"client_immersive": {"value": 0}}]' \
    >"${disabled}/config.json"
before="$(sha256sum "${disabled}/config.json" | cut -d' ' -f1)"
run_wrapper "$disabled"
grep -Fxq 'client_immersive=0' "${temp_dir}/args"
after="$(sha256sum "${disabled}/config.json" | cut -d' ' -f1)"
[[ "$before" == "$after" ]] || {
    echo 'Обёртка переписала пользовательское значение client_immersive' >&2
    exit 1
}

# 4. PARSEC_NIVORA_IMMERSIVE=0 disables the whole behaviour.
opted_out="${temp_dir}/opted-out"
PARSEC_NIVORA_IMMERSIVE=0 run_wrapper "$opted_out"
[[ ! -s "${temp_dir}/args" ]] || {
    echo 'Отключённый immersive всё равно передал аргумент' >&2
    exit 1
}
[[ ! -e "${opted_out}/config.json" ]] || {
    echo 'Отключённый immersive всё равно создал конфиг' >&2
    exit 1
}

# 5. A legacy profile is still the user's choice; do not create JSON=2 over
#    an existing TXT=0, or migrate any other legacy settings implicitly.
legacy="${temp_dir}/legacy"
mkdir -p "$legacy"
printf 'client_immersive=0\nclient_decoder_software=1\n' >"${legacy}/config.txt"
run_unchanged_profile "$legacy"
grep -Fxq 'client_immersive=0' "${temp_dir}/args"

# A JSON profile without this key must consult legacy TXT before seeding.
printf '%s\n' '["notice", {"client_vsync": {"value": 1}}]' >"${legacy}/config.json"
run_unchanged_profile "$legacy"
grep -Fxq 'client_immersive=0' "${temp_dir}/args"

# An explicit JSON setting takes precedence when both formats have a value.
printf '%s\n' '["notice", {"client_immersive": {"value": 1}}]' >"${legacy}/config.json"
run_unchanged_profile "$legacy"
grep -Fxq 'client_immersive=1' "${temp_dir}/args"

# 6. Invalid/unknown JSON is not permission to overwrite a profile or create
#    a competing TXT default. Keep even an empty file byte for byte.
json_cases=(
    ''
    '{invalid json'
    '[]'
    '["notice", []]'
    '"unknown future format"'
    '["notice", {}, {"future": true}]'
    '{"client_immersive": {"unknown": 0}}'
    '{"client_immersive": {"value": "custom"}}'
    '{"client_immersive": {"value": 1.5}}'
)
for index in "${!json_cases[@]}"; do
    unknown="${temp_dir}/unknown-${index}"
    mkdir -p "$unknown"
    printf '%s' "${json_cases[$index]}" >"${unknown}/config.json"
    printf 'client_immersive=0\n' >"${unknown}/config.txt"
    run_unchanged_profile "$unknown"
    [[ ! -s "${temp_dir}/args" ]]
done
unreadable="${temp_dir}/unreadable"
mkdir -p "${unreadable}/config.json"
run_unchanged_profile "$unreadable"
[[ ! -s "${temp_dir}/args" ]]

# 7. Python is optional in the RPM dependencies. Its absence must not turn a
#    saved JSON choice into an unread profile overridden by a new TXT file.
no_python="${temp_dir}/no-python-bin"
mkdir -p "$no_python"
for command in bash mkdir; do
    ln -s "$(command -v "$command")" "${no_python}/${command}"
done
PARSEC_TEST_PATH="$no_python" run_unchanged_profile "$chosen"
[[ ! -s "${temp_dir}/args" ]]

legacy_no_python="${temp_dir}/legacy-no-python"
mkdir -p "$legacy_no_python"
printf 'client_immersive=0\n' >"${legacy_no_python}/config.txt"
PARSEC_TEST_PATH="$no_python" run_unchanged_profile "$legacy_no_python"
grep -Fxq 'client_immersive=0' "${temp_dir}/args"

fresh_no_python="${temp_dir}/fresh-no-python"
PARSEC_TEST_PATH="$no_python" run_wrapper "$fresh_no_python"
grep -Fxq 'client_immersive=2' "${temp_dir}/args"
grep -Fxq 'client_immersive=2' "${fresh_no_python}/config.txt"
[[ ! -e "${fresh_no_python}/config.json" ]]

# 8. Explicit launch options bypass all profile reads/writes, preserve spaces
#    in separate arguments and do not seed a different default for next time.
explicit="${temp_dir}/explicit"
run_wrapper "$explicit" 'client_immersive=0:peer_id=123' 'argument with spaces'
[[ ! -e "$explicit" ]]
printf '%s\n' 'client_immersive=0:peer_id=123' 'argument with spaces' \
    >"${temp_dir}/expected-args"
cmp "${temp_dir}/expected-args" "${temp_dir}/args"
run_unchanged_profile "$chosen" 'client_immersive=0:peer_id=123' 'argument with spaces'
cmp "${temp_dir}/expected-args" "${temp_dir}/args"

# 9. An unfamiliar last legacy assignment must not be replaced by an earlier
#    numeric value, nor by a numeric prefix parsed from something like 0oops.
legacy_unknown="${temp_dir}/legacy-unknown"
mkdir -p "$legacy_unknown"
printf 'client_immersive=1\nclient_immersive=0oops\n' >"${legacy_unknown}/config.txt"
run_unchanged_profile "$legacy_unknown"
[[ ! -s "${temp_dir}/args" ]]

# 10. A validated profile with no choice may receive the default. Retain all
#     unrelated settings, file permissions and any pre-existing .tmp file.
seed_json="${temp_dir}/seed-json"
mkdir -p "$seed_json"
printf '%s\n' '["notice", {"client_vsync": {"value": 0}}]' >"${seed_json}/config.json"
chmod 0600 "${seed_json}/config.json"
printf 'belongs to another process\n' >"${seed_json}/config.json.tmp"
run_wrapper "$seed_json"
grep -Fxq 'client_immersive=2' "${temp_dir}/args"
[[ "$(stat -c %a "${seed_json}/config.json")" == 600 ]]
[[ "$(cat "${seed_json}/config.json.tmp")" == 'belongs to another process' ]]
[[ -z "$(find "$seed_json" -name '.config.json.*.tmp' -print -quit)" ]]
python3 - "${seed_json}/config.json" <<'PY'
import json
import sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text())
assert data == ["notice", {
    "client_vsync": {"value": 0}, "client_immersive": {"value": 2},
}]
PY
run_unchanged_profile "$seed_json"

seed_txt="${temp_dir}/seed-txt"
mkdir -p "$seed_txt"
printf '# existing configuration\nclient_vsync=0\n' >"${seed_txt}/config.txt"
run_wrapper "$seed_txt"
grep -Fxq 'client_immersive=2' "${temp_dir}/args"
printf '# existing configuration\nclient_vsync=0\n\nclient_immersive=2\n' \
    >"${temp_dir}/expected-txt"
cmp "${temp_dir}/expected-txt" "${seed_txt}/config.txt"
[[ ! -e "${seed_txt}/config.json" ]]
run_unchanged_profile "$seed_txt"

echo 'OK: Parsec preserves JSON/TXT choices, launch overrides and profile contents'
