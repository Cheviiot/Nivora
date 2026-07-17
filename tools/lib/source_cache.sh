#!/bin/bash

import_stplr_source_cache() {
    local cache_engine="$1"
    local cache_image="$2"
    local cache_volume_name="$3"
    local cache_work_dir="$4"
    local cache_source_dir="$5"
    shift 5
    local packages=("$@")

    if [[ ! -d "$cache_source_dir" ]] || ! command -v sqlite3 >/dev/null 2>&1; then
        echo '==> source cache import skipped'
        return 0
    fi

    local cache_manifest="${cache_work_dir}/source-cache.tsv"
    local cache_db="${cache_work_dir}/source-cache.db"
    local package package_name package_version index source expected
    local url_hash restore_name candidate actual
    local -a package_sources package_checksums

    : >"$cache_manifest"
    sqlite3 "$cache_db" '
        CREATE TABLE cache_record (
            i_d INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
            hash TEXT NULL,
            repo TEXT NULL,
            pkg TEXT NULL,
            ver TEXT NULL,
            name TEXT NULL,
            type INTEGER NULL
        );
        CREATE INDEX IDX_cache_record_hash ON cache_record(hash);
        CREATE INDEX IDX_cache_record_repo ON cache_record(repo);
        CREATE INDEX IDX_cache_record_pkg ON cache_record(pkg);
        CREATE INDEX IDX_cache_record_ver ON cache_record(ver);
    '

    for package in "${packages[@]}"; do
        package_name="$(stplr-spec get-field --path "${package}/Staplerfile" name)"
        package_version="$(stplr-spec get-field --path "${package}/Staplerfile" version)"
        [[ "$package_name" =~ ^[a-z0-9.+-]+$ ]]
        [[ "$package_version" =~ ^[A-Za-z0-9._+~-]+$ ]]

        read -ra package_sources <<<"$(
            stplr-spec get-field --path "${package}/Staplerfile" sources
        )"
        read -ra package_checksums <<<"$(
            stplr-spec get-field --path "${package}/Staplerfile" checksums
        )"

        for index in "${!package_sources[@]}"; do
            source="${package_sources[$index]}"
            [[ "$source" != local://* && "$source" == *'~archive=false'* ]] || continue
            [[ -v 'package_checksums[index]' ]]
            expected="${package_checksums[$index]#sha256:}"
            url_hash="$(printf '%s' "$source" | sha256sum)"
            url_hash="${url_hash%% *}"
            if [[ "$source" == *'~name='* ]]; then
                restore_name="${source##*~name=}"
                restore_name="${restore_name%%&*}"
            else
                restore_name="$(basename "${source%%\?*}")"
            fi
            [[ "$restore_name" =~ ^[A-Za-z0-9._+-]+$ ]]

            candidate="${cache_source_dir}/${url_hash}/${restore_name}"
            [[ -f "$candidate" ]] || continue
            actual="$(sha256sum "$candidate")"
            actual="${actual%% *}"
            [[ "$actual" == "$expected" ]] || continue

            printf '%s\t%s\t%s\n' "$url_hash" "$restore_name" "$expected" \
                >>"$cache_manifest"
            sqlite3 "$cache_db" \
                "INSERT INTO cache_record(hash, repo, pkg, ver, name, type) VALUES('$url_hash', 'default', '$package_name', '$package_version', '$restore_name', 1);"
        done
    done

    echo "==> importing verified sources from ${cache_source_dir}"
    # The script is intentionally expanded inside the container, not by the host shell.
    # shellcheck disable=SC2016
    "$cache_engine" run --rm \
        -v "${cache_source_dir}:/source:ro" \
        -v "${cache_manifest}:/manifest:ro" \
        -v "${cache_db}:/cache-db:ro" \
        -v "${cache_volume_name}:/var/cache/stplr" \
        "$cache_image" \
        bash -euo pipefail -c '
            mkdir -p /var/cache/stplr/dl
            cp -a /cache-db /var/cache/stplr/dl/db
            imported=0
            bytes=0
            while IFS=$'"'"'\t'"'"' read -r url_hash restore_name expected; do
                source="/source/${url_hash}/${restore_name}"
                actual="$(sha256sum "$source")"
                actual="${actual%% *}"
                [[ "$actual" == "$expected" ]]
                destination="/var/cache/stplr/dl/${url_hash}/${restore_name}"
                mkdir -p "${destination%/*}"
                cp -a "$source" "$destination"
                size="$(stat -c %s "$source")"
                imported=$((imported + 1))
                bytes=$((bytes + size))
            done </manifest
            chown -R --reference=/var/cache/stplr /var/cache/stplr/dl
            printf "Imported sources: %d (%d bytes)\n" "$imported" "$bytes"
        '
}
