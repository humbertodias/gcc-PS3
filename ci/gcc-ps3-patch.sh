#!/bin/sh
# Patch for ps3toolchain: GCC delta only (no Docker / GitHub Actions / CI blobs).
#
#   ./ci/gcc-ps3-patch.sh > gcc-13.2.0-PS3.patch
#   ./ci/gcc-ps3-patch.sh --stat
#   FROM=upstream TO=master ./ci/gcc-ps3-patch.sh
#
# Extra args are passed to git diff (e.g. --stat, -w).
set -eu
cd "$(git rev-parse --show-toplevel)"
from="${FROM:-upstream}"
to="${TO:-HEAD}"
echo "git diff $* $from $to  (excluding ci, .github, Docker)" >&2
git diff "$@" "$from" "$to" -- \
  ':!ci' \
  ':!.github' \
  ':!Dockerfile' \
  ':!.dockerignore' \
  ':!.gitignore'
