#!/bin/bash
# Prepare a clean ALT build environment. GitHub jobs may reuse this image;
# each build and lifecycle transaction still starts a fresh container.

nivora_alt_container_engine() {
    local selected="${NIVORA_CONTAINER_ENGINE:-}"
    case "$selected" in
    '')
        # Stapler 0.2.0 needs UID/GID ranges unavailable inside the hosted
        # runner's rootless Podman namespace. Use its Docker daemon for CI;
        # retain the existing Podman-first choice for local installations.
        if [[ "${GITHUB_ACTIONS:-}" == true ]]; then
            selected=docker
        elif command -v podman >/dev/null 2>&1; then
            selected=podman
        else
            selected=docker
        fi
        ;;
    docker | podman) ;;
    *)
        echo 'ALT builder: NIVORA_CONTAINER_ENGINE must be docker or podman' >&2
        return 1
        ;;
    esac
    command -v "$selected" >/dev/null 2>&1 || {
        echo "ALT builder: selected container engine ${selected} is not installed" >&2
        return 1
    }
    if ! timeout --signal=TERM --kill-after=1s 30s "$selected" info >/dev/null 2>&1; then
        echo "ALT builder: selected container engine ${selected} is unavailable; check its service and access permissions" >&2
        return 1
    fi
    printf '%s\n' "$selected"
}

nivora_prepare_docker_config() {
    local destination="$1" original="${DOCKER_CONFIG:-${HOME}/.docker}"
    # Keep connection settings while excluding registry credentials and user
    # build configuration. The caller owns a private directory outside the
    # uploaded build context and removes it after the last engine command.
    python3 - "$original" "$destination" <<'PY'
import json
import shutil
import sys
from pathlib import Path

source, target = map(Path, sys.argv[1:])
try:
    config_file = source / "config.json"
    config = json.loads(config_file.read_text()) if config_file.exists() else {}
    if not isinstance(config, dict):
        raise ValueError("Docker config must be an object")
    # An anonymous entry also prevents Docker from autodetecting a personal
    # pass/secretservice credential store when auths is otherwise empty.
    isolated = {"auths": {"registry.altlinux.org": {}}}
    for key in ("currentContext", "HttpHeaders"):
        if key in config:
            isolated[key] = config[key]
    if (source / "contexts").exists():
        shutil.copytree(source / "contexts", target / "contexts")
    # The default context may use DOCKER_HOST + TLS with certificates read
    # from DOCKER_CONFIG. Explicit DOCKER_CERT_PATH remains inherited.
    for name in ("ca.pem", "cert.pem", "key.pem"):
        if (source / name).exists():
            shutil.copyfile(source / name, target / name)
            (target / name).chmod(0o600)
    (target / "config.json").write_text(json.dumps(isolated) + "\n")
    (target / "config.json").chmod(0o600)
except (OSError, ValueError):
    print("ALT builder: cannot isolate Docker connection configuration", file=sys.stderr)
    raise SystemExit(1)
PY
}

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
# Stapler installs build dependencies through plain apt-get in this image.
RUN printf '%s\n' 'Dir::Etc::sourcelist "/etc/apt/nivora-p11.list";' 'Dir::Etc::sourceparts "-";' \\
    >/etc/apt/apt.conf.d/99nivora-sources.conf
RUN bash /usr/local/lib/nivora/alt_apt_network.sh update \\
    && bash /usr/local/lib/nivora/alt_apt_network.sh run dist-upgrade -y \\
    && bash /usr/local/lib/nivora/alt_apt_network.sh run install -y ca-certificates stplr binutils python3
# Keep the selected sources effective after apt-conf and its dependencies were upgraded.
RUN test -s /etc/apt/nivora-p11.list \\
    && test "\$(apt-config shell LIST Dir::Etc::sourcelist)" = "LIST='/etc/apt/nivora-p11.list'" \\
    && test "\$(apt-config shell PARTS Dir::Etc::sourceparts)" = "PARTS='-'"
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
