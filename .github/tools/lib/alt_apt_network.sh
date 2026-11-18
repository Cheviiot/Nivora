#!/bin/bash
# Bounded ALT apt-rpm access for disposable official ALT builder containers.
set -euo pipefail

readonly apt_get_bin="${NIVORA_ALT_APT_GET:-apt-get}"
readonly timeout_bin="${NIVORA_ALT_APT_TIMEOUT_BIN:-timeout}"
readonly apt_root="${NIVORA_ALT_APT_ROOT:-/etc/apt}"
readonly apt_lists="${NIVORA_ALT_APT_LISTS:-/var/lib/apt/lists}"
readonly active_source="${NIVORA_ALT_APT_ACTIVE_SOURCE:-${apt_root}/sources.list.d/alt.list}"
readonly selected_source="${apt_root}/nivora-p11.list"
# Beltelecom carries the signed x86 p11 repository in Minsk.
readonly belarus_mirror='http://mirror.datacenter.by/pub/ALTLinux'
readonly apt_retries="${NIVORA_ALT_APT_RETRIES:-0}"
readonly command_retries="${NIVORA_ALT_APT_COMMAND_RETRIES:-2}"
readonly connect_timeout="${NIVORA_ALT_APT_CONNECT_TIMEOUT_SECONDS:-10}"
readonly io_timeout="${NIVORA_ALT_APT_IO_TIMEOUT_SECONDS:-15}"
readonly attempt_timeout="${NIVORA_ALT_APT_ATTEMPT_TIMEOUT_SECONDS:-30}"
# apt-rpm downloads the three x86 branch indexes serially on a cold builder.
readonly belarus_timeout="${NIVORA_ALT_APT_ATTEMPT_TIMEOUT_SECONDS:-60}"
readonly total_timeout="${NIVORA_ALT_APT_TOTAL_TIMEOUT_SECONDS:-210}"
readonly command_timeout="${NIVORA_ALT_APT_COMMAND_TIMEOUT_SECONDS:-300}"

fail() {
    echo "ALT apt: $*" >&2
    exit 1
}

for value_name in apt_retries command_retries connect_timeout io_timeout attempt_timeout total_timeout command_timeout; do
    value="${!value_name}"
    [[ "$value" =~ ^[0-9]+$ ]] || fail "${value_name} must be a non-negative integer"
done
(( connect_timeout > 0 && io_timeout > 0 && attempt_timeout > 0 && total_timeout > 0 && command_timeout > 0 )) ||
    fail 'timeouts must be positive'

apt_run() {
    # apt-rpm retries transient archive downloads before the RPM transaction.
    # Keep one apt-get invocation and one deadline; never rerun package hooks
    # after a failed install, upgrade or removal.
    local source_list="$active_source"
    if [[ -s "$selected_source" ]]; then source_list="$selected_source"; fi
    "$timeout_bin" --signal=TERM --kill-after=1s "${command_timeout}s" \
        "$apt_get_bin" \
        -o "Dir::Etc::sourcelist=${source_list}" \
        -o Dir::Etc::sourceparts=- \
        -o "Acquire::Retries=${command_retries}" \
        -o "Acquire::http::Timeout=${io_timeout}" \
        -o "Acquire::http::ConnectTimeout=${connect_timeout}" \
        "$@"
}

clean_lists() {
    [[ -n "$apt_lists" && "$apt_lists" != / ]] || fail 'unsafe apt lists path'
    mkdir -p "$apt_lists"
    find "$apt_lists" -mindepth 1 -delete
    mkdir -p "${apt_lists}/partial"
}

cleanup_tmp() {
    if [[ -n "${tmp_dir:-}" && -d "$tmp_dir" ]]; then
        find "$tmp_dir" -mindepth 1 -delete
        rmdir -- "$tmp_dir"
    fi
}

trim_line() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

