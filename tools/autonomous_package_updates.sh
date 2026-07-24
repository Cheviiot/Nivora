#!/bin/bash
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
results_dir="${AUTONOMOUS_UPDATE_RESULTS_DIR:?AUTONOMOUS_UPDATE_RESULTS_DIR is required}"

[[ "$#" -gt 0 ]] || {
    echo 'usage: autonomous_package_updates.sh package...' >&2
    exit 2
}

mkdir -p "$results_dir"
: >"${results_dir}/successful-packages"
: >"${results_dir}/failed-packages"

for package in "$@"; do
    package_result="${results_dir}/${package}"
    worktree="${RUNNER_TEMP:?RUNNER_TEMP is required}/update-${package}"
    mkdir -p "$package_result"

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

    phase_file="${package_result}/phase"
    log_file="${package_result}/update.log"
    if (
        set -euo pipefail
        cd "$worktree"

        echo update-recipe >"$phase_file"
        stplr-spec update-package "$package"

        echo sync-catalog >"$phase_file"
        tools/sync_readme_versions.py

        echo static-checks >"$phase_file"
        tools/run_checks.sh

        echo clean-build >"$phase_file"
        tools/clean_build.sh "$package"

        echo verify-artifact >"$phase_file"
        tools/verify_artifacts.sh "$package"
    ) >"$log_file" 2>&1; then
        git -C "$worktree" diff --binary -- "$package" \
            >"${package_result}/update.patch"
        printf '%s\n' "$package" >>"${results_dir}/successful-packages"
        echo success >"${package_result}/result"
    else
        status=$?
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

    git -C "$repo_root" worktree remove --force "$worktree" \
        >>"${package_result}/worktree.log" 2>&1
done
