#!/usr/bin/env bash
#
# Author:  Linuxfabrik GmbH, Zurich, Switzerland
# Contact: info (at) linuxfabrik (dot) ch
#          https://www.linuxfabrik.ch/
# License: The Unlicense, see LICENSE file.
#
# Print the packages that have no release of their current state on <head>, one
# name per line, sorted: no release tag <name>-<version>-<iteration> has the same
# packages/<name>/ as <head>. Unlike the diff of a single push, this also catches
# up the packages of a release run that failed or that GitHub cancelled (it keeps
# one pending run per concurrency group and cancels the one waiting before).
#
# Usage: unreleased-packages.sh <head>
#
# Needs the release tags in the clone (actions/checkout with fetch-depth: 0).

set -e -o pipefail -u

head="$1"

find packages -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort | while read -r name; do
    released=false
    # the version starts with a digit: no match for sources-<name> or <name>-foo
    for tag in $(git tag --list "$name-[0-9]*" | grep --extended-regexp "^$name-[0-9][^/]*-[0-9]+$" || true); do
        if git diff --quiet "$tag" "$head" -- "packages/$name/"; then
            released=true
            break
        fi
    done
    if [ "$released" = false ]; then
        echo "$name"
    fi
done
