#!/bin/bash
set -euo pipefail

readonly results_dir="${AUTONOMOUS_UPDATE_RESULTS_DIR:?AUTONOMOUS_UPDATE_RESULTS_DIR is required}"
readonly detected_packages_json="${DETECTED_PACKAGES_JSON:?DETECTED_PACKAGES_JSON is required}"
readonly expected_updates_json="${EXPECTED_UPDATES_JSON:?EXPECTED_UPDATES_JSON is required}"
readonly expected_github_desktop_commit="${EXPECTED_GITHUB_DESKTOP_COMMIT:-}"

semantic_tmp=''
cleanup() {
    if [[ -n "$semantic_tmp" && -d "$semantic_tmp" ]]; then
        find "$semantic_tmp" -mindepth 1 -delete
        rmdir "$semantic_tmp"
    fi
}
trap cleanup EXIT

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"

die() {
    echo "validate_update_artifact: $*" >&2
    exit 1
}

is_safe_package() {
    [[ "$1" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]
}

is_safe_phase() {
    case "$1" in
    detect-version | prepare-worktree | update-recipe | pin-upstream-commit | \
        sync-catalog | static-checks | clean-build | verify-artifact | \
        no-update-diff | pin-source-fingerprint)
        return 0
        ;;
    *) return 1 ;;
    esac
}

require_regular_file() {
    local path="$1"
    [[ -f "$path" && ! -L "$path" ]] ||
        die "expected a regular file: ${path}"
}

[[ -d "$results_dir" && ! -L "$results_dir" ]] ||
    die "results path must be a real directory: ${results_dir}"

invalid_node="$(
    find "$results_dir" -mindepth 1 ! -type f ! -type d -print -quit
)"
[[ -z "$invalid_node" ]] ||
    die "symlink or non-regular artifact node is forbidden: ${invalid_node}"

hardlinked_file="$(
    find "$results_dir" -type f -links +1 -print -quit
)"
[[ -z "$hardlinked_file" ]] ||
    die "hard-linked artifact file is forbidden: ${hardlinked_file}"

oversized_file="$(
    find "$results_dir" -type f -size +10M -print -quit
)"
[[ -z "$oversized_file" ]] ||
    die "artifact file exceeds the 10 MiB limit: ${oversized_file}"

detected_output=''
if ! detected_output="$({
    DETECTED_PACKAGES_JSON="$detected_packages_json" python3 - <<'PY'
import json
import os
import sys

try:
    value = json.loads(os.environ["DETECTED_PACKAGES_JSON"])
except (KeyError, json.JSONDecodeError) as error:
    print(f"invalid DETECTED_PACKAGES_JSON: {error}", file=sys.stderr)
    raise SystemExit(1)

if not isinstance(value, list) or any(not isinstance(item, str) for item in value):
    print("DETECTED_PACKAGES_JSON must be an array of strings", file=sys.stderr)
    raise SystemExit(1)

for item in value:
    print(item)
PY
})"; then
    die 'cannot parse DETECTED_PACKAGES_JSON'
fi

declare -a detected_packages=()
if [[ -n "$detected_output" ]]; then
    mapfile -t detected_packages < <(printf '%s\n' "$detected_output")
fi

declare -A detected=()
for package in "${detected_packages[@]}"; do
    is_safe_package "$package" || die "unsafe detected package name: ${package}"
    [[ -z "${detected[$package]:-}" ]] ||
        die "duplicate detected package: ${package}"
    [[ -d "${repo_root}/${package}" && ! -L "${repo_root}/${package}" ]] ||
        die "unknown detected package: ${package}"
    require_regular_file "${repo_root}/${package}/Staplerfile"
    detected[$package]=1
done

expected_output=''
if ! expected_output="$({
    EXPECTED_UPDATES_JSON="$expected_updates_json" python3 - <<'PY'
import json
import os
import re

value = json.loads(os.environ["EXPECTED_UPDATES_JSON"])
if not isinstance(value, dict):
    raise SystemExit("EXPECTED_UPDATES_JSON must be an object")
