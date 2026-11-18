#!/bin/bash
# Exercise the real removal hooks with an offline systemd unit tree.
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'find "$test_root" -mindepth 1 -delete; rmdir "$test_root"' EXIT
real_systemctl="$(command -v systemctl)"

install -d "$test_root/bin"
cat >"$test_root/bin/systemctl" <<'EOF'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >>"$HAPP_TEST_CALLS"
[[ "${HAPP_TEST_SYSTEMD_FAILURE:-0}" == 0 ]] || exit 1
case "$1" in
--no-reload)
    shift
    exec "$HAPP_TEST_SYSTEMCTL" --root "$HAPP_TEST_ROOT" --no-reload "$@"
    ;;
stop | daemon-reload)
    # No manager is running in the fixture; record these actions only.
    exit 0
    ;;
*) echo "Unexpected systemctl call: $*" >&2; exit 1 ;;
esac
EOF
chmod 0755 "$test_root/bin/systemctl"
for command in update-mime-database update-desktop-database gtk-update-icon-cache; do
    printf '#!/bin/sh\nexit 0\n' >"$test_root/bin/$command"
    chmod 0755 "$test_root/bin/$command"
done

setup_case() {
    local case_root="$1"
    install -d "$case_root/usr/lib/systemd/system" "$case_root/run/systemd/system"
    cat >"$case_root/usr/lib/systemd/system/happd.service" <<'EOF'
[Unit]
Description=Happ lifecycle fixture
[Service]
ExecStart=/usr/bin/true
[Install]
WantedBy=multi-user.target
EOF
    "$real_systemctl" --root "$case_root" enable happd.service >/dev/null 2>&1
    for hook in preremove postremove; do
        sed "s|/run/systemd/system|${case_root}/run/systemd/system|g" \
            "$package_dir/$hook.sh" >"$case_root/$hook.sh"
    done
    : >"$case_root/calls"
}

run_hook() {
    local case_root="$1" hook="$2" count="$3"
    PATH="$test_root/bin:$PATH" HAPP_TEST_ROOT="$case_root" \
        HAPP_TEST_SYSTEMCTL="$real_systemctl" HAPP_TEST_CALLS="$case_root/calls" \
        bash "$case_root/$hook.sh" "$count"
}

removed="$test_root/removed"
setup_case "$removed"
enable_link="$removed/etc/systemd/system/multi-user.target.wants/happd.service"
[[ -L "$enable_link" ]]
run_hook "$removed" preremove 0
[[ ! -L "$enable_link" ]]
grep -Fxq -- '--no-reload disable happd.service' "$removed/calls"
grep -Fxq 'stop happd.service' "$removed/calls"
rm "$removed/usr/lib/systemd/system/happd.service"
run_hook "$removed" postremove 0
grep -Fxq 'daemon-reload' "$removed/calls"
[[ ! -L "$enable_link" ]]

for count in 1 2; do
    upgrading="$test_root/upgrade-$count"
    setup_case "$upgrading"
    run_hook "$upgrading" preremove "$count"
    [[ ! -s "$upgrading/calls" ]]
    [[ -L "$upgrading/etc/systemd/system/multi-user.target.wants/happd.service" ]]
    run_hook "$upgrading" postremove "$count"
    [[ "$(cat "$upgrading/calls")" == daemon-reload ]]
done

# A failed systemd operation must not prevent other removal hooks from running.
failed="$test_root/systemd-unavailable"
setup_case "$failed"
HAPP_TEST_SYSTEMD_FAILURE=1 run_hook "$failed" preremove 0
HAPP_TEST_SYSTEMD_FAILURE=1 run_hook "$failed" postremove 0 2>"$failed/warning"
grep -Fxq 'stop happd.service' "$failed/calls"
grep -Fq 'unit-файлы' "$failed/warning"

# Containers and chroots without a running systemd manager need no actions.
offline="$test_root/no-manager"
setup_case "$offline"
rmdir "$offline/run/systemd/system"
run_hook "$offline" preremove 0
run_hook "$offline" postremove 0
[[ ! -s "$offline/calls" ]]

echo 'OK: Happ disables its unit before removal and preserves services on upgrade'
