#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PACKAGE_UPDATES_LIB_ONLY=1
# shellcheck source=.github/tools/package_updates.sh
source "${repo_root}/.github/tools/package_updates.sh"

version_is_newer 2.0.0 1.9.9
version_is_newer 1.10.0 1.9.9
version_is_newer release-3.6.4 release-3.6.3
if version_is_newer 1.9.9 2.0.0; then
    echo 'downgrade was incorrectly accepted' >&2
    exit 1
fi
if version_is_newer 2.0.0 2.0.0; then
    echo 'equal version was incorrectly accepted' >&2
    exit 1
fi
if version_is_newer 1.0.0-rc.1 1.0.0; then
    echo 'prerelease was incorrectly treated as newer than stable' >&2
    exit 1
fi

echo 'OK: package updater rejects downgrades'

github_latest_release() {
	[[ "$1" == 'Cheviiot/Casement' ]]
	printf '%s\n' 'v0.1.0'
}

require_package casement
[[ "$(latest_version casement)" == '0.1.0' ]]
echo 'OK: Casement updater follows the latest stable GitHub release tag'
