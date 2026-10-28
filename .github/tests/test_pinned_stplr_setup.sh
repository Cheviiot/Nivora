#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/nivora-pinned-stplr.XXXXXX")"
cleanup() {
    find "$scratch" -mindepth 1 -delete
    rmdir "$scratch"
}
trap cleanup EXIT

real_git="$(command -v git)"
export GIT_CONFIG_NOSYSTEM=1
export GIT_TERMINAL_PROMPT=0
export GIT_AUTHOR_NAME=test
export GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test
export GIT_COMMITTER_EMAIL=test@example.invalid

git init --bare -q "$scratch/remote.git"
git init -q "$scratch/seed"
git -C "$scratch/seed" checkout -qb main
git -C "$scratch/seed" remote add origin "$scratch/remote.git"
printf 'pinned\n' >"$scratch/seed/source.txt"
git -C "$scratch/seed" add source.txt
git -C "$scratch/seed" commit -qm pinned
pinned_sha="$(git -C "$scratch/seed" rev-parse HEAD)"
git -C "$scratch/seed" push -q origin HEAD:main
printf 'different\n' >"$scratch/seed/source.txt"
git -C "$scratch/seed" commit -qam different
wrong_sha="$(git -C "$scratch/seed" rev-parse HEAD)"
git -C "$scratch/seed" push -q origin HEAD:other

mkdir -p "$scratch/mock-bin"
cat >"$scratch/mock-bin/git" <<'GIT'
#!/bin/bash
set -euo pipefail
args=()
is_fetch=false
for argument in "$@"; do
    [[ "$argument" == fetch ]] && is_fetch=true
done
if [[ "$is_fetch" == true ]]; then
    count=0
    [[ ! -f "$NIVORA_FETCH_COUNT_FILE" ]] || read -r count <"$NIVORA_FETCH_COUNT_FILE"
    count=$((count + 1))
    printf '%s\n' "$count" >"$NIVORA_FETCH_COUNT_FILE"
    printf '%s\n' "$*" >>"$NIVORA_FETCH_ARGS_LOG"
    case "$NIVORA_FETCH_MODE" in
        transient)
            if ((count < 3)); then
                echo 'mock transient network failure' >&2
                exit 1
            fi
            ;;
        permanent)
            echo 'mock persistent network failure' >&2
            exit 1
            ;;
    esac
fi
for argument in "$@"; do
    if [[ "$is_fetch" == true && "$NIVORA_FETCH_MODE" == wrong \
        && "$argument" == "$NIVORA_FETCH_EXPECTED" ]]; then
        args+=("$NIVORA_FETCH_WRONG")
    else
        args+=("$argument")
    fi
done
exec "$NIVORA_REAL_GIT" "${args[@]}"
GIT
chmod +x "$scratch/mock-bin/git"

export PATH="$scratch/mock-bin:$PATH"
export NIVORA_REAL_GIT="$real_git"

export NIVORA_FETCH_MODE=transient
export NIVORA_FETCH_COUNT_FILE="$scratch/transient-count"
export NIVORA_FETCH_ARGS_LOG="$scratch/transient-args"
checkout="$scratch/transient-checkout"
mkdir -p "$checkout"
source "$repo_root/.github/tools/lib/pinned_git_checkout.sh"
pinned_git_checkout "$scratch/remote.git" "$pinned_sha" "$checkout"
[[ "$(git -C "$checkout" rev-parse HEAD)" == "$pinned_sha" ]]
[[ "$(<"$NIVORA_FETCH_COUNT_FILE")" == 3 ]]
grep -Fq -- '-c http.version=HTTP/1.1' "$NIVORA_FETCH_ARGS_LOG"
grep -Fq -- '-c http.connectTimeout=90' "$NIVORA_FETCH_ARGS_LOG"

