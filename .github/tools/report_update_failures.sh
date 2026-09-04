#!/bin/bash
set -euo pipefail

results_dir="${AUTONOMOUS_UPDATE_RESULTS_DIR:?AUTONOMOUS_UPDATE_RESULTS_DIR is required}"
resolved_file="${AUTONOMOUS_UPDATE_RESOLVED_FILE:-${results_dir}/successful-packages}"
repository="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
run_url="https://github.com/${repository}/actions/runs/${GITHUB_RUN_ID:?GITHUB_RUN_ID is required}"
issues_json="$(
    gh api --paginate --slurp \
        "repos/${repository}/issues?state=all&per_page=100"
)"

is_safe_package() {
    [[ "$1" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]
}

is_safe_phase() {
    case "$1" in
    detect-version | prepare-worktree | update-recipe | pin-upstream-commit | \
        pin-source-fingerprint | sync-catalog | static-checks | clean-build | \
        verify-artifact | no-update-diff)
        return 0
        ;;
    *) return 1 ;;
    esac
}

append_snippet() {
    local path="$1"
    local mode="$2"
    [[ -f "$path" && ! -L "$path" ]] || {
        printf '    (нет данных)\n'
        return
    }
    python3 - "$path" "$mode" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
mode = sys.argv[2]
lines = path.read_bytes().decode("utf-8", errors="replace").splitlines()
lines = lines[-80:] if mode == "tail" else lines[:200]
text = "\n".join(lines)
raw = text.encode("utf-8")
if len(raw) > 12_000:
    text = raw[:12_000].decode("utf-8", errors="ignore") + "\n…(обрезано)"

# Do not let upstream-controlled diagnostics create mentions or service markers.
text = text.replace("@", "@\u200b").replace("<!-- nivora-", "<!\u200b-- nivora-")
if not text:
    text = "(пусто)"
for line in text.splitlines():
    print(f"    {line}")
PY
}

find_issue() {
    local marker="$1"
    local title="$2"
    jq -r --arg marker "$marker" --arg title "$title" '
        [
            .[][]
            | select(has("pull_request") | not)
            | select(.user.login == "github-actions[bot]")
            | select(.title == $title)
            | select((((.body // "") | split("\n"))[0] // "") == $marker)
        ][0].number // empty
    ' <<<"$issues_json"
}

while IFS=$'\t' read -r package phase; do
    [[ -n "$package" ]] || continue
    is_safe_package "$package" || {
        echo "unsafe package in failed-packages: ${package}" >&2
        exit 1
    }
    is_safe_phase "$phase" || {
        echo "unsafe phase in failed-packages: ${phase}" >&2
        exit 1
    }
    marker="<!-- nivora-autonomous-update:${package} -->"
    title="[autoupdate] ${package}: требуется диагностика"
    issue_number="$(find_issue "$marker" "$title")"
    report="${results_dir}/${package}/issue-body.md"
    {
        printf '%s\n\n' "$marker"
        printf 'Автономное обновление пакета **%s** остановлено на фазе **%s**.\n\n' \
            "$package" "$phase"
        printf -- '- Последний запуск: %s\n' "$run_url"
        printf -- '- Диагностика Actions хранится 30 дней в artifact запуска.\n'
        printf -- '- Остальные пакеты обновляются независимо от этого сбоя.\n\n'
        printf '### Состояние\n\n'
        append_snippet "${results_dir}/${package}/FAILED" head
        printf '\n### Последние строки журнала\n\n'
        append_snippet "${results_dir}/${package}/update.log" tail
        printf '\n### Изменения рецепта\n\n'
        append_snippet "${results_dir}/${package}/failed.patch" head
    } >"$report"

    if [[ -n "$issue_number" ]]; then
        gh api --method PATCH "repos/${repository}/issues/${issue_number}" \
            -f state=open \
            -f body="$(<"$report")" >/dev/null
    else
        gh api --method POST "repos/${repository}/issues" \
            -f title="$title" \
            -f body="$(<"$report")" >/dev/null
    fi
done <"${results_dir}/failed-packages"

while IFS= read -r package; do
    [[ -n "$package" ]] || continue
    is_safe_package "$package" || {
        echo "unsafe package in resolved package list: ${package}" >&2
        exit 1
    }
    marker="<!-- nivora-autonomous-update:${package} -->"
    title="[autoupdate] ${package}: требуется диагностика"
    issue_number="$(find_issue "$marker" "$title")"
    if [[ -n "$issue_number" ]]; then
        gh api --method PATCH "repos/${repository}/issues/${issue_number}" \
            -f state=closed \
            -f state_reason=completed >/dev/null
    fi
done < <(
    if [[ -f "$resolved_file" ]]; then
        sort -u "$resolved_file"
    fi
)
