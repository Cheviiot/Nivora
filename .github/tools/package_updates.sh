#!/bin/bash
set -euo pipefail

readonly -a PACKAGES=(
    anidesk
    balena-etcher
    chatgpt
    claude
    distroshelf
    github-desktop
    happ
    nivora-cli
    parsec
    pineconemc
    tailscale
    telegram
    ventoy
    vesktop
    vintner
    yandex-music
)

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"

die() {
    echo "package_updates: $*" >&2
    exit 1
}

require_package() {
    local requested="$1"
    local package
    for package in "${PACKAGES[@]}"; do
        [[ "$package" == "$requested" ]] && return 0
    done
    die "unknown package: ${requested}"
}

current_version() {
    stplr-spec get-field --path "${repo_root}/$1/Staplerfile" version
}

github_json() {
    local url="$1"
    local -a headers=(
        -H 'Accept: application/vnd.github+json'
        -H 'X-GitHub-Api-Version: 2022-11-28'
    )
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        headers+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
    fi
    curl --retry 3 --retry-delay 2 --retry-all-errors \
        --connect-timeout 30 --max-time 120 -fsSL "${headers[@]}" "$url"
}

git_latest_stable_tag() {
    local repository="$1"
    local attempt tag=''

    for attempt in 1 2 3; do
        tag="$(
            GIT_TERMINAL_PROMPT=0 timeout 60s \
                git ls-remote --tags --refs "https://github.com/${repository}.git" 'refs/tags/v*' |
                awk '{sub("refs/tags/", "", $2); print $2}' |
                grep -Eiv '(^|[-_.])(alpha|beta|rc|pre|preview)([-_.0-9]|$)' |
                sort -V |
                tail -1
        )" || tag=''
        if [[ -n "$tag" ]]; then
            printf '%s\n' "$tag"
            return 0
        fi
        sleep "$((attempt * 2))"
    done

    return 1
}

github_latest_release() {
    local repository="$1"
    local tag=''
    tag="$(
        github_json "https://api.github.com/repos/${repository}/releases?per_page=30" |
            jq -r '
                .[]
                | select(.draft == false and .prerelease == false)
                | .tag_name
                | select(test("[0-9]+\\.[0-9]"))
                | select(test("(?:^|[-_.])(alpha|beta|rc|pre|preview)(?:[-_.0-9]|$)"; "i") | not)
            ' 2>/dev/null |
            sort -V |
            tail -1
    )" || tag=''

    if [[ -z "$tag" ]]; then
        tag="$(git_latest_stable_tag "$repository")" || tag=''
    fi

    [[ -n "$tag" ]] || {
        echo "package_updates: cannot determine latest release for ${repository}" >&2
        return 1
    }
    printf '%s\n' "${tag#v}"
}

version_is_newer() {
    local candidate="$1"
    local baseline="$2"
    local highest candidate_base baseline_base
    local prerelease_pattern='[-_.](alpha|beta|rc|pre|preview)([-_.]?[0-9].*)?$'
    [[ "$candidate" != "$baseline" ]] || return 1

    candidate_base="$(sed -E "s/${prerelease_pattern}//I" <<<"$candidate")"
    baseline_base="$(sed -E "s/${prerelease_pattern}//I" <<<"$baseline")"
    if [[ "$candidate_base" == "$baseline_base" ]]; then
        if [[ "$candidate" =~ $prerelease_pattern ]] &&
            [[ ! "$baseline" =~ $prerelease_pattern ]]; then
            return 1
        fi
        if [[ ! "$candidate" =~ $prerelease_pattern ]] &&
            [[ "$baseline" =~ $prerelease_pattern ]]; then
            return 0
        fi
    fi

    highest="$(printf '%s\n%s\n' "$candidate" "$baseline" | sort -V | tail -1)"
    [[ "$highest" == "$candidate" ]]
}

is_mutable_source_package() {
    case "$1" in
    chatgpt | parsec) return 0 ;;
    *) return 1 ;;
    esac
}

http_etag_fingerprint() {
    local url="$1"
    local headers etag
    headers="$(
        curl --retry 3 --retry-delay 2 --retry-all-errors \
            --connect-timeout 30 --max-time 120 -fsSIL "$url"
    )" || return
    etag="$(
        awk '
            tolower($1) == "etag:" {
                value = $2
                gsub(/\r/, "", value)
                gsub(/"/, "", value)
            }
            END { if (value != "") print value }
        ' <<<"$headers"
    )"
    [[ -n "$etag" ]] || {
        echo "package_updates: upstream did not return ETag for ${url}" >&2
        return 1
    }
    printf '%s' "$etag" | sha256sum | awk '{print $1}'
}

