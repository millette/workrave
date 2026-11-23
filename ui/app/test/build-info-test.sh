#!/bin/sh
# Checks that the workrave binary carries the build information shown in the
# About dialog: the build date and time with time zone, the git branch and
# the git commit of the source tree it was built from.
#
# Usage: build-info-test.sh /path/to/workrave /path/to/source
# Exit codes: 0 pass, 1 fail, 77 skipped (missing tool or not a git tree).

set -eu

workrave=${1:?usage: $0 /path/to/workrave /path/to/source}
source_dir=${2:?usage: $0 /path/to/workrave /path/to/source}

for tool in git strings; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "SKIP: $tool not found"
    exit 77
  fi
done
if ! git -C "$source_dir" rev-parse HEAD >/dev/null 2>&1; then
  echo "SKIP: $source_dir is not a git work tree"
  exit 77
fi

commit=$(git -C "$source_dir" rev-parse --short=10 HEAD)
branch=$(git -C "$source_dir" rev-parse --abbrev-ref HEAD)

found_commit=no
found_branch=no
found_datetime=no
lines=$(mktemp)
trap 'rm -f "$lines"' EXIT
strings "$workrave" >"$lines"
while IFS= read -r line; do
  case $line in
    "$commit" | "$commit (modified)") found_commit=yes ;;
  esac
  if [ "$line" = "$branch" ]; then
    found_branch=yes
  fi
  case $line in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\ [0-9][0-9]:[0-9][0-9]:[0-9][0-9]\ *\ \([+-][0-9][0-9][0-9][0-9]\))
      found_datetime=yes
      ;;
  esac
done <"$lines"

status=0
if [ $found_commit != yes ]; then
  echo "FAIL: commit $commit not found in $workrave"
  status=1
fi
if [ $found_branch != yes ]; then
  echo "FAIL: branch $branch not found in $workrave"
  status=1
fi
if [ $found_datetime != yes ]; then
  echo "FAIL: no build date like '2026-11-23 17:05:12 EST (-0500)' in $workrave"
  status=1
fi
if [ $status = 0 ]; then
  echo "PASS: $workrave was built from $branch $commit"
fi
exit $status
