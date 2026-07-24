#!/bin/bash
set -euo pipefail

readonly -a PACKAGES=(
    adwyra
    anidesk
    balena-etcher
    chatbox
    clash-verge-rev
    claude-alt
    claude
    codex
    fisher
    github-desktop
    happ
    netbird
    nivora-stplr
    opencode
    parsec
    pineconemc
    tailscale
    ventoy
    vual
    yandex-browser-stable
)

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"

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
                [
                    .[]
                    | select(.draft == false and .prerelease == false)
                    | .tag_name
                    | select(test("(?:^|[-_.])(alpha|beta|rc|pre|preview)(?:[-_.0-9]|$)"; "i") | not)
                ][0] // empty
            ' 2>/dev/null
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

latest_chatbox() {
    local version
    version="$(
        github_json 'https://api.github.com/repos/chatboxai/chatbox/releases?per_page=30' |
            jq -er '
                [
                    .[]
                    | select(.draft == false and .prerelease == false)
                    | . as $release
                    | $release.assets[]?
                    | select(.name | test("^Chatbox-[0-9]+(?:\\.[0-9]+)+-amd64\\.deb$"))
                    | $release.tag_name
                ][0]
            ' |
            sed 's/^v//'
    )" || die 'cannot determine latest Chatbox Linux release'
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

latest_yandex_browser() {
    local version
    version="$(
        curl --retry 3 --retry-delay 2 --retry-all-errors \
            --connect-timeout 30 --max-time 120 -fsSL \
            'https://repo.yandex.ru/yandex-browser/deb/dists/stable/main/binary-amd64/Packages.gz' |
            gzip -dc |
            awk '
                /^Package: yandex-browser-stable$/ { selected = 1; next }
                /^Package: / { selected = 0 }
                selected && /^Version: / {
                    version = $2
                    sub(/-[^-]+$/, "", version)
                    print version
                }
            ' |
            sort -V |
            tail -1
    )"
    [[ -n "$version" ]] || die 'cannot determine latest Yandex Browser version'
    printf '%s\n' "$version"
}

latest_version() {
    case "$1" in
    adwyra) github_latest_release Cheviiot/Adwyra ;;
    anidesk) latest_anidesk ;;
    balena-etcher) github_latest_release balena-io/etcher ;;
    chatbox) latest_chatbox ;;
    clash-verge-rev) github_latest_release clash-verge-rev/clash-verge-rev ;;
    claude | claude-alt) latest_claude_desktop ;;
    codex) github_latest_release Boria138/codex-app-linux ;;
    fisher) github_latest_release jorgebucaran/fisher ;;
    github-desktop)
        github_latest_release desktop/desktop | sed 's/^release-//'
        ;;
    happ) github_latest_release Happ-proxy/happ-desktop ;;
    netbird) github_latest_release netbirdio/netbird ;;
    nivora-stplr) current_version nivora-stplr ;;
    opencode) github_latest_release anomalyco/opencode ;;
    parsec) latest_parsec ;;
    pineconemc) github_latest_release ElyPrismLauncher/Launcher ;;
    tailscale) latest_tailscale ;;
    ventoy) github_latest_release ventoy/Ventoy ;;
    vual) github_latest_release Cheviiot/Vual ;;
    yandex-browser-stable) latest_yandex_browser ;;
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
    local package current latest status versions
    local updates=0
    printf '%-24s %-24s %-24s %s\n' PACKAGE CURRENT LATEST STATUS
    for package in "${PACKAGES[@]}"; do
        versions="$(check_package "$package")" || return
        read -r current latest <<<"$versions"
        status=current
        if [[ "$current" != "$latest" ]]; then
            status=update
            updates=1
        fi
        printf '%-24s %-24s %-24s %s\n' "$package" "$current" "$latest" "$status"
    done
    [[ "$updates" -eq 0 ]] || return 10
}

outdated_packages() {
    local package current latest versions
    for package in "${PACKAGES[@]}"; do
        versions="$(check_package "$package")" || return
        read -r current latest <<<"$versions"
        if [[ "$current" != "$latest" ]]; then
            printf '%s\n' "$package"
        fi
    done
}

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
*)
    die 'usage: package_updates.sh {check <package>|check-all|outdated}'
    ;;
esac