source_fingerprints() {
    local package="$1"
    local fingerprint
    require_package "$package"
    case "$package" in
    chatgpt)
        fingerprint="$(http_etag_fingerprint \
            'https://persistent.oaistatic.com/codex-app-prod/linux/deb/latest/chatgpt_amd64.deb')" || return
        printf 'source_fingerprint_amd64\t%s\n' "$fingerprint"
        fingerprint="$(http_etag_fingerprint \
            'https://persistent.oaistatic.com/codex-app-prod/linux/deb/latest/chatgpt_arm64.deb')" || return
        printf 'source_fingerprint_arm64\t%s\n' "$fingerprint"
        ;;
    parsec)
        fingerprint="$(http_etag_fingerprint \
            'https://builds.parsec.app/package/parsec-linux.deb')" || return
        printf 'source_fingerprint\t%s\n' "$fingerprint"
        ;;
    *) die "package has no mutable source fingerprint: ${package}" ;;
    esac
}

source_fingerprints_json() {
    local package="$1"
    local output
    output="$(source_fingerprints "$package")" || return
    jq -cRn '
        [inputs | select(length > 0) | split("\t") |
            {key: .[0], value: .[1]}]
        | from_entries
    ' <<<"$output"
}

fingerprints_match_recipe() {
    local package="$1"
    local fingerprints_json="$2"
    local field fingerprint stored count=0
    while IFS=$'\t' read -r field fingerprint; do
        [[ "$field" =~ ^source_fingerprint(_(amd64|arm64))?$ ]] || return 2
        [[ "$fingerprint" =~ ^[0-9a-f]{64}$ ]] || return 2
        stored="$(
            stplr-spec get-field \
                --path "${repo_root}/${package}/Staplerfile" "$field"
        )" || return 2
        [[ "$stored" =~ ^[0-9a-f]{64}$ ]] || return 2
        [[ "$stored" == "$fingerprint" ]] || return 1
        count=$((count + 1))
    done < <(jq -r 'to_entries[] | [.key, .value] | @tsv' <<<"$fingerprints_json")
    [[ "$count" -gt 0 ]] || return 2
}

source_fingerprint_drifted() {
    local package="$1"
    local field fingerprint stored fingerprints_output
    local drifted=1
    fingerprints_output="$(source_fingerprints "$package")" || return 2
    while IFS=$'\t' read -r field fingerprint; do
        [[ "$fingerprint" =~ ^[0-9a-f]{64}$ ]] || return 2
        stored="$(
            stplr-spec get-field \
                --path "${repo_root}/${package}/Staplerfile" "$field"
        )" || return 2
        [[ "$stored" =~ ^[0-9a-f]{64}$ ]] || return 2
        if [[ "$stored" != "$fingerprint" ]]; then
            drifted=0
        fi
    done <<<"$fingerprints_output"
    return "$drifted"
}

latest_anidesk() {
    local version
    version="$(
        GIT_TERMINAL_PROMPT=0 timeout 60s \
            git ls-remote --tags --refs https://github.com/theDesConnet/AniDesk.git 'refs/tags/v*' |
            awk '{sub("refs/tags/v", "", $2); print $2}' |
            sort -V |
            tail -1
    )"
    [[ -n "$version" ]] || die 'cannot determine latest AniDesk version'
    printf '%s\n' "$version"
}

latest_claude_desktop() {
    local version
    version="$(
        curl --retry 3 --retry-delay 2 --retry-all-errors \
            --connect-timeout 30 --max-time 120 -fsSL \
            'https://downloads.claude.ai/claude-desktop/apt/stable/dists/stable/main/binary-amd64/Packages' |
            awk '
                /^Package: claude-desktop$/ { selected = 1; next }
                /^Package: / { selected = 0 }
                selected && /^Version: / { print $2 }
            ' |
            sort -V |
            tail -1
    )"
    [[ -n "$version" ]] || die 'cannot determine latest Claude Desktop version'
    printf '%s\n' "$version"
}

latest_parsec() {
    local temp_dir version
    temp_dir="$(mktemp -d)"
    curl --retry 3 --retry-delay 2 --retry-all-errors \
        --connect-timeout 30 --max-time 300 -fsSL \
        -o "${temp_dir}/parsec.deb" \
        'https://builds.parsec.app/package/parsec-linux.deb'
    (
        cd "$temp_dir"
        ar x parsec.deb
        tar -xOf control.tar.* ./control
    ) >"${temp_dir}/control"
    version="$(awk '$1 == "Version:" {print $2; exit}' "${temp_dir}/control")"
    [[ -n "$version" ]] || die 'cannot determine latest Parsec version'
    printf '%s\n' "$version"
    find "$temp_dir" -mindepth 1 -delete
    rmdir "$temp_dir"
}

