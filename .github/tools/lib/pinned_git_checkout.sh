#!/bin/bash

# Initialize a minimal checkout of one immutable commit, retrying transient fetch
# failures while refusing to accept a different object as the pinned revision.
pinned_git_checkout() {
    local repository="${1:?usage: pinned_git_checkout REPOSITORY COMMIT DIRECTORY}"
    local commit="${2:?usage: pinned_git_checkout REPOSITORY COMMIT DIRECTORY}"
    local checkout="${3:?usage: pinned_git_checkout REPOSITORY COMMIT DIRECTORY}"
    local attempt fetched=false actual

    [[ "$commit" =~ ^[0-9a-f]{40}$ ]] || {
        echo 'pinned_git_checkout: commit must be a 40-character lowercase SHA' >&2
        return 2
    }

    git init -q "$checkout" || return
    git -C "$checkout" remote add origin "$repository" || return
    for attempt in 1 2 3; do
        if timeout 90s git \
            -c http.version=HTTP/1.1 \
            -c http.connectTimeout=90 \
            -c http.lowSpeedLimit=20 \
            -c http.lowSpeedTime=90 \
            -C "$checkout" fetch -q --no-tags --depth=1 origin "$commit"; then
            fetched=true
            break
        fi
        echo "pinned_git_checkout: fetch attempt ${attempt}/3 failed for ${commit}" >&2
        if ((attempt < 3)); then
            sleep "$attempt"
        fi
    done
    [[ "$fetched" == true ]] || {
        echo "pinned_git_checkout: unable to fetch pinned commit ${commit} after 3 attempts" >&2
        return 1
    }

    git -C "$checkout" checkout -q --detach FETCH_HEAD || return
    actual="$(git -C "$checkout" rev-parse --verify HEAD)" || return
    [[ "$actual" == "$commit" ]] || {
        echo "pinned_git_checkout: expected ${commit}, fetched ${actual}" >&2
        return 1
    }
}
