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
    local home="$1"
    shift
    : >"${temp_dir}/args"
    PARSEC_TEST_ARGS="${temp_dir}/args" \
        PARSEC_BINARY="${temp_dir}/parsecd" \
        PARSEC_CONFIG_HOME="$home" \
        bash "$wrapper" "$@"
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

# 3. A value the wrapper does not use itself is still the user's choice: it is
#    kept, and Parsec starts without any command-line override.
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

echo 'OK: Parsec immersive не перезаписывает пользовательскую настройку'