safe = re.compile(r"^[0-9A-Za-z.+~_-]+$")
fingerprint = re.compile(r"^[0-9a-f]{64}$")
for package, versions in value.items():
    expected_keys = {
        "chatgpt": {"source_fingerprint_amd64", "source_fingerprint_arm64"},
        "parsec": {"source_fingerprint"},
    }.get(package, set())
    if (
        not isinstance(package, str)
        or not isinstance(versions, dict)
        or set(versions) != {"current", "latest", "fingerprints"}
        or not all(isinstance(versions[key], str) for key in ("current", "latest"))
        or not isinstance(versions["fingerprints"], dict)
        or set(versions["fingerprints"]) != expected_keys
        or any(
            not isinstance(item, str) or not fingerprint.fullmatch(item)
            for item in versions["fingerprints"].values()
        )
        or not safe.fullmatch(versions["current"])
        or not safe.fullmatch(versions["latest"])
    ):
        raise SystemExit(f"invalid expected update entry: {package!r}")
    print(
        package,
        versions["current"],
        versions["latest"],
        json.dumps(versions["fingerprints"], sort_keys=True, separators=(",", ":")),
        sep="\t",
    )
PY
})"; then
    die 'cannot parse EXPECTED_UPDATES_JSON'
fi

declare -A expected_current=()
declare -A expected_latest=()
declare -A expected_fingerprints=()
if [[ -n "$expected_output" ]]; then
    while IFS=$'\t' read -r package current latest fingerprints extra; do
        [[ -z "${extra:-}" ]] || die "malformed expected update for ${package}"
        is_safe_package "$package" || die "unsafe package in expected updates: ${package}"
        [[ -n "${detected[$package]:-}" ]] ||
            die "expected update was not detected: ${package}"
        expected_current[$package]="$current"
        expected_latest[$package]="$latest"
        expected_fingerprints[$package]="$fingerprints"
    done <<<"$expected_output"
fi

readonly successful_file="${results_dir}/successful-packages"
readonly failed_file="${results_dir}/failed-packages"
readonly checked_file="${results_dir}/checked-packages"
require_regular_file "$successful_file"
require_regular_file "$failed_file"
require_regular_file "$checked_file"

declare -A checked=()
while IFS= read -r package || [[ -n "$package" ]]; do
    is_safe_package "$package" || die "unsafe package in checked-packages: ${package}"
    [[ -n "${detected[$package]:-}" ]] ||
        die "unknown package in checked-packages: ${package}"
    [[ -z "${checked[$package]:-}" ]] ||
        die "duplicate package in checked-packages: ${package}"
    checked[$package]=1
done <"$checked_file"

declare -A successful=()
while IFS= read -r package || [[ -n "$package" ]]; do
    is_safe_package "$package" ||
        die "unsafe package in successful-packages: ${package}"
    [[ -n "${detected[$package]:-}" ]] ||
        die "unknown package in successful-packages: ${package}"
    [[ -z "${successful[$package]:-}" ]] ||
        die "duplicate package in successful-packages: ${package}"
    successful[$package]=1
done <"$successful_file"

declare -A failed=()
declare -A failed_phase=()
while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" == *$'\t'* ]] || die "malformed failed-packages row: ${line}"
    package="${line%%$'\t'*}"
    phase="${line#*$'\t'}"
    [[ "$phase" != *$'\t'* ]] || die "malformed failed-packages row: ${line}"
    is_safe_package "$package" || die "unsafe package in failed-packages: ${package}"
    is_safe_phase "$phase" || die "unsafe or unknown failure phase for ${package}: ${phase}"
    [[ -n "${detected[$package]:-}" ]] ||
        die "unknown package in failed-packages: ${package}"
    [[ -z "${failed[$package]:-}" ]] ||
        die "duplicate package in failed-packages: ${package}"
    [[ -z "${successful[$package]:-}" ]] ||
        die "package is both successful and failed: ${package}"
    failed[$package]=1
    failed_phase[$package]="$phase"
done <"$failed_file"

declare -A allowed_root_files=(
    [successful-packages]=1
    [failed-packages]=1
    [checked-packages]=1
)
while IFS= read -r -d '' entry; do
    name="${entry##*/}"
    if [[ -d "$entry" ]]; then
        is_safe_package "$name" || die "unsafe result directory name: ${name}"
        [[ -n "${detected[$name]:-}" ]] || die "unknown result directory: ${name}"
    else
        [[ -n "${allowed_root_files[$name]:-}" ]] ||
            die "unknown top-level artifact file: ${name}"
    fi
done < <(find "$results_dir" -mindepth 1 -maxdepth 1 -print0)