export NIVORA_FETCH_MODE=permanent
export NIVORA_FETCH_COUNT_FILE="$scratch/permanent-count"
export NIVORA_FETCH_ARGS_LOG="$scratch/permanent-args"
permanent_checkout="$scratch/permanent-checkout"
mkdir -p "$permanent_checkout"
if pinned_git_checkout "$scratch/remote.git" "$pinned_sha" "$permanent_checkout" \
    >"$scratch/permanent.out" 2>"$scratch/permanent.err"; then
    echo 'permanent fetch failure was accepted' >&2
    exit 1
fi
[[ "$(<"$NIVORA_FETCH_COUNT_FILE")" == 3 ]]

export NIVORA_FETCH_MODE=wrong
export NIVORA_FETCH_COUNT_FILE="$scratch/wrong-count"
export NIVORA_FETCH_ARGS_LOG="$scratch/wrong-args"
export NIVORA_FETCH_EXPECTED="$pinned_sha"
export NIVORA_FETCH_WRONG="$wrong_sha"
wrong_checkout="$scratch/wrong-checkout"
mkdir -p "$wrong_checkout"
if pinned_git_checkout "$scratch/remote.git" "$pinned_sha" "$wrong_checkout" \
    >"$scratch/wrong.out" 2>"$scratch/wrong.err"; then
    echo 'nonmatching fetched commit was accepted' >&2
    exit 1
fi
grep -Fq "expected ${pinned_sha}, fetched ${wrong_sha}" "$scratch/wrong.err"

# Exercise the stplr-spec preparation path with a mock go command, never a real build.
mkdir -p "$scratch/mock-go-bin" "$scratch/spec-bin"
cat >"$scratch/mock-go-bin/go" <<'GO'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >"$NIVORA_GO_CALL_LOG"
[[ "$1" == install && "$*" == *'./cmd/stplr-spec' ]]
install -d "$GOBIN"
cat >"$GOBIN/stplr-spec" <<'SPEC'
#!/bin/sh
echo mock-stplr-spec
SPEC
chmod +x "$GOBIN/stplr-spec"
GO
chmod +x "$scratch/mock-go-bin/go"
export NIVORA_FETCH_MODE=normal
export NIVORA_FETCH_COUNT_FILE="$scratch/spec-fetch-count"
export NIVORA_FETCH_ARGS_LOG="$scratch/spec-fetch-args"
export NIVORA_GO_CALL_LOG="$scratch/go-call"
PATH="$scratch/mock-go-bin:$PATH" \
    STPLR_UTILS_COMMIT="$pinned_sha" \
    "$repo_root/.github/tools/prepare_stplr_spec.sh" \
    "$scratch/spec-bin/stplr-spec" "$scratch/remote.git"
[[ -x "$scratch/spec-bin/stplr-spec" ]]
[[ "$("$scratch/spec-bin/stplr-spec")" == mock-stplr-spec ]]
grep -Fq 'install -C ' "$NIVORA_GO_CALL_LOG"
grep -Fq './cmd/stplr-spec' "$NIVORA_GO_CALL_LOG"
[[ "$(<"$NIVORA_FETCH_COUNT_FILE")" == 1 ]]

action_file="$repo_root/.github/actions/setup-stplr-spec/action.yml"
restore_line="$(grep -n 'id: stplr-spec-cache' "$action_file" | cut -d: -f1)"
compile_line="$(grep -n 'id: compile-stplr-spec' "$action_file" | cut -d: -f1)"
save_line="$(grep -n 'actions/cache/save@55cc8345863c7cc4c66a329aec7e433d2d1c52a9' "$action_file" | cut -d: -f1)"
((restore_line < compile_line && compile_line < save_line)) || {
    echo 'stplr-spec cache restore/compile/save order is invalid' >&2
    exit 1
}
if grep -q 'restore-keys:' "$action_file"; then
    echo 'stplr-spec cache must not restore a stale prefix key' >&2
    exit 1
fi
grep -Fq 'runner.os' "$action_file"
grep -Fq 'runner.arch' "$action_file"
grep -Fq "ubuntu-24.04-go1.26.5-utils-c6ddbb5e4e5637d97bb7b2587729178d715c6c52-\${{ hashFiles" "$action_file"

echo 'OK: pinned source checkout retries transient failure, rejects bad SHA, and spec setup uses mocked Go'
