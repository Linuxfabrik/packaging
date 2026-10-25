#!/usr/bin/env bash
#
# Author:  Linuxfabrik GmbH, Zurich, Switzerland
# Contact: info (at) linuxfabrik (dot) ch
#          https://www.linuxfabrik.ch/
# License: The Unlicense, see LICENSE file.
#
# Print the packages touched between two commits, one name per line, sorted.
# A package counts as touched when anything below packages/<name>/ changed and
# the directory still exists.
#
# Usage: changed-packages.sh [--include-build] <base> <head>
#
# With --include-build, a change below build/ prints every package, because the
# shared build scripts and containerfiles affect all of them. If <base> is not a
# known commit (e.g. the all-zero SHA of a newly created branch), every package
# is printed as well.

set -e -o pipefail -u

include_build=false
if [ "${1:-}" = '--include-build' ]; then
    include_build=true
    shift
fi
base="$1"
head="$2"

all_packages() {
    find packages -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort
}

if ! git cat-file -e "$base^{commit}" 2>/dev/null; then
    all_packages
    exit 0
fi

# Three dots: compare against the merge base, so commits that landed on the base
# branch after a pull request was opened do not count as its changes.
changed="$(git diff --name-only "$base...$head")"

if [ "$include_build" = true ] && grep --quiet '^build/' <<< "$changed"; then
    all_packages
    exit 0
fi

# grep exits 1 when nothing below packages/ changed, which is no error here
{ grep '^packages/[^/]*/' <<< "$changed" || true; } \
    | cut --delimiter=/ --fields=2 \
    | sort --unique \
    | while read -r name; do
        if [ -d "packages/$name" ]; then
            echo "$name"
        fi
    done
