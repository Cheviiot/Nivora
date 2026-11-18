#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/nivora-stable-stplr.XXXXXX")"
cleanup() {
    find "$scratch" -mindepth 1 -delete
    rmdir "$scratch"
}
trap cleanup EXIT

fixture_root="$scratch/repo"
mkdir -p "$fixture_root/.github/tools/lib" "$scratch/mock-bin" "$scratch/downloads"
cp "$repo_root/.github/tools/prepare_stplr.sh" "$fixture_root/.github/tools/"
cp "$repo_root/.github/tools/lib/pinned_git_checkout.sh" "$fixture_root/.github/tools/lib/"
cp "$repo_root/.github/tools/lib/go_build.sh" "$fixture_root/.github/tools/lib/"

for architecture in x86_64 aarch64; do
    mkdir -p "$scratch/payload-$architecture"
    # Keep $1 literal: the generated fixture checks its own command argument.
    # shellcheck disable=SC2016
    printf '#!/bin/sh\n[ "$1" = version ] || exit 2\nprintf "v0.2.0 %s\\n"\n' \
        "$architecture" >"$scratch/payload-$architecture/stplr"
    tar -czf "$scratch/downloads/stplr-0.2.0-linux-$architecture.tar.gz" \
        -C "$scratch/payload-$architecture" stplr
done
x86_digest="$(sha256sum "$scratch/downloads/stplr-0.2.0-linux-x86_64.tar.gz")"
arm_digest="$(sha256sum "$scratch/downloads/stplr-0.2.0-linux-aarch64.tar.gz")"
cat >"$fixture_root/.github/support-matrix.toml" <<EOF
[stapler]
stable_version = "0.2.0"
stable_linux_x86_64_url = "https://altlinux.space/stapler/stplr/releases/download/v0.2.0/stplr-0.2.0-linux-x86_64.tar.gz"
stable_linux_x86_64_sha256 = "${x86_digest%% *}"
stable_linux_aarch64_url = "https://altlinux.space/stapler/stplr/releases/download/v0.2.0/stplr-0.2.0-linux-aarch64.tar.gz"
stable_linux_aarch64_sha256 = "${arm_digest%% *}"
EOF

