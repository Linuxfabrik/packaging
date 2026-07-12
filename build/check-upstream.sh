#!/usr/bin/env bash
#
# Author:  Linuxfabrik GmbH, Zurich, Switzerland
# Contact: info (at) linuxfabrik (dot) ch
#          https://www.linuxfabrik.ch/
# License: The Unlicense, see LICENSE file.
#
# Detect whether a package is behind its upstream. Reads PKG_VERSION and the
# upstream coordinates from the package's package.conf, queries the latest
# upstream GitHub release and compares the two versions.
#
# Usage: check-upstream.sh <package-dir>
#
# Prints "<current> <latest>" and exits:
#   0  upstream is newer (a bump is due)
#   1  already up to date
#   2  error (e.g. could not determine the latest upstream version)
#
# With --write it also rewrites PKG_VERSION in package.conf to the latest version.
# Honors GITHUB_TOKEN (sent as a bearer token) to avoid API rate limits.

set -e -o pipefail -u

write=false
if [ "${1:-}" = '--write' ]; then
    write=true
    shift
fi

dir="$1"
conf="$dir/package.conf"

# shellcheck source=/dev/null
source "$conf"

auth=()
if [ -n "${GITHUB_TOKEN:-}" ]; then
    auth=(--header "Authorization: Bearer $GITHUB_TOKEN")
fi

api="https://api.github.com/repos/$PKG_GITHUB_USER/$PKG_GITHUB_REPO/releases/latest"
latest="$(curl --fail --silent --show-error --location "${auth[@]}" "$api" \
    | sed --quiet 's/.*"tag_name": *"\([^"]*\)".*/\1/p' \
    | sed 's/^v//')"

if [ -z "$latest" ]; then
    echo "Could not determine latest upstream version for $PKG_GITHUB_USER/$PKG_GITHUB_REPO" >&2
    exit 2
fi

echo "$PKG_VERSION $latest"

if [ "$PKG_VERSION" = "$latest" ]; then
    exit 1
fi

# Newer only if $latest sorts strictly after the current version.
newest="$(printf '%s\n%s\n' "$PKG_VERSION" "$latest" | sort --version-sort | tail -1)"
if [ "$newest" != "$latest" ]; then
    exit 1
fi

if [ "$write" = true ]; then
    sed --in-place "s/^PKG_VERSION=.*/PKG_VERSION='$latest'/" "$conf"
fi

exit 0