latest_tailscale() {
    local effective version
    effective="$(
        curl --retry 3 --retry-delay 2 --retry-all-errors \
            --connect-timeout 30 --max-time 120 -fsSLI -o /dev/null \
            -w '%{url_effective}' \
            'https://pkgs.tailscale.com/stable/tailscale_latest_amd64.tgz'
    )"
    version="$(sed -n 's/.*tailscale_\([0-9][0-9.]*\)_amd64\.tgz.*/\1/p' <<<"$effective")"
    [[ -n "$version" ]] || die 'cannot determine latest Tailscale version'
    printf '%s\n' "$version"
}

latest_yandex_music() {
    local version
    # resources/app-update.yml in the packaged app points electron-builder's
    # own updater at this feed; same generic-provider latest-*.yml format
    # used by electron-builder generic providers, just not on GitHub here.
    version="$(
        curl --retry 3 --retry-delay 2 --retry-all-errors \
            --connect-timeout 30 --max-time 120 -fsSL \
            'https://desktop.app.music.yandex.net/stable/latest-linux.yml' |
            awk -F': ' '$1 == "version" { print $2; exit }'
    )"
    [[ -n "$version" ]] || die 'cannot determine latest Yandex Music version'
    printf '%s\n' "$version"
}

latest_chatgpt() {
    local temp_dir version
    temp_dir="$(mktemp -d)"
    # The .deb is 300+ MB; a small Range request is enough to capture
    # debian-binary + control.tar.xz, which `ar` extracts fine even though
    # the overall archive is truncated (there's no manifest/latest.yml
    # published alongside it to check instead).
    curl --retry 3 --retry-delay 2 --retry-all-errors \
        --connect-timeout 30 --max-time 60 -fsSL \
        -r 0-2097151 \
        -o "${temp_dir}/chatgpt.deb" \
        'https://persistent.oaistatic.com/codex-app-prod/linux/deb/latest/chatgpt_amd64.deb'
    (cd "$temp_dir" && ar x chatgpt.deb debian-binary control.tar.xz)
    version="$(tar -xOf "${temp_dir}/control.tar.xz" ./control | awk '$1 == "Version:" {print $2; exit}')"
    [[ -n "$version" ]] || die 'cannot determine latest ChatGPT version'
    printf '%s\n' "$version"
    find "$temp_dir" -mindepth 1 -delete
    rmdir "$temp_dir"
}

latest_version() {
    case "$1" in
    anidesk) latest_anidesk ;;
    balena-etcher) github_latest_release balena-io/etcher ;;
    chatgpt) latest_chatgpt ;;
    claude) latest_claude_desktop ;;
    distroshelf) github_latest_release ranfdev/DistroShelf ;;
    github-desktop)
        github_latest_release desktop/desktop | sed 's/^release-//'
        ;;
    happ) github_latest_release Happ-proxy/happ-desktop ;;
    nivora-cli) current_version nivora-cli ;;
    parsec) latest_parsec ;;
    pineconemc) github_latest_release ElyPrismLauncher/Launcher ;;
    tailscale) latest_tailscale ;;
    telegram) github_latest_release telegramdesktop/tdesktop ;;
    ventoy) github_latest_release ventoy/Ventoy ;;
    vesktop) github_latest_release Vencord/Vesktop ;;
    vintner) github_latest_release Cheviiot/vintner ;;
    yandex-music) latest_yandex_music ;;
    *) die "unknown package: $1" ;;
    esac
}

check_package() {
    local package="$1"
    local current latest
    require_package "$package"
    current="$(current_version "$package")" || return
    latest="$(latest_version "$package")" || return
    printf '%s %s\n' "$current" "$latest"
}

check_all() {
    local package current latest status versions drift_status
    local unavailable=0
    local updates=0
    printf '%-24s %-24s %-24s %s\n' PACKAGE CURRENT LATEST STATUS
    for package in "${PACKAGES[@]}"; do
        if ! versions="$(check_package "$package")"; then
            printf '%-24s %-24s %-24s %s\n' "$package" unknown unknown unavailable
            [[ -z "${PACKAGE_UPDATE_FAILURES_FILE:-}" ]] ||
                printf '%s\n' "$package" >>"$PACKAGE_UPDATE_FAILURES_FILE"
            unavailable=1
            continue
        fi
        read -r current latest <<<"$versions"
        status=current
        if version_is_newer "$latest" "$current"; then
            status=update
            updates=1
        elif [[ "$current" == "$latest" ]] &&
            is_mutable_source_package "$package"; then
            if source_fingerprint_drifted "$package"; then
                status=checksum-drift
                updates=1
            else
                drift_status=$?
                if [[ "$drift_status" -gt 1 ]]; then
                    status=unavailable
                    unavailable=1
                    [[ -z "${PACKAGE_UPDATE_FAILURES_FILE:-}" ]] ||
                        printf '%s\n' "$package" >>"$PACKAGE_UPDATE_FAILURES_FILE"
                elif [[ -n "${PACKAGE_UPDATE_CURRENT_FILE:-}" ]]; then
                    printf '%s\n' "$package" >>"$PACKAGE_UPDATE_CURRENT_FILE"
                fi
            fi
        else
            [[ "$current" == "$latest" ]] || status=ahead
            if [[ -n "${PACKAGE_UPDATE_CURRENT_FILE:-}" ]]; then
                printf '%s\n' "$package" >>"$PACKAGE_UPDATE_CURRENT_FILE"
            fi
        fi
        printf '%-24s %-24s %-24s %s\n' "$package" "$current" "$latest" "$status"
    done
    [[ "$unavailable" -eq 0 ]] || return 1
    [[ "$updates" -eq 0 ]] || return 10
}

