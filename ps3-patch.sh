#!/bin/sh
# Emit the GCC delta for ps3toolchain (Docker / GitHub Actions omitted).
#
#   ./ps3-patch.sh > gcc-13.2.0-PS3.patch
#   ./ps3-patch.sh --stat
#   FROM=upstream TO=master ./ps3-patch.sh
#
# Extra args are passed to git diff (e.g. --stat, -w). This file is
# excluded from its own output so the patch stays compiler-only.
set -eu
cd "$(git rev-parse --show-toplevel)"
from="${FROM:-upstream}"
to="${TO:-HEAD}"
echo "git diff $* $from $to  (excluding CI/Docker; see $0)" >&2
git diff "$@" "$from" "$to" -- \
  ':!ci' \
  ':!.github' \
  ':!Dockerfile' \
  ':!.dockerignore' \
  ':!.gitignore' \
  ':!ps3-patch.sh'
