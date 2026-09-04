#!/bin/bash
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
staplerfile="${package_dir}/Staplerfile"

for field in deps_debian deps_ubuntu deps_arch deps_fedora deps_opensuse deps_altlinux; do
    grep -Eq "^${field}=\(" "$staplerfile"
done

for field in auto_req_altlinux auto_req_fedora auto_req_opensuse; do
    grep -Fq "${field}=1" "$staplerfile"
done

grep -Fq 'auto_req=0' "$staplerfile"
grep -Fq 'auto_prov=0' "$staplerfile"
! grep -Eq '^auto_prov_[a-z0-9_]+=1' "$staplerfile"
