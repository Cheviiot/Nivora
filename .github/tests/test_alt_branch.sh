#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=.github/tools/lib/alt_branch.sh
source "${repo_root}/.github/tools/lib/alt_branch.sh"

unset NIVORA_ALT_BRANCH NIVORA_ALT_BUILDER_IMAGE
[[ "$(nivora_alt_branch)" == p11 ]]
[[ "$(NIVORA_ALT_BRANCH=p11 nivora_alt_branch)" == p11 ]]
[[ "$(NIVORA_ALT_BRANCH='' nivora_alt_branch)" == p11 ]]
image="$(nivora_alt_branch_image "$(nivora_alt_branch)")"
[[ "$image" =~ ^registry\.altlinux\.org/p11/base@sha256:[0-9a-f]{64}$ ]]

override="registry.example/p11@sha256:$(printf '0%.0s' {1..64})"
[[ "$(NIVORA_ALT_BUILDER_IMAGE="$override" nivora_alt_branch_image p11)" == "$override" ]]

for branch in sisyphus p10 unknown; do
    if output="$(NIVORA_ALT_BRANCH="$branch" nivora_alt_branch 2>&1)"; then
        echo "Unsupported ALT branch was accepted: $branch" >&2
        exit 1
    else
        status=$?
    fi
    [[ "$status" -eq 2 && "$output" == *'только ALT p11'* ]]

    # The image override must not bypass branch validation when the image
    # helper is called directly instead of through nivora_alt_branch.
    if output="$(NIVORA_ALT_BUILDER_IMAGE="$override" nivora_alt_branch_image "$branch" 2>&1)"; then
        echo "Image override accepted unsupported ALT branch: $branch" >&2
        exit 1
    else
        status=$?
    fi
    [[ "$status" -eq 2 && "$output" == *'только ALT p11'* ]]
done

# Exercise the real lifecycle entry point without a container or downloads.
plan="$(NIVORA_LIFECYCLE_PLAN_ONLY=1 NIVORA_LIFECYCLE_PACKAGES=antigravity \
    bash "${repo_root}/.github/tools/test_package_lifecycle.sh")"
[[ "$plan" == $'BRANCH:p11\nRPM:antigravity' ]]

# Both entry points must reject an unsupported branch before any tooling,
# container or image override can be used. An invalid package also keeps the
# build fixture inert if a regression mistakenly accepts the branch.
for tool in clean_build.sh test_package_lifecycle.sh; do
    if output="$(NIVORA_ALT_BRANCH=sisyphus NIVORA_ALT_BUILDER_IMAGE="$override" \
        NIVORA_LIFECYCLE_PLAN_ONLY=1 \
        bash "${repo_root}/.github/tools/$tool" __invalid_fixture_package__ 2>&1)"; then
        echo "$tool accepted an unsupported ALT branch" >&2
        exit 1
    else
        status=$?
    fi
    [[ "$status" -eq 2 && "$output" == *'только ALT p11'* ]]
done

echo 'OK: сборка и lifecycle поддерживают только ALT p11'