for package in "${detected_packages[@]}"; do
    [[ -n "${checked[$package]:-}" ]] ||
        die "detected package is missing from checked-packages: ${package}"
    [[ -n "${successful[$package]:-}" || -n "${failed[$package]:-}" ]] ||
        die "detected package has no success or failure result: ${package}"
    package_dir="${results_dir}/${package}"
    [[ -d "$package_dir" && ! -L "$package_dir" ]] ||
        die "missing result directory for ${package}"
    if find "$package_dir" -mindepth 1 -type d -print -quit | grep -q .; then
        die "nested result directories are forbidden for ${package}"
    fi

    declare -A allowed_package_files=(
        [FAILED]=1
        [Staplerfile.after]=1
        [failed.patch]=1
        [phase]=1
        [result]=1
        [update.log]=1
        [update.patch]=1
        [worktree.log]=1
    )
    while IFS= read -r -d '' package_file; do
        package_filename="${package_file##*/}"
        [[ -n "${allowed_package_files[$package_filename]:-}" ]] ||
            die "unknown result file for ${package}: ${package_filename}"
    done < <(find "$package_dir" -mindepth 1 -maxdepth 1 -type f -print0)

    require_regular_file "${package_dir}/result"
    result="$(<"${package_dir}/result")"
    require_regular_file "${package_dir}/phase"
    phase="$(<"${package_dir}/phase")"
    is_safe_phase "$phase" || die "unsafe phase marker for ${package}: ${phase}"

    if [[ -n "${successful[$package]:-}" ]]; then
        [[ -n "${expected_latest[$package]:-}" ]] ||
            die "successful package has no trusted expected version: ${package}"
        [[ "$result" == success ]] || die "invalid success marker for ${package}"
        [[ "$phase" == verify-artifact ]] ||
            die "successful package ended in the wrong phase: ${package}: ${phase}"
        [[ ! -e "${package_dir}/FAILED" ]] ||
            die "successful package has a FAILED marker: ${package}"
        patch="${package_dir}/update.patch"
        require_regular_file "$patch"
        [[ -s "$patch" ]] || die "empty update patch for ${package}"

        if ! numstat="$(cd "$repo_root" && git apply --numstat -- "$patch")"; then
            die "cannot parse update patch for ${package}"
        fi
        mapfile -t numstat_lines < <(printf '%s\n' "$numstat")
        [[ "${#numstat_lines[@]}" -eq 1 ]] ||
            die "update patch for ${package} must change exactly one path"
        IFS=$'\t' read -r additions deletions changed_path extra <<<"${numstat_lines[0]}"
        [[ "$additions" =~ ^[0-9]+$ && "$deletions" =~ ^[0-9]+$ ]] ||
            die "binary patch is forbidden for ${package}"
        [[ -z "${extra:-}" && "$changed_path" == "${package}/Staplerfile" ]] ||
            die "update patch for ${package} changes forbidden path: ${changed_path}"

        if ! summary="$(cd "$repo_root" && git apply --summary -- "$patch")"; then
            die "cannot summarize update patch for ${package}"
        fi
        [[ -z "$summary" ]] ||
            die "created, deleted, renamed, copied, or mode-changed paths are forbidden for ${package}"
        (cd "$repo_root" && git apply --check -- "$patch") ||
            die "update patch does not apply cleanly for ${package}"

        semantic_tmp="$(mktemp -d)"
        install -d "${semantic_tmp}/${package}"
        cp "${repo_root}/${package}/Staplerfile" \
            "${semantic_tmp}/${package}/Staplerfile"
        (cd "$semantic_tmp" && git apply --whitespace=nowarn -- "$patch") ||
            die "cannot materialize update patch for ${package}"
        if ! TRUSTED_RECIPE="${repo_root}/${package}/Staplerfile" \
            CANDIDATE_RECIPE="${semantic_tmp}/${package}/Staplerfile" \
            PACKAGE_ID="$package" \
            EXPECTED_CURRENT="${expected_current[$package]}" \
            EXPECTED_LATEST="${expected_latest[$package]}" \
            EXPECTED_FINGERPRINTS="${expected_fingerprints[$package]}" \
            EXPECTED_GITHUB_DESKTOP_COMMIT="$expected_github_desktop_commit" \
            python3 - <<'PY'
