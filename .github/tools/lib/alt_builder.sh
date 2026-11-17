#!/bin/bash
# Prepare a clean ALT build environment. GitHub jobs may reuse this image;
# each build and lifecycle transaction still starts a fresh container.

nivora_prepare_alt_builder() {
    local engine="$1" branch="$2" base_image="$3" context_dir="$4" image_tag="$5"
    local helper_dir cache_key cache_tag='' pulled=0 attempt
    helper_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    [[ -s "${context_dir}/stplr" ]] || {
        echo 'ALT builder: prepared Stapler binary is missing' >&2
        return 1
    }
    install -m 0644 "${helper_dir}/alt_apt_network.sh" \
        "${context_dir}/alt_apt_network.sh" || return 1
    cat >"${context_dir}/Containerfile" <<EOF
FROM ${base_image}
COPY alt_apt_network.sh /usr/local/lib/nivora/alt_apt_network.sh
RUN bash /usr/local/lib/nivora/alt_apt_network.sh update \\
    && bash /usr/local/lib/nivora/alt_apt_network.sh run dist-upgrade -y \\
    && bash /usr/local/lib/nivora/alt_apt_network.sh run install -y ca-certificates stplr binutils python3
COPY stplr /usr/local/bin/stplr
RUN chmod 0755 /usr/local/bin/stplr && /usr/local/bin/stplr version
EOF

    # Reuse is restricted to one GitHub job attempt. Local invocations keep
    # their existing disposable-image behaviour, with no persistent cache.
    # Hash file contents only: the callers use different temporary paths.
    if [[ "${GITHUB_ACTIONS:-}" == true && -n "${GITHUB_JOB:-}" &&
        "${GITHUB_RUN_ID:-}" =~ ^[1-9][0-9]*$ &&
        "${GITHUB_RUN_ATTEMPT:-}" =~ ^[1-9][0-9]*$ ]]; then
        cache_key="$(
            {
                printf '%s\n' "${GITHUB_REPOSITORY:-}" "$GITHUB_RUN_ID" \
                    "$GITHUB_RUN_ATTEMPT" "$GITHUB_JOB" "$branch"
                sha256sum "${context_dir}/Containerfile" \
                    "${context_dir}/alt_apt_network.sh" "${context_dir}/stplr" |
                    cut -d ' ' -f 1
            } | sha256sum | cut -d ' ' -f 1
        )"
        cache_tag="nivora-prepared-alt-${branch}:${cache_key}"
        if "$engine" image inspect "$cache_tag" >/dev/null 2>&1; then
            echo "ALT builder: reuse prepared ${branch} environment for this job" >&2
            "$engine" tag "$cache_tag" "$image_tag" || return 1
            return 0
        fi
    fi

    for attempt in 1 2 3; do
        if "$engine" pull "$base_image"; then
            pulled=1
            break
        fi
        sleep "$((attempt * 5))"
    done
    [[ "$pulled" -eq 1 ]] || return 1
    "$engine" build -t "$image_tag" -f "${context_dir}/Containerfile" \
        "$context_dir" || return 1
    if [[ -n "$cache_tag" ]]; then
        "$engine" tag "$image_tag" "$cache_tag" || return 1
    fi
}
