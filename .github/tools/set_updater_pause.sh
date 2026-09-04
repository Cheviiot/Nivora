#!/bin/bash
set -euo pipefail

state="${1:?usage: set_updater_pause.sh (true|false) [sha] [reason]}"
sha="${2:-unknown}"
reason="${3:-post-push verification failed}"
repository="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
run_url="https://github.com/${repository}/actions/runs/${GITHUB_RUN_ID:?GITHUB_RUN_ID is required}"
marker='<!-- nivora-updater-paused -->'
title='[autoupdate] обновления приостановлены'

case "$state" in
true | false) ;;
*)
    echo "invalid pause state: ${state}" >&2
    exit 2
    ;;
esac

[[ "$sha" =~ ^[0-9a-f]{40}$ ]] || {
    echo "invalid commit SHA: ${sha}" >&2
    exit 2
}

reason="$(python3 - "$reason" <<'PY'
import sys

value = " ".join(sys.argv[1].split())[:500]
print(value.replace("@", "@\u200b").replace("<!-- nivora-", "<!\u200b-- nivora-"))
PY
)"

gh variable set NIVORA_UPDATER_PAUSED --repo "$repository" --body "$state"
if [[ "$state" == true ]]; then
    gh variable set NIVORA_UPDATER_PAUSED_SHA --repo "$repository" --body "$sha"
fi
issue_number="$(
    gh api --paginate --slurp \
        "repos/${repository}/issues?state=all&per_page=100" 2>/dev/null |
        jq -r --arg marker "$marker" --arg title "$title" '
            [.[][] | select(has("pull_request") | not) |
             select(.user.login == "github-actions[bot]") |
             select(.title == $title) |
             select((((.body // "") | split("\n"))[0] // "") == $marker)]
             [0].number // empty
        ' 2>/dev/null
)" || true

if [[ "$state" == true ]]; then
    body="$marker

Автоматические обновления приостановлены после сбоя проверки точного commit **${sha}**.

- Причина: ${reason}
- Запуск: ${run_url}

После исправления запустите post-push проверку вручную для текущего SHA main с параметром resume_on_success. Recovery проверит все 16 пакетов и разрешит снятие паузы только для потомка этого commit."
    if [[ -n "$issue_number" ]]; then
        gh api --method PATCH "repos/${repository}/issues/${issue_number}" \
            -f state=open -f body="$body" >/dev/null
    else
        gh api --method POST "repos/${repository}/issues" \
            -f title="$title" \
            -f body="$body" >/dev/null
    fi
elif [[ -n "$issue_number" ]]; then
    gh api --method PATCH "repos/${repository}/issues/${issue_number}" \
        -f state=closed -f state_reason=completed >/dev/null
fi
