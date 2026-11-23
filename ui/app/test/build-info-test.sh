#!/bin/sh
# Checks the build information shown in the About dialog.
#
# 1. cmake/modules/BuildInfo.cmake, run in throwaway source trees: what it
#    records for a branch, a detached HEAD, a modified tree, no git at all,
#    and a fixed build date; and that it leaves its output alone when the
#    source state has not changed.
# 2. The workrave binary carries what the build recorded in BuildInfoData.h.
#
# It never compares with the current HEAD of the real source tree: that
# changes with every commit, and a test must not fail because of one.
#
# Usage: build-info-test.sh cmake /path/to/BuildInfo.cmake /path/to/workrave /path/to/BuildInfoData.h
# Exit codes: 0 pass, 1 fail, 77 skipped (git is not installed).

set -eu

cmake=${1:?usage: $0 cmake BuildInfo.cmake workrave BuildInfoData.h}
script=${2:?usage: $0 cmake BuildInfo.cmake workrave BuildInfoData.h}
workrave=${3:?usage: $0 cmake BuildInfo.cmake workrave BuildInfoData.h}
recorded=${4:?usage: $0 cmake BuildInfo.cmake workrave BuildInfoData.h}

if ! command -v git >/dev/null 2>&1; then
  echo "SKIP: git not found"
  exit 77
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
status=0

fail() {
  echo "FAIL: $1"
  status=1
}

# Runs the generator on source tree $1, writing $1.h.
generate() {
  "$cmake" -DSOURCE_DIR="$1" -DOUTPUT="$1.h" -P "$script"
}

# The value of #define WORKRAVE_BUILD_INFO_$2 in header $1, without quotes.
value() {
  sed -n "s/^#define WORKRAVE_BUILD_INFO_$2 \"\(.*\)\"\$/\1/p" "$1"
}

expect() {
  if [ "$2" != "$3" ]; then
    fail "$1: got '$2', want '$3'"
  fi
}

# A source tree with one commit on branch $2.
new_tree() {
  mkdir "$1"
  git -C "$1" init -q -b "$2"
  echo one >"$1/file"
  git -C "$1" add file
  git -C "$1" -c user.name=test -c user.email=test@example.invalid commit -q -m one
}

# Keep the caller's environment out of the generator.
unset WORKRAVE_BUILD_DATETIME WORKRAVE_GIT_BRANCH WORKRAVE_COMMIT_HASH SOURCE_DATE_EPOCH

# --- a branch, with a name shorter than four characters
tree=$work/branch
new_tree "$tree" rym
generate "$tree"
commit=$(git -C "$tree" rev-parse --short=10 HEAD)
expect "branch" "$(value "$tree.h" BRANCH)" "rym"
expect "commit" "$(value "$tree.h" COMMIT)" "$commit"
case $(value "$tree.h" DATETIME) in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\ [0-9][0-9]:[0-9][0-9]:[0-9][0-9]\ *\ \([+-][0-9][0-9][0-9][0-9]\)) ;;
  *) fail "build date: got '$(value "$tree.h" DATETIME)', want something like '2026-11-23 17:05:12 EST (-0500)'" ;;
esac

# --- unchanged source state: the output is left alone, date included
cp "$tree.h" "$tree.before"
sleep 1
generate "$tree"
if ! cmp -s "$tree.h" "$tree.before"; then
  fail "the header was rewritten although the source state did not change"
fi

# --- a tracked file modified: marked, and the output is rewritten
echo two >"$tree/file"
generate "$tree"
expect "modified tree" "$(value "$tree.h" COMMIT)" "$commit (modified)"
if cmp -s "$tree.h" "$tree.before"; then
  fail "the header was not rewritten after a tracked file changed"
fi

# --- a detached HEAD, as on a CI checkout
tree=$work/detached
new_tree "$tree" main
git -C "$tree" checkout -q --detach
generate "$tree"
expect "detached HEAD" "$(value "$tree.h" BRANCH)" "detached HEAD"
expect "detached commit" "$(value "$tree.h" COMMIT)" "$(git -C "$tree" rev-parse --short=10 HEAD)"

# --- not a git tree, as when built from a release tarball: nothing to show
tree=$work/tarball
mkdir "$tree"
# A parent directory may be a git tree; stop git from looking further up.
GIT_CEILING_DIRECTORIES=$work generate "$tree"
expect "no git: branch" "$(value "$tree.h" BRANCH)" ""
expect "no git: commit" "$(value "$tree.h" COMMIT)" ""

# --- a reproducible build: the date comes from SOURCE_DATE_EPOCH
tree=$work/reproducible
new_tree "$tree" main
SOURCE_DATE_EPOCH=0 generate "$tree"
expect "SOURCE_DATE_EPOCH" "$(value "$tree.h" DATETIME)" "1970-01-01 00:00:00 UTC (+0000)"

# --- values given by the packager
tree=$work/overrides
new_tree "$tree" main
WORKRAVE_BUILD_DATETIME="some day" WORKRAVE_GIT_BRANCH=release WORKRAVE_COMMIT_HASH=0123456789abcdef generate "$tree"
expect "given date" "$(value "$tree.h" DATETIME)" "some day"
expect "given branch" "$(value "$tree.h" BRANCH)" "release"
expect "given commit" "$(value "$tree.h" COMMIT)" "0123456789"

# --- the binary carries what its build recorded
if [ ! -f "$recorded" ]; then
  fail "$recorded not found"
else
  for name in DATETIME BRANCH COMMIT; do
    want=$(value "$recorded" "$name")
    # grep, not strings: strings drops anything shorter than four characters.
    if [ -n "$want" ] && ! grep -a -F -q -- "$want" "$workrave"; then
      fail "$workrave does not contain its recorded $name '$want'"
    fi
  done
fi

if [ $status = 0 ]; then
  echo "PASS: build information is recorded as expected"
fi
exit $status
