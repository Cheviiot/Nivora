#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
cd "$repo_root"

mapfile -d '' shell_files < <(
    find . -type f -not -path './.git/*' -print0 |
        while IFS= read -r -d '' file; do
            if head -n 1 -- "$file" 2>/dev/null |
                grep -IqE '^#!.*(bash|/sh)([[:space:]]|$)'; then
                printf '%s\0' "$file"
            fi
        done
)

mapfile -d '' python_files < <(
    find . -type f -name '*.py' -not -path './.git/*' -print0
)

for file in "${shell_files[@]}"; do
    bash -n "$file"
done

if [[ "${#shell_files[@]}" -gt 0 ]]; then
    shellcheck -x "${shell_files[@]}"
fi

if [[ "${#python_files[@]}" -gt 0 ]]; then
    python3 -m py_compile "${python_files[@]}"
fi

python3 -m unittest discover -s tests -p 'test_*.py' -v
bash tests/test_helper.sh
bash tests/test_migration.sh
python3 tools/validate_repo.py

if command -v stplr-spec >/dev/null 2>&1; then
    for staplerfile in */Staplerfile; do
        stplr-spec get-field --path "$staplerfile" name >/dev/null
    done
fi

echo 'OK: все проверки Nivora завершены'
