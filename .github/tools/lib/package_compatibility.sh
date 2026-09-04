#!/bin/bash

nivora_read_optional_list_field() {
    local package="$1"
    local field="$2"
    local recipe="${package}/Staplerfile"

    [[ "$field" =~ ^[a-z_]+$ ]]
    if ! grep -Eq "^[[:space:]]*${field}[[:space:]]*=" "$recipe"; then
        return 0
    fi
    stplr-spec get-field --path "$recipe" "$field" || {
        echo "${package}: cannot read declared ${field}" >&2
        return 2
    }
}

# Return 0 for supported, 1 for intentionally unsupported and 2 for a
# malformed/unreadable compatibility declaration.
nivora_package_supports_distro() {
    local package="$1"
    local distro="$2"
    local compatible incompatible candidate

    compatible="$(nivora_read_optional_list_field "$package" compatible_with)" || \
        return 2
    incompatible="$(nivora_read_optional_list_field "$package" incompatible_with)" || \
        return 2

    for candidate in $incompatible; do
        [[ "$candidate" != "$distro" ]] || return 1
    done
    [[ -n "$compatible" ]] || return 0
    for candidate in $compatible; do
        [[ "$candidate" != "$distro" ]] || return 0
    done
    return 1
}
