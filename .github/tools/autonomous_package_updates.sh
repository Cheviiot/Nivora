#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
results_dir="${AUTONOMOUS_UPDATE_RESULTS_DIR:?AUTONOMOUS_UPDATE_RESULTS_DIR is required}"
stplr_spec_command="${STPLR_SPEC_COMMAND:-stplr-spec}"
update_plan_json="${UPDATE_PLAN_JSON:?UPDATE_PLAN_JSON is required}"

mkdir -p "$results_dir"
: >"${results_dir}/successful-packages"
: >"${results_dir}/failed-packages"
: >"${results_dir}/checked-packages"

pin_github_desktop_source() {
    local worktree="$1"
    local staplerfile="${worktree}/github-desktop/Staplerfile"
    local version resolved

    version="$("$stplr_spec_command" get-field --path "$staplerfile" version)" || return
    resolved="${GITHUB_DESKTOP_UPSTREAM_COMMIT:-}"
    if [[ -z "$resolved" ]]; then
        resolved="$({
            git ls-remote https://github.com/desktop/desktop.git \
                "refs/tags/release-${version}^{}"
            git ls-remote https://github.com/desktop/desktop.git \
                "refs/tags/release-${version}"
        } | awk 'NR == 1 { print $1 }')" || return
    fi
    [[ "$resolved" =~ ^[0-9a-f]{40}$ ]] || return

    sed -i \
        "s/^upstream_commit='[0-9a-f]\{40\}'$/upstream_commit='${resolved}'/" \
        "$staplerfile" || return
    "$stplr_spec_command" update-checksums --path "$staplerfile" || return
    EXPECTED_UPSTREAM_COMMIT="$resolved" \
        bash "${worktree}/github-desktop/tests/test-upstream-pin.sh" || return
}

is_mutable_source_package() {
    case "$1" in
    chatgpt | parsec) return 0 ;;
    *) return 1 ;;
    esac
}

planned_version() {
    local package="$1"
    local field="$2"
    jq -er --arg package "$package" --arg field "$field" \
        '.[$package][$field] | select(type == "string" and length > 0)' \
        <<<"$update_plan_json"
}

planned_fingerprints() {
    local package="$1"
    jq -cer --arg package "$package" \
        '.[$package].fingerprints | select(type == "object")' \
        <<<"$update_plan_json"
}

bump_recipe_release() {
    local staplerfile="$1"
    local release
    release="$("$stplr_spec_command" get-field --path "$staplerfile" release)" || return
    [[ "$release" =~ ^[1-9][0-9]*$ ]] || return
    sed -i -E "s/^release=[1-9][0-9]*$/release=$((release + 1))/" \
        "$staplerfile" || return
    grep -Fxq "release=$((release + 1))" "$staplerfile"
}

pin_mutable_source_fingerprints() {
    local worktree="$1"
    local package="$2"
    local fingerprints="$3"
    local staplerfile="${worktree}/${package}/Staplerfile"
    local field fingerprint count=0
    while IFS=$'\t' read -r field fingerprint; do
        [[ "$field" =~ ^source_fingerprint(_(amd64|arm64))?$ ]] || return
        [[ "$fingerprint" =~ ^[0-9a-f]{64}$ ]] || return
        grep -Eq "^${field}='[0-9a-f]{64}'$" "$staplerfile" || return
        sed -i -E \
            "s/^${field}='[0-9a-f]{64}'$/${field}='${fingerprint}'/" \
            "$staplerfile" || return
        count=$((count + 1))
    done < <(jq -r 'to_entries[] | [.key, .value] | @tsv' <<<"$fingerprints")
    [[ "$count" -gt 0 ]]
}

verify_mutable_source_snapshot() {
    local package="$1"
    local expected="$2"
    local actual
    actual="$(
        "${repo_root}/.github/tools/package_updates.sh" fingerprints "$package" |
            jq -cRn '
                [inputs | select(length > 0) | split("\t") |
                    {key: .[0], value: .[1]}]
                | from_entries
            '
    )" || return
    [[ "$(jq -cS . <<<"$actual")" == "$(jq -cS . <<<"$expected")" ]]
}

