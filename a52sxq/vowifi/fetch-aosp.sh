#!/usr/bin/env bash
# Fetches AOSP Iwlan and QualifiedNetworksService at the commits this package was tested
# with (android17-release) into a52sxq/vowifi/aosp/ and applies the a52sxq patches.
set -euo pipefail
VW=$(cd "$(dirname "$0")" && pwd)
fetch() {  # fetch <dir> <aosp project> <commit>
  local dir=$VW/aosp/$1 project=$2 commit=$3
  if [ ! -d "$dir/.git" ]; then
    git clone -q --filter=blob:none --no-checkout \
      "https://android.googlesource.com/platform/packages/services/$project" "$dir"
  fi
  git -C "$dir" fetch -q --depth 1 origin "$commit" 2>/dev/null || git -C "$dir" fetch -q origin
  git -C "$dir" checkout -q -B a52sxq "$commit"
  for p in "$VW"/patches/"$1"/*.patch; do
    [ -e "$p" ] || continue
    git -C "$dir" -c user.name=a52sxq -c user.email=a52sxq@localhost am -q "$p"
  done
  echo "$1: $(git -C "$dir" log --oneline -1)"
}
fetch iwlan Iwlan ddf0eb7f277ea6a5a62c63678d17218714f38071
fetch qns QualifiedNetworksService f1500926b882a189c7c5772368835d5de700b34f
