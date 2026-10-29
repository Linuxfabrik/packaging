#!/usr/bin/env bash
#
# Author:  Linuxfabrik GmbH, Zurich, Switzerland
# Contact: info (at) linuxfabrik (dot) ch
#          https://www.linuxfabrik.ch/
# License: The Unlicense, see LICENSE file.
#
# Detect whether a package is behind its upstream. Reads PKG_VERSION and the
# upstream coordinates from the package's package.conf, determines the latest
# upstream version and compares the two.
#
# Usage: check-upstream.sh [--write] <package-dir>
#
# Prints "<current> <latest>" and exits:
#   0  upstream is newer (a bump is due)
#   1  already up to date, or the package has no upstream to watch
#   2  error (e.g. the upstream could not be queried, or its latest tag does not
#      look like a version)
#
# With --write it also rewrites PKG_VERSION in package.conf to the latest version.
#
# Upstream coordinates in package.conf:
#   PKG_UPSTREAM_TYPE        github | gitlab | none
#   PKG_UPSTREAM_PROJECT     e.g. nicolargo/glances, or group/subgroup/project
#   PKG_UPSTREAM_SOURCE      releases (default) | tags
#   PKG_UPSTREAM_TAG_PREFIX  stripped from the tag to get the version, default v
#   PKG_UPSTREAM_MAJOR_MIN_PATCH  tags only: a version of a newer major release
#                            than PKG_VERSION counts from this patch level on,
#                            e.g. 1 waits for x.y.1 (default: no limit)
#   PKG_UPSTREAM_URL         GitLab instance, default https://gitlab.com
#
# `releases` takes the release the upstream marks as latest; drafts and
# prereleases never count. `tags` takes the highest version among all tags that
# start with the prefix, skipping alpha, beta, dev, pre and rc tags. Use it for
# projects that tag without publishing releases.
#
# PKG_UPSTREAM_MAJOR_MIN_PATCH holds back a new major release until its first
# bugfix release, the way Nextcloud's own stable channel does, while bugfix
# releases of the packaged major still come through.
#
# Honors GITHUB_TOKEN and GITLAB_TOKEN to avoid API rate limits and to read
# private GitLab projects (releases only; tags are read with `git ls-remote`).

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

PKG_UPSTREAM_SOURCE="${PKG_UPSTREAM_SOURCE:-releases}"
PKG_UPSTREAM_TAG_PREFIX="${PKG_UPSTREAM_TAG_PREFIX-v}"
PKG_UPSTREAM_URL="${PKG_UPSTREAM_URL:-https://gitlab.com}"

die() {
    echo "$dir: $*" >&2
    exit 2
}

# Print the tag of the release the upstream marks as latest.
latest_release_tag() {
    local api auth=() json
    case "$PKG_UPSTREAM_TYPE" in
    github)
        api="https://api.github.com/repos/$PKG_UPSTREAM_PROJECT/releases/latest"
        if [ -n "${GITHUB_TOKEN:-}" ]; then
            auth=(--header "Authorization: Bearer $GITHUB_TOKEN")
        fi
        ;;
    gitlab)
        # The project path goes into the URL encoded, slashes included.
        api="$PKG_UPSTREAM_URL/api/v4/projects/${PKG_UPSTREAM_PROJECT//\//%2F}/releases/permalink/latest"
        if [ -n "${GITLAB_TOKEN:-}" ]; then
            auth=(--header "PRIVATE-TOKEN: $GITLAB_TOKEN")
        fi
        ;;
    esac
    json="$(curl --fail --silent --show-error --location "${auth[@]}" "$api")" \
        || die "could not query $api (does the project publish releases? if it only tags, set PKG_UPSTREAM_SOURCE='tags')"
    jq --exit-status --raw-output '.tag_name' <<< "$json" \
        || die "no tag_name in the answer of $api"
}

# Print the highest version among all tags carrying the prefix.
latest_tag_version() {
    local repo_url
    case "$PKG_UPSTREAM_TYPE" in
    github) repo_url="https://github.com/$PKG_UPSTREAM_PROJECT.git" ;;
    gitlab) repo_url="$PKG_UPSTREAM_URL/$PKG_UPSTREAM_PROJECT.git" ;;
    esac
    local refs ref tag
    # Anonymous on purpose: a private or mistyped project fails right away
    # instead of prompting, and no credential helper or askpass program is asked
    # for stored credentials.
    refs="$(GIT_ASKPASS='' GIT_TERMINAL_PROMPT=0 SSH_ASKPASS='' \
        git -c core.askPass='' -c credential.helper='' \
        ls-remote --refs --tags "$repo_url")" \
        || die "could not list the tags of $repo_url"
    # The prefix is compared literally, not as a regex (duplicity uses "rel.").
    while read -r _ ref; do
        tag="${ref#refs/tags/}"
        if [[ "$tag" == "$PKG_UPSTREAM_TAG_PREFIX"* ]]; then
            echo "${tag#"$PKG_UPSTREAM_TAG_PREFIX"}"
        fi
    done <<< "$refs" \
        | { grep --extended-regexp '^[0-9]+(\.[0-9]+)*([-+._][0-9A-Za-z.]+)?$' || true; } \
        | { grep --extended-regexp --ignore-case --invert-match '(alpha|beta|dev|pre|rc)' || true; } \
        | awk -F. -v major="${PKG_VERSION%%.*}" -v min_patch="${PKG_UPSTREAM_MAJOR_MIN_PATCH:-0}" \
            '$1 + 0 <= major + 0 || $3 + 0 >= min_patch + 0' \
        | sort --version-sort \
        | tail -1
}

case "${PKG_UPSTREAM_TYPE:-}" in
github | gitlab) ;;
none)
    echo "$dir: no upstream to watch (PKG_UPSTREAM_TYPE='none')" >&2
    exit 1
    ;;
*) die "PKG_UPSTREAM_TYPE must be github, gitlab or none, not '${PKG_UPSTREAM_TYPE:-}'" ;;
esac

if [ -n "${PKG_UPSTREAM_MAJOR_MIN_PATCH:-}" ] && [ "$PKG_UPSTREAM_SOURCE" != 'tags' ]; then
    die "PKG_UPSTREAM_MAJOR_MIN_PATCH needs PKG_UPSTREAM_SOURCE='tags', the latest release alone shows no bugfix releases of the packaged major"
fi

case "$PKG_UPSTREAM_SOURCE" in
releases)
    tag="$(latest_release_tag)"
    if [[ "$tag" != "$PKG_UPSTREAM_TAG_PREFIX"* ]]; then
        die "latest release tag '$tag' does not start with PKG_UPSTREAM_TAG_PREFIX='$PKG_UPSTREAM_TAG_PREFIX'"
    fi
    latest="${tag#"$PKG_UPSTREAM_TAG_PREFIX"}"
    ;;
tags)
    latest="$(latest_tag_version)"
    ;;
*) die "PKG_UPSTREAM_SOURCE must be releases or tags, not '$PKG_UPSTREAM_SOURCE'" ;;
esac

if [ -z "$latest" ]; then
    die "found no upstream version"
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