outdated_packages() {
    local package current latest versions drift_status needs_update
    local fingerprints_before fingerprints_after fingerprints_json
    for package in "${PACKAGES[@]}"; do
        fingerprints_json='{}'
        if is_mutable_source_package "$package"; then
            if ! fingerprints_before="$(source_fingerprints_json "$package")"; then
                echo "package_updates: source fingerprint failed for ${package}" >&2
                [[ -z "${PACKAGE_UPDATE_FAILURES_FILE:-}" ]] ||
                    printf '%s\n' "$package" >>"$PACKAGE_UPDATE_FAILURES_FILE"
                continue
            fi
        fi
        if ! versions="$(check_package "$package")"; then
            echo "package_updates: version detection failed for ${package}" >&2
            [[ -z "${PACKAGE_UPDATE_FAILURES_FILE:-}" ]] ||
                printf '%s\n' "$package" >>"$PACKAGE_UPDATE_FAILURES_FILE"
            continue
        fi
        if is_mutable_source_package "$package"; then
            if ! fingerprints_after="$(source_fingerprints_json "$package")"; then
                echo "package_updates: source fingerprint failed for ${package}" >&2
                [[ -z "${PACKAGE_UPDATE_FAILURES_FILE:-}" ]] ||
                    printf '%s\n' "$package" >>"$PACKAGE_UPDATE_FAILURES_FILE"
                continue
            fi
            if [[ "$fingerprints_before" != "$fingerprints_after" ]]; then
                echo "package_updates: mutable source changed during detection for ${package}" >&2
                [[ -z "${PACKAGE_UPDATE_FAILURES_FILE:-}" ]] ||
                    printf '%s\n' "$package" >>"$PACKAGE_UPDATE_FAILURES_FILE"
                continue
            fi
            fingerprints_json="$fingerprints_after"
        fi
        read -r current latest <<<"$versions"
        needs_update=0
        if version_is_newer "$latest" "$current"; then
            needs_update=1
        elif [[ "$current" == "$latest" ]] &&
            is_mutable_source_package "$package"; then
            if fingerprints_match_recipe "$package" "$fingerprints_json"; then
                :
            else
                drift_status=$?
                if [[ "$drift_status" -gt 1 ]]; then
                    echo "package_updates: source fingerprint failed for ${package}" >&2
                    [[ -z "${PACKAGE_UPDATE_FAILURES_FILE:-}" ]] ||
                        printf '%s\n' "$package" >>"$PACKAGE_UPDATE_FAILURES_FILE"
                    continue
                fi
                needs_update=1
            fi
        fi
        if [[ "$needs_update" -eq 1 ]]; then
            printf '%s\n' "$package"
            if [[ -n "${PACKAGE_UPDATE_PLAN_FILE:-}" ]]; then
                printf '%s\t%s\t%s\t%s\n' \
                    "$package" "$current" "$latest" "$fingerprints_json" \
                    >>"$PACKAGE_UPDATE_PLAN_FILE"
            fi
        elif [[ -n "${PACKAGE_UPDATE_CURRENT_FILE:-}" ]]; then
            printf '%s\n' "$package" >>"$PACKAGE_UPDATE_CURRENT_FILE"
        fi
    done
}

if [[ "${PACKAGE_UPDATES_LIB_ONLY:-0}" != 1 ]]; then
    case "${1:-}" in
    check)
        [[ "$#" -eq 2 ]] || die 'usage: package_updates.sh check <package>'
        check_package "$2"
        ;;
    check-all)
        [[ "$#" -eq 1 ]] || die 'usage: package_updates.sh check-all'
        check_all
        ;;
    outdated)
        [[ "$#" -eq 1 ]] || die 'usage: package_updates.sh outdated'
        outdated_packages
        ;;
    fingerprints)
        [[ "$#" -eq 2 ]] || die 'usage: package_updates.sh fingerprints <package>'
        is_mutable_source_package "$2" ||
            die "package has no mutable source fingerprint: $2"
        source_fingerprints "$2"
        ;;
    *)
        die 'usage: package_updates.sh {check <package>|check-all|outdated|fingerprints <package>}'
        ;;
    esac
fi
