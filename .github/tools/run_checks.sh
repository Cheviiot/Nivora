#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
cd "$repo_root"

command -v stplr-spec >/dev/null 2>&1 || {
    echo 'stplr-spec is required for repository validation' >&2
    exit 2
}

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

python3 -m unittest discover -s .github/tests -p 'test_*.py' -v
while IFS= read -r -d '' test_script; do
    bash "$test_script"
done < <(find .github/tests -maxdepth 1 -type f \
    -name 'test_*.sh' -print0 | sort -z)
while IFS= read -r -d '' test_script; do
    bash "$test_script"
done < <(find . -mindepth 3 -maxdepth 3 -type f \
    -path './*/tests/test-*.sh' -not -path './.github/*' -print0 | sort -z)
python3 .github/tools/validate_repo.py

for staplerfile in */Staplerfile; do
    stplr-spec get-field --path "$staplerfile" name >/dev/null
done

echo 'OK: все проверки Nivora завершены'
