#!/bin/bash
# Bounded ALT apt-rpm access for disposable official ALT builder containers.
set -euo pipefail

readonly apt_get_bin="${NIVORA_ALT_APT_GET:-apt-get}"
readonly timeout_bin="${NIVORA_ALT_APT_TIMEOUT_BIN:-timeout}"
readonly apt_root="${NIVORA_ALT_APT_ROOT:-/etc/apt}"
readonly apt_lists="${NIVORA_ALT_APT_LISTS:-/var/lib/apt/lists}"
readonly active_source="${NIVORA_ALT_APT_ACTIVE_SOURCE:-${apt_root}/sources.list.d/alt.list}"
readonly apt_retries="${NIVORA_ALT_APT_RETRIES:-0}"
readonly connect_timeout="${NIVORA_ALT_APT_CONNECT_TIMEOUT_SECONDS:-10}"
readonly io_timeout="${NIVORA_ALT_APT_IO_TIMEOUT_SECONDS:-15}"
readonly attempt_timeout="${NIVORA_ALT_APT_ATTEMPT_TIMEOUT_SECONDS:-30}"
readonly total_timeout="${NIVORA_ALT_APT_TOTAL_TIMEOUT_SECONDS:-210}"
readonly command_timeout="${NIVORA_ALT_APT_COMMAND_TIMEOUT_SECONDS:-300}"

fail() {
    echo "ALT apt: $*" >&2
    exit 1
}

for value_name in apt_retries connect_timeout io_timeout attempt_timeout total_timeout command_timeout; do
    value="${!value_name}"
    [[ "$value" =~ ^[0-9]+$ ]] || fail "${value_name} must be a non-negative integer"
done
(( connect_timeout > 0 && io_timeout > 0 && attempt_timeout > 0 && total_timeout > 0 && command_timeout > 0 )) ||
    fail 'timeouts must be positive'

apt_run() {
    "$timeout_bin" --signal=TERM --kill-after=1s "${command_timeout}s" \
        "$apt_get_bin" \
        -o "Dir::Etc::sourcelist=${active_source}" \
        -o Dir::Etc::sourceparts=- \
        -o "Acquire::Retries=${apt_retries}" \
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

        source_url="${fields[2]}"
        source_line="${fields[*]}"
        if [[ -z "${lines_by_url[$source_url]+set}" ]]; then
            candidate_urls+=("$source_url")
            lines_by_url["$source_url"]=''
        fi
        lines_by_url["$source_url"]+="${source_line}"$'\n'
    done <"$list_file"
}

update_indexes() {
    local source_dir="${apt_root}/sources.list.d"
    local source_file url candidate_url source_line remaining started
    local tmp_dir log_file candidate_file attempt=0 active_count
    local -a candidate_urls=() expanded_urls=() parts
    declare -A lines_by_url=() seen_url=()

    [[ -f "$active_source" ]] || fail "active source list is missing: ${active_source}"
    [[ -d "$source_dir" ]] || fail "source directory is missing: ${source_dir}"
    command -v "$apt_get_bin" >/dev/null 2>&1 || fail "missing ${apt_get_bin}"
    command -v "$timeout_bin" >/dev/null 2>&1 || fail "missing ${timeout_bin}"

    # Prefer only active primary sources, then the image's documented
    # alternatives (including commented entries in the primary list).
    collect_source_lines "$active_source" active
    active_count="${#candidate_urls[@]}"
    (( active_count > 0 )) || fail 'active ALT source list has no HTTP(S) RPM entries'
    collect_source_lines "$active_source" commented
    shopt -s nullglob
    for source_file in "${source_dir}"/*.list; do
        [[ "$source_file" == "$active_source" ]] && continue
        collect_source_lines "$source_file"
    done
    if [[ -f "${apt_root}/sources.list" ]]; then
        collect_source_lines "${apt_root}/sources.list"
    fi

    # Use HTTP repositories from the official image configuration only. Fresh
    # ALT base images may have no CA bundle yet, so synthesizing HTTPS URLs
    # would fail TLS before the first apt install can add ca-certificates.
    for url in "${candidate_urls[@]}"; do
        expanded_urls+=("$url")
    done

    tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/nivora-alt-apt.XXXXXX")"
    started="$SECONDS"
    for candidate_url in "${expanded_urls[@]}"; do
        [[ -n "${seen_url[$candidate_url]+set}" ]] && continue
        seen_url["$candidate_url"]=1
        remaining=$((total_timeout - (SECONDS - started)))
        (( remaining > 0 )) || break
        ((attempt += 1))
        if (( remaining < attempt_timeout )); then
            per_attempt="$remaining"
        else
            per_attempt="$attempt_timeout"
        fi

        candidate_file="${tmp_dir}/sources-${attempt}.list"
        log_file="${tmp_dir}/apt-${attempt}.log"
        : >"$candidate_file"
        while IFS= read -r source_line; do
            [[ -n "$source_line" ]] || continue
            read -r -a parts <<<"$source_line"
            parts[2]="$candidate_url"
            printf '%s\n' "${parts[*]}" >>"$candidate_file"
        done <<<"${lines_by_url[$candidate_url]:-}"

        [[ -s "$candidate_file" ]] || continue

        echo "ALT apt: update ${candidate_url} (attempt ${attempt}, ${per_attempt}s cap)" >&2
        clean_lists
        if "$timeout_bin" --signal=TERM --kill-after=1s "${per_attempt}s" \
            "$apt_get_bin" \
            -o "Dir::Etc::sourcelist=${candidate_file}" \
            -o Dir::Etc::sourceparts=- \
            -o "Acquire::Retries=${apt_retries}" \
            -o "Acquire::http::Timeout=${io_timeout}" \
            -o "Acquire::http::ConnectTimeout=${connect_timeout}" \
            update >"$log_file" 2>&1 &&
            ! grep -Eiq 'failed to fetch|some index files failed|signature.*(fail|error|could not|couldn.t|invalid)|no_pubkey|not signed' "$log_file"; then
            cat "$log_file"
            install -m 0644 "$candidate_file" "${active_source}.nivora-tmp"
            mv -f -- "${active_source}.nivora-tmp" "$active_source"
            echo "ALT apt: selected ${candidate_url}" >&2
            cleanup_tmp
            return 0
        fi
        cat "$log_file" >&2
        clean_lists
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
