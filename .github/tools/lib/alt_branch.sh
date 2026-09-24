#!/bin/bash
# Single source of truth for the ALT branch a build or lifecycle run targets.
# Both branches are declared in .github/support-matrix.toml, and the container
# image of each one is digest-pinned there.

nivora_alt_branch() {
    local branch="${NIVORA_ALT_BRANCH:-sisyphus}"
    case "$branch" in
    p11 | sisyphus)
        printf '%s\n' "$branch"
        ;;
    *)
        echo "Неизвестная ветка ALT: ${branch} (ожидается p11 или sisyphus)" >&2
        return 2
        ;;
    esac
}

nivora_alt_branch_image() {
    local branch="$1"
    local matrix override image
    matrix="$(
        cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd
    )/support-matrix.toml"

    # An explicit override still has to be digest-pinned; see clean_build.sh.
    override="${NIVORA_ALT_BUILDER_IMAGE:-}"
    if [[ -n "$override" ]]; then
        printf '%s\n' "$override"
        return 0
    fi

    image="$(
        python3 - "$matrix" "$branch" <<'PY'
import sys, tomllib
with open(sys.argv[1], "rb") as stream:
    matrix = tomllib.load(stream)
image = matrix.get("images", {}).get(f"alt_{sys.argv[2]}")
if not image:
    raise SystemExit(f"support matrix has no image for ALT {sys.argv[2]}")
print(image)
PY
    )" || return 1
    printf '%s\n' "$image"
}