import os
import re
from pathlib import Path

trusted_path = Path(os.environ["TRUSTED_RECIPE"])
candidate_path = Path(os.environ["CANDIDATE_RECIPE"])
package = os.environ["PACKAGE_ID"]
expected_current = os.environ["EXPECTED_CURRENT"]
expected_latest = os.environ["EXPECTED_LATEST"]
expected_fingerprints = __import__("json").loads(os.environ["EXPECTED_FINGERPRINTS"])
expected_github_desktop_commit = os.environ["EXPECTED_GITHUB_DESKTOP_COMMIT"]
trusted = trusted_path.read_text(encoding="utf-8").splitlines()
candidate = candidate_path.read_text(encoding="utf-8").splitlines()

if len(trusted) != len(candidate):
    raise SystemExit("recipe line count changed")

array_start = re.compile(r"^(sources|checksums)(_[a-z0-9_]+)?=\($")
quoted_value = re.compile(r"^[ \t]*(['\"])(.*)\1[ \t]*$")
checksum_value = re.compile(r"^[ \t]*(['\"])(?:sha256:)?([0-9a-f]{64})\1[ \t]*$")
version_value = re.compile(
    r"^version=(?:'([0-9A-Za-z.+~_-]+)'|\"([0-9A-Za-z.+~_-]+)\"|"
    r"([0-9A-Za-z.+~_-]+))$"
)
commit_value = re.compile(r"^upstream_commit='([0-9a-f]{40})'$")
release_value = re.compile(r"^release=([1-9][0-9]*)$")
fingerprint_value = re.compile(
    r"^(source_fingerprint(?:_(?:amd64|arm64))?)='([0-9a-f]{64})'$")


def arrays(lines: list[str]) -> dict[str, list[tuple[int, str]]]:
    parsed: dict[str, list[tuple[int, str]]] = {}
    current: str | None = None
    for index, line in enumerate(lines):
        if current is None:
            match = array_start.fullmatch(line)
            if match:
                current = match.group(1) + (match.group(2) or "")
                parsed[current] = []
            continue
        if line == ")":
            current = None
            continue
        match = quoted_value.fullmatch(line)
        if not match:
            raise SystemExit(f"cannot parse {current} entry on line {index + 1}")
        parsed[current].append((index, match.group(2)))
    if current is not None:
        raise SystemExit(f"unterminated array: {current}")
    return parsed


trusted_arrays = arrays(trusted)
candidate_arrays = arrays(candidate)
if trusted_arrays.keys() != candidate_arrays.keys():
    raise SystemExit("source/checksum array structure changed")

allowed_remote_checksum_lines: set[int] = set()
for source_name, source_entries in trusted_arrays.items():
    if not source_name.startswith("sources"):
        continue
    checksum_name = source_name.replace("sources", "checksums", 1)
    trusted_checksums = trusted_arrays.get(checksum_name)
    candidate_sources = candidate_arrays.get(source_name)
    candidate_checksums = candidate_arrays.get(checksum_name)
    if (
        trusted_checksums is None
        or candidate_sources is None
        or candidate_checksums is None
        or len(source_entries) != len(trusted_checksums)
        or len(source_entries) != len(candidate_sources)
        or len(source_entries) != len(candidate_checksums)
    ):
        raise SystemExit(f"source/checksum cardinality changed for {source_name}")
    for offset, ((_, source), (candidate_source_line, candidate_source)) in enumerate(
        zip(source_entries, candidate_sources, strict=True)
    ):
        if source != candidate_source:
            raise SystemExit(
                f"source entry changed on line {candidate_source_line + 1}"
            )
        if source.startswith(("https://", "git+")):
            allowed_remote_checksum_lines.add(trusted_checksums[offset][0])

trusted_version_matches = [version_value.fullmatch(line) for line in trusted]
candidate_version_matches = [version_value.fullmatch(line) for line in candidate]
trusted_version_values = [
    next(group for group in match.groups() if group is not None)
    for match in trusted_version_matches
    if match is not None
]
candidate_version_values = [
    next(group for group in match.groups() if group is not None)
    for match in candidate_version_matches
    if match is not None
]
if trusted_version_values != [expected_current]:
    raise SystemExit("trusted recipe version differs from detection plan")
if candidate_version_values != [expected_latest]:
    raise SystemExit("candidate recipe version differs from detection plan")