run_update_phases() {
    local worktree="$1"
    local package="$2"
    local phase_file="$3"
    local planned_current planned_latest planned_source_fingerprints

    cd "$worktree" || return
    echo update-recipe >"$phase_file" || return
    planned_current="$(planned_version "$package" current)" || return
    planned_latest="$(planned_version "$package" latest)" || return
    if is_mutable_source_package "$package"; then
        planned_source_fingerprints="$(planned_fingerprints "$package")" || return
        verify_mutable_source_snapshot \
            "$package" "$planned_source_fingerprints" || return
    fi
    if is_mutable_source_package "$package" &&
        [[ "$planned_current" == "$planned_latest" ]]; then
        "$stplr_spec_command" update-checksums \
            --path "${worktree}/${package}/Staplerfile" || return
        bump_recipe_release "${worktree}/${package}/Staplerfile" || return
    else
        "$stplr_spec_command" update-package "$package" || return
    fi
    if [[ "$package" == 'github-desktop' ]]; then
        echo pin-upstream-commit >"$phase_file" || return
        pin_github_desktop_source "$worktree" || return
    fi
    if is_mutable_source_package "$package"; then
        echo pin-source-fingerprint >"$phase_file" || return
        verify_mutable_source_snapshot \
            "$package" "$planned_source_fingerprints" || return
        pin_mutable_source_fingerprints \
            "$worktree" "$package" "$planned_source_fingerprints" || return
    fi
    echo sync-catalog >"$phase_file" || return
    .github/tools/sync_readme_versions.py || return
    echo static-checks >"$phase_file" || return
    .github/tools/run_checks.sh || return
    echo clean-build >"$phase_file" || return
    .github/tools/clean_build.sh "$package" || return
    echo verify-artifact >"$phase_file" || return
    .github/tools/verify_artifacts.sh "$package" || return
}

if [[ "$#" -eq 0 ]]; then
    echo 'No outdated packages were detected'
    exit 0
fi

for package in "$@"; do
    package_result="${results_dir}/${package}"
    worktree="${RUNNER_TEMP:?RUNNER_TEMP is required}/update-${package}"
    mkdir -p "$package_result"
    printf '%s\n' "$package" >>"${results_dir}/checked-packages"
    phase_file="${package_result}/phase"
    echo prepare-worktree >"$phase_file"

    if ! git -C "$repo_root" worktree add --detach "$worktree" HEAD \
        >"${package_result}/worktree.log" 2>&1; then
        {
            printf 'package=%s\n' "$package"
            printf 'phase=prepare-worktree\n'
            printf 'exit_status=1\n'
        } >"${package_result}/FAILED"
        printf '%s\t%s\n' "$package" prepare-worktree \
            >>"${results_dir}/failed-packages"
        echo failure >"${package_result}/result"
        continue
    fi

    log_file="${package_result}/update.log"
    set +e
    run_update_phases "$worktree" "$package" "$phase_file" \
        >"$log_file" 2>&1
    status=$?
    set -e
    if [[ "$status" -eq 0 ]]; then
        git -C "$worktree" diff --binary -- "$package" \
            >"${package_result}/update.patch"
        if [[ -s "${package_result}/update.patch" ]]; then
            printf '%s\n' "$package" >>"${results_dir}/successful-packages"
            echo success >"${package_result}/result"
        else
            {
                printf 'package=%s\n' "$package"
                printf 'phase=no-update-diff\n'
                printf 'exit_status=1\n'
            } >"${package_result}/FAILED"
            printf '%s\t%s\n' "$package" no-update-diff \
                >>"${results_dir}/failed-packages"
            echo failure >"${package_result}/result"
        fi
    else
        failed_phase="$(<"$phase_file")"
        {
            printf 'package=%s\n' "$package"
            printf 'phase=%s\n' "$failed_phase"
            printf 'exit_status=%s\n' "$status"
        } >"${package_result}/FAILED"
        git -C "$worktree" diff --binary \
            >"${package_result}/failed.patch"
        if [[ -f "${worktree}/${package}/Staplerfile" ]]; then
            install -Dm644 "${worktree}/${package}/Staplerfile" \
                "${package_result}/Staplerfile.after"
        fi
        printf '%s\t%s\n' "$package" "$failed_phase" \
            >>"${results_dir}/failed-packages"
        echo failure >"${package_result}/result"
    fi

    if ! git -C "$repo_root" worktree remove --force "$worktree" \
        >>"${package_result}/worktree.log" 2>&1; then
        echo "warning: unable to remove update worktree for ${package}" >&2
    fi
done
