#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
target="${1:?usage: prepare_stplr_spec.sh TARGET REPOSITORY}"
repository="${2:?usage: prepare_stplr_spec.sh TARGET REPOSITORY}"
commit="${STPLR_UTILS_COMMIT:?STPLR_UTILS_COMMIT is required}"
checkout="$(mktemp -d "${TMPDIR:-/tmp}/nivora-stplr-spec.XXXXXX")"
cleanup() {
    find "$checkout" -mindepth 1 -delete
    rmdir "$checkout"
}
trap cleanup EXIT

for command in git go; do
    command -v "$command" >/dev/null 2>&1 || {
        echo "prepare_stplr_spec: required command is missing: ${command}" >&2
        exit 2
    }
done

# shellcheck source=.github/tools/lib/pinned_git_checkout.sh
source "${script_dir}/lib/pinned_git_checkout.sh"
# shellcheck source=.github/tools/lib/go_build.sh
source "${script_dir}/lib/go_build.sh"
pinned_git_checkout "$repository" "$commit" "$checkout"
nivora_build_go_binary "$checkout" "$target" ./cmd/stplr-spec --help
