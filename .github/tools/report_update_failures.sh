#!/bin/bash
set -euo pipefail

results_dir="${AUTONOMOUS_UPDATE_RESULTS_DIR:?AUTONOMOUS_UPDATE_RESULTS_DIR is required}"
repository="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
run_url="https://github.com/${repository}/actions/runs/${GITHUB_RUN_ID:?GITHUB_RUN_ID is required}"
issues_json="$(
    gh api --paginate --slurp \
        "repos/${repository}/issues?state=all&per_page=100"
)"
code_fence='```'

find_issue() {
    local marker="$1"
    jq -r --arg marker "$marker" '
        [
            .[][]
            | select(has("pull_request") | not)
            | select((.body // "") | contains($marker))
        ][0].number // empty
    ' <<<"$issues_json"
}

while IFS=$'\t' read -r package phase; do
    [[ -n "$package" ]] || continue
    marker="<!-- nivora-autonomous-update:${package} -->"
    issue_number="$(find_issue "$marker")"
    report="${results_dir}/${package}/issue-body.md"
    {
        printf '%s\n\n' "$marker"
        printf 'Автономное обновление пакета **%s** остановлено на фазе **%s**.\n\n' \
            "$package" "$phase"
        printf -- '- Последний запуск: %s\n' "$run_url"
        printf -- '- Диагностика Actions хранится 30 дней в artifact запуска.\n'
        printf -- '- Остальные пакеты обновляются независимо от этого сбоя.\n\n'
        printf '### Состояние\n\n%stext\n' "$code_fence"
        sed -n '1,80p' "${results_dir}/${package}/FAILED"
        printf '%s\n\n### Последние строки журнала\n\n%stext\n' \
            "$code_fence" "$code_fence"
        tail -n 80 "${results_dir}/${package}/update.log" 2>/dev/null || true
        printf '%s\n\n### Изменения рецепта\n\n%sdiff\n' \
            "$code_fence" "$code_fence"
        sed -n '1,200p' "${results_dir}/${package}/failed.patch" \
            2>/dev/null || true
        printf '%s\n' "$code_fence"
    } >"$report"

    if [[ -n "$issue_number" ]]; then
        gh api --method PATCH "repos/${repository}/issues/${issue_number}" \
            -f state=open \
            -f body="$(<"$report")" >/dev/null
    else
        gh api --method POST "repos/${repository}/issues" \
            -f title="[autoupdate] ${package}: требуется диагностика" \
            -f body="$(<"$report")" >/dev/null
    fi
done <"${results_dir}/failed-packages"

while IFS= read -r package; do
    [[ -n "$package" ]] || continue
    marker="<!-- nivora-autonomous-update:${package} -->"
    issue_number="$(find_issue "$marker")"
    if [[ -n "$issue_number" ]]; then
        gh api --method PATCH "repos/${repository}/issues/${issue_number}" \
            -f state=closed \
            -f state_reason=completed >/dev/null
    fi
done <"${results_dir}/successful-packages"