collect_source_lines() {
    local list_file="$1" mode="${2:-all}" line content source_url source_line commented
    local -a fields
    while IFS= read -r line || [[ -n "$line" ]]; do
        content="$(trim_line "$line")"
        commented=0
        if [[ "$content" == \#* ]]; then
            commented=1
            content="$(trim_line "${content#\#}")"
        fi
        [[ "$mode" != active || "$commented" == 0 ]] || continue
        [[ "$mode" != commented || "$commented" == 1 ]] || continue
        [[ "$content" == rpm\ * ]] || continue
        read -r -a fields <<<"$content"
        ((${#fields[@]} >= 5)) || continue
        [[ "${fields[1]}" =~ ^\[[^]]+\]$ ]] || continue
        [[ "${fields[2]}" =~ ^http://[^[:space:]]+$ ]] || continue

        source_url="${fields[2]%/}"
        if [[ "$mode" == active ]]; then
            active_urls["$source_url"]=1
        elif [[ -n "${active_urls[$source_url]+set}" ]]; then
            # A commented source must not enable extra architectures on the active URL.
            continue
        fi
        fields[2]="$source_url"
        source_line="${fields[*]}"
        if [[ -z "${lines_by_url[$source_url]+set}" ]]; then
            candidate_urls+=("$source_url")
            lines_by_url["$source_url"]=''
        fi
        lines_by_url["$source_url"]+="${source_line}"$'\n'
    done <"$list_file"
}

# Preserve every active architecture, component and signing key from the image.
# Skip Minsk if it cannot serve the full set (in particular, aarch64).
belarus_p11_sources() {
    local url
    for url in "${candidate_urls[@]}"; do
        printf '%s' "${lines_by_url[$url]}"
    done | awk -v mirror="$belarus_mirror" '
        $2 != "[p11]" || $4 !~ /^p11\/branch\/(x86_64|x86_64-i586|i586|noarch)$/ { exit 1 }
        { $3 = mirror; if (!seen[$0]++) print }
    '
}

update_indexes() {
    local source_dir="${apt_root}/sources.list.d"
    local source_file candidate_url by_sources remaining started
    local tmp_dir log_file candidate_file attempt=0 pass per_attempt
    local -a candidate_urls=()
    declare -A lines_by_url=() active_urls=() seen_url=()

    [[ -f "$active_source" ]] || fail "active source list is missing: ${active_source}"
    [[ -d "$source_dir" ]] || fail "source directory is missing: ${source_dir}"
    command -v "$apt_get_bin" >/dev/null 2>&1 || fail "missing ${apt_get_bin}"
    command -v "$timeout_bin" >/dev/null 2>&1 || fail "missing ${timeout_bin}"

    # Keep the image's original sources available even after a successful selection.
    collect_source_lines "$active_source" active
    (( ${#candidate_urls[@]} > 0 )) || fail 'active ALT source list has no HTTP RPM entries'
    by_sources="$(belarus_p11_sources)" || by_sources=''
    collect_source_lines "$active_source" commented
    shopt -s nullglob
    for source_file in "${source_dir}"/*.list; do
        [[ "$source_file" == "$active_source" ]] && continue
        collect_source_lines "$source_file"
    done
    if [[ -f "${apt_root}/sources.list" ]]; then
        collect_source_lines "${apt_root}/sources.list"
    fi

    # A clean base image can use HTTP before ca-certificates is installed.
    if [[ -n "$by_sources" ]]; then
        candidate_urls=("$belarus_mirror" "${candidate_urls[@]}")
        lines_by_url["$belarus_mirror"]="$by_sources"
    fi

    tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/nivora-alt-apt.XXXXXX")"
    started="$SECONDS"
    # A mirror can briefly serve inconsistent indexes during synchronization.
    # Retry the same official candidates once, without resetting the deadline.
    for pass in 1 2; do
        seen_url=()
        for candidate_url in "${candidate_urls[@]}"; do
            [[ "$candidate_url" != "$belarus_mirror" || -n "$by_sources" ]] || continue
            [[ -n "${seen_url[$candidate_url]+set}" ]] && continue
            seen_url["$candidate_url"]=1
            remaining=$((total_timeout - (SECONDS - started)))
            (( remaining > 0 )) || break 2
            ((attempt += 1))
            per_attempt="$attempt_timeout"
            if [[ "$candidate_url" == "$belarus_mirror" ]]; then per_attempt="$belarus_timeout"; fi
            if (( remaining < per_attempt )); then
                per_attempt="$remaining"
            fi

            candidate_file="${tmp_dir}/sources-${attempt}.list"
            log_file="${tmp_dir}/apt-${attempt}.log"
            printf '%s\n' "${lines_by_url[$candidate_url]%$'\n'}" >"$candidate_file"

            echo "ALT apt: update ${candidate_url} (pass ${pass}/2, attempt ${attempt}, ${per_attempt}s cap)" >&2
            clean_lists
            if "$timeout_bin" --signal=TERM --kill-after=1s "${per_attempt}s" \
                "$apt_get_bin" \
                -o "Dir::Etc::sourcelist=${candidate_file}" \
                -o Dir::Etc::sourceparts=- \
                -o "Acquire::Retries=${apt_retries}" \
                -o "Acquire::http::Timeout=${io_timeout}" \
                -o "Acquire::http::ConnectTimeout=${connect_timeout}" \
                update >"$log_file" 2>&1 &&
                ! grep -Eiq 'failed to fetch|some index files failed|(checksum|hash([[:space:]]+sum)?|size)[[:space:]]+mismatch|signature.*(fail|error|could not|couldn.t|invalid)|no_pubkey|not signed' "$log_file"; then
                cat "$log_file"
                install -m 0644 "$candidate_file" "${selected_source}.tmp"
                mv -f -- "${selected_source}.tmp" "$selected_source"
                echo "ALT apt: selected ${candidate_url}" >&2
                cleanup_tmp
                return 0
            fi
            cat "$log_file" >&2
            clean_lists
        done
    done

    cleanup_tmp
    fail "all configured mirrors failed within ${total_timeout}s total (${attempt} attempts)"
}

case "${1:-}" in
update)
    (($# == 1)) || fail 'usage: alt_apt_network.sh update | run <apt-get args...>'
    update_indexes
    ;;
run)
    shift
    (($# > 0)) || fail 'usage: alt_apt_network.sh run <apt-get args...>'
    [[ -f "$active_source" ]] || fail "active source list is missing: ${active_source}"
    apt_run "$@"
    ;;
*)
    fail 'usage: alt_apt_network.sh update | run <apt-get args...>'
    ;;
esac