cat >"$scratch/mock-bin/uname" <<'UNAME'
#!/bin/sh
[ "$1" = -m ] || exit 2
printf '%s\n' "$NIVORA_TEST_ARCH"
UNAME
cat >"$scratch/mock-bin/curl" <<'CURL'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >>"$NIVORA_TEST_DOWNLOAD_LOG"
[[ "${NIVORA_TEST_DOWNLOAD_FAIL:-0}" != 1 ]] || exit 7
destination=''
url="${!#}"
while (($#)); do
    if [[ "$1" == -o ]]; then
        destination="$2"
        shift 2
    else
        shift
    fi
done
[[ -n "$destination" ]]
if [[ "${NIVORA_TEST_DOWNLOAD_CORRUPT:-0}" == 1 ]]; then
    printf 'corrupted archive\n' >"$destination"
else
    cp "$NIVORA_TEST_DOWNLOADS/${url##*/}" "$destination"
fi
CURL
# Stable must use the release binary on ARM as well as x86_64.
cat >"$scratch/mock-bin/go" <<'GO'
#!/bin/sh
echo 'unexpected source build for stable' >&2
exit 99
GO
cp "$scratch/mock-bin/go" "$scratch/mock-bin/git"
chmod +x "$scratch/mock-bin/"*
export PATH="$scratch/mock-bin:$PATH"
export NIVORA_TEST_DOWNLOADS="$scratch/downloads"
export NIVORA_TEST_DOWNLOAD_LOG="$scratch/download.log"
export NIVORA_STPLR_CACHE_DIR="$scratch/cache"
export NIVORA_STPLR_CHANNEL=stable
export NIVORA_TEST_ARCH=x86_64
prepare="$fixture_root/.github/tools/prepare_stplr.sh"

# Download and execute only the verified x86_64 fixture.
"$prepare" "$scratch/bin/stplr-x86" >"$scratch/version"
grep -Fxq 'v0.2.0 x86_64' "$scratch/version"
[[ "$(wc -l <"$NIVORA_TEST_DOWNLOAD_LOG")" -eq 1 ]]

# A matching cached archive remains usable without network access.
NIVORA_TEST_DOWNLOAD_FAIL=1 "$prepare" "$scratch/bin/stplr-cached" >"$scratch/version"
grep -Fxq 'v0.2.0 x86_64' "$scratch/version"
[[ "$(wc -l <"$NIVORA_TEST_DOWNLOAD_LOG")" -eq 1 ]]

# Corrupt cached bytes must be replaced before extraction.
printf 'damaged cache\n' >"$NIVORA_STPLR_CACHE_DIR/stplr-0.2.0-linux-x86_64.tar.gz"
"$prepare" "$scratch/bin/stplr-repaired" >"$scratch/version"
grep -Fxq 'v0.2.0 x86_64' "$scratch/version"
[[ "$(wc -l <"$NIVORA_TEST_DOWNLOAD_LOG")" -eq 2 ]]

# ARM uses a distinct archive/cache key; its uname alias reuses the same archive.
NIVORA_TEST_ARCH=aarch64 "$prepare" "$scratch/bin/stplr-arm" >"$scratch/version"
grep -Fxq 'v0.2.0 aarch64' "$scratch/version"
NIVORA_TEST_ARCH=arm64 NIVORA_TEST_DOWNLOAD_FAIL=1 \
    "$prepare" "$scratch/bin/stplr-arm-alias" >"$scratch/version"
grep -Fxq 'v0.2.0 aarch64' "$scratch/version"
[[ "$(wc -l <"$NIVORA_TEST_DOWNLOAD_LOG")" -eq 3 ]]

# Failed integrity checks must preserve an existing target and leave no cache entry.
printf 'existing target\n' >"$scratch/existing-stplr"
if NIVORA_STPLR_CACHE_DIR="$scratch/bad-cache" NIVORA_TEST_DOWNLOAD_CORRUPT=1 \
    "$prepare" "$scratch/existing-stplr" >"$scratch/bad.out" 2>"$scratch/bad.err"; then
    echo 'stable helper accepted a corrupt release archive' >&2
    exit 1
fi
grep -Fq 'SHA-256 mismatch' "$scratch/bad.err"
grep -Fxq 'existing target' "$scratch/existing-stplr"
[[ -z "$(find "$scratch/bad-cache" -type f -print -quit)" ]]

# No accidental fallback to another architecture or to a source checkout.
downloads_before="$(wc -l <"$NIVORA_TEST_DOWNLOAD_LOG")"
if NIVORA_TEST_ARCH=riscv64 "$prepare" "$scratch/bin/unsupported" \
    >"$scratch/unsupported.out" 2>"$scratch/unsupported.err"; then
    echo 'stable helper accepted an unsupported architecture' >&2
    exit 1
fi
grep -Fq 'Unsupported architecture' "$scratch/unsupported.err"
[[ ! -f "$scratch/bin/unsupported" ]]
[[ "$(wc -l <"$NIVORA_TEST_DOWNLOAD_LOG")" -eq "$downloads_before" ]]

# Matching the pinned checksum is necessary but does not make an archive or
# executable usable. Neither extraction nor a failed smoke may destroy a tool.
for failure in missing-member broken-binary; do
    payload="$scratch/$failure"
    mkdir -p "$payload"
    if [[ "$failure" == missing-member ]]; then
        printf 'no executable here\n' >"$payload/other-file"
    else
        printf '#!/bin/sh\nexit 7\n' >"$payload/stplr"
    fi
    tar -czf "$scratch/downloads/stplr-0.2.0-linux-x86_64.tar.gz" -C "$payload" .
    # The production archive has a bare stplr entry; make that entry exact for
    # the executable failure case so the smoke, rather than tar, rejects it.
    if [[ "$failure" == broken-binary ]]; then
        tar -czf "$scratch/downloads/stplr-0.2.0-linux-x86_64.tar.gz" -C "$payload" stplr
    fi
    digest="$(sha256sum "$scratch/downloads/stplr-0.2.0-linux-x86_64.tar.gz")"
    sed -i -E "s/^(stable_linux_x86_64_sha256 = ).*/\1\"${digest%% *}\"/" \
        "$fixture_root/.github/support-matrix.toml"
    printf 'existing target\n' >"$scratch/existing-stplr"
    chmod 0755 "$scratch/existing-stplr"
    if NIVORA_STPLR_CACHE_DIR="$scratch/cache-$failure" \
        "$prepare" "$scratch/existing-stplr" >"$scratch/$failure.out" 2>"$scratch/$failure.err"; then
        echo "stable helper accepted ${failure}" >&2
        exit 1
    fi
    grep -Fxq 'existing target' "$scratch/existing-stplr" || {
        echo "stable helper destroyed the existing target after ${failure}" >&2
        exit 1
    }
    [[ "$(stat -c %a "$scratch/existing-stplr")" == 755 ]]
    [[ -z "$(find "$scratch" -maxdepth 1 -name 'existing-stplr.tmp.*' -print -quit)" ]]
done

echo 'OK: verified stable archives, ARM binaries and atomic replacement after smoke'