trusted_releases = [
    int(match.group(1))
    for line in trusted
    if (match := release_value.fullmatch(line)) is not None
]
candidate_releases = [
    int(match.group(1))
    for line in candidate
    if (match := release_value.fullmatch(line)) is not None
]
if len(trusted_releases) != 1 or len(candidate_releases) != 1:
    raise SystemExit("recipe must contain exactly one positive release")
expected_release = 1 if expected_current != expected_latest else trusted_releases[0] + 1
if candidate_releases != [expected_release]:
    raise SystemExit(f"candidate release must be {expected_release}")

required_fingerprints = {
    "chatgpt": {"source_fingerprint_amd64", "source_fingerprint_arm64"},
    "parsec": {"source_fingerprint"},
}.get(package, set())
trusted_fingerprints = {
    match.group(1): match.group(2)
    for line in trusted
    if (match := fingerprint_value.fullmatch(line)) is not None
}
candidate_fingerprints = {
    match.group(1): match.group(2)
    for line in candidate
    if (match := fingerprint_value.fullmatch(line)) is not None
}
if set(trusted_fingerprints) != required_fingerprints:
    raise SystemExit("trusted recipe has invalid mutable-source fingerprints")
if set(candidate_fingerprints) != required_fingerprints:
    raise SystemExit("candidate recipe has invalid mutable-source fingerprints")
if candidate_fingerprints != expected_fingerprints:
    raise SystemExit("candidate mutable-source fingerprints differ from detection plan")

if package == "github-desktop":
    if not re.fullmatch(r"[0-9a-f]{40}", expected_github_desktop_commit):
        raise SystemExit("trusted GitHub Desktop commit is missing")
    candidate_commits = [
        match.group(1)
        for line in candidate
        if (match := commit_value.fullmatch(line)) is not None
    ]
    if candidate_commits != [expected_github_desktop_commit]:
        raise SystemExit("candidate GitHub Desktop commit differs from build output")

changed = 0
changed_checksum = 0
changed_fingerprint = 0
for index, (before, after) in enumerate(zip(trusted, candidate, strict=True)):
    if before == after:
        continue
    changed += 1
    if version_value.fullmatch(before) and version_value.fullmatch(after):
        continue
    if release_value.fullmatch(before) and release_value.fullmatch(after):
        continue
    if (
        package == "github-desktop"
        and commit_value.fullmatch(before)
        and commit_value.fullmatch(after)
    ):
        continue
    if index in allowed_remote_checksum_lines:
        if checksum_value.fullmatch(before) and checksum_value.fullmatch(after):
            changed_checksum += 1
            continue
    before_fingerprint = fingerprint_value.fullmatch(before)
    after_fingerprint = fingerprint_value.fullmatch(after)
    if (
        before_fingerprint is not None
        and after_fingerprint is not None
        and before_fingerprint.group(1) == after_fingerprint.group(1)
        and before_fingerprint.group(1) in required_fingerprints
    ):
        changed_fingerprint += 1
        continue
    raise SystemExit(f"forbidden recipe change on line {index + 1}")

if changed == 0:
    raise SystemExit("recipe patch has no semantic change")
if changed_checksum == 0:
    raise SystemExit("update changed no remote source checksum")
if expected_current == expected_latest and changed_fingerprint == 0:
    raise SystemExit("same-version source refresh changed no fingerprint")
PY
        then
            die "update patch changes forbidden recipe content for ${package}"
        fi
        find "$semantic_tmp" -mindepth 1 -delete
        rmdir "$semantic_tmp"
        semantic_tmp=''
    else
        [[ "$result" == failure ]] || die "invalid failure marker for ${package}"
        [[ "$phase" == "${failed_phase[$package]}" ]] ||
            die "failure phase marker mismatch for ${package}"
        require_regular_file "${package_dir}/FAILED"
        grep -Fxq "package=${package}" "${package_dir}/FAILED" ||
            die "FAILED marker has the wrong package for ${package}"
        grep -Fxq "phase=${failed_phase[$package]}" "${package_dir}/FAILED" ||
            die "FAILED marker has the wrong phase for ${package}"
        [[ ! -e "${package_dir}/update.patch" ]] ||
            die "failed package contains an update patch: ${package}"
    fi
done

echo "OK: update artifact is complete and safe (${#detected_packages[@]} packages)"
