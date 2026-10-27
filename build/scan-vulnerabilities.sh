#!/usr/bin/env bash
#
# Author:  Linuxfabrik GmbH, Zurich, Switzerland
# Contact: info (at) linuxfabrik (dot) ch
#          https://www.linuxfabrik.ch/
# License: The Unlicense, see LICENSE file.
#
# Scan the published packages for known vulnerabilities in what they bundle:
# Go modules and the Go standard library in static binaries, Python packages in
# a venv, JavaScript in a bundled web UI. Per package it takes the newest
# release in the `release` channel and, if newer, the newest one in `testing`.
# Dependencies a package takes from the distribution are not looked at, the
# distribution's own updates fix those.
#
# Only x86_64 (amd64) and noarch packages are scanned: the aarch64 builds come
# from the same sources and lockfiles. Only vulnerabilities with a fixed version
# count, since only those can be fixed by a rebuild or an upstream bump.
#
# Usage: scan-vulnerabilities.sh <output-dir>
#
# Writes <output-dir>/scanned (one release tag per line) and, for every release
# with findings, <output-dir>/<tag>.md, a Markdown table of them.
#
# Needs: cpio, dpkg-deb, gh (with GH_TOKEN), grype, jq, rpm2cpio.

set -e -o pipefail -u

out="$1"
repo="${GITHUB_REPOSITORY:-Linuxfabrik/packaging}"
repo_root="$(cd "$(dirname "$0")/.." && pwd)"

mkdir --parents "$out"
: > "$out/scanned"
work="$(mktemp --directory)"
trap 'rm --recursive --force "$work"' EXIT

# Fetch the vulnerability database once instead of on every scan.
grype db update

releases="$(gh release list \
    --exclude-drafts \
    --json 'isPrerelease,name,publishedAt,tagName' \
    --limit 1000 \
    --repo "$repo")"

for dir in "$repo_root"/packages/*/; do
    package="$(basename "$dir")"

    # Newest release, then the newest prerelease if it is newer. Rejected
    # prereleases are not served. `<package>-<digit>` keeps e.g. `glances-` from
    # matching a package named `glances-foo`.
    tags="$(jq --raw-output --arg package "$package" '
        [.[]
            | select(.tagName | startswith($package + "-"))
            | select(.tagName | ltrimstr($package + "-") | test("^[0-9]"))
            | select(.name | endswith("(rejected)") | not)]
        | sort_by(.publishedAt) | reverse
        | (map(select(.isPrerelease | not)) | first) as $release
        | (map(select(.isPrerelease)) | first) as $testing
        | [$release, (if $testing and ($release == null or $testing.publishedAt > $release.publishedAt) then $testing else null end)]
        | map(select(. != null) | .tagName) | .[]
    ' <<< "$releases")"

    for tag in $tags; do
        echo "✅ Scan $tag"
        echo "$tag" >> "$out/scanned"
        rm --recursive --force "$work/assets" "$work/root"
        mkdir "$work/assets" "$work/root"
        gh release download "$tag" \
            --dir "$work/assets" \
            --pattern '*.x86_64.rpm' \
            --pattern '*.noarch.rpm' \
            --pattern '*_amd64.deb' \
            --pattern '*_all.deb' \
            --repo "$repo"

        : > "$work/matches.jsonl"
        for asset in "$work/assets"/*; do
            name="$(basename "$asset")"
            # the target the package is built for: el9, sle16, debian13, ...
            case "$name" in
            *.rpm)
                target="${name%.*.rpm}"
                target="${target##*.}"
                ;;
            *+*.deb)
                target="${name##*+}"
                target="${target%%_*}"
                ;;
            *) target="$name" ;;
            esac

            root="$work/root/$name"
            mkdir "$root"
            case "$name" in
            *.rpm) (cd "$root" && rpm2cpio "$asset" | cpio --extract --make-directories --quiet) ;;
            *.deb) dpkg-deb --extract "$asset" "$root" ;;
            esac

            # The extracted tree has no package database, so grype only sees
            # what the package bundles.
            GRYPE_DB_AUTO_UPDATE=false grype "dir:$root" --only-fixed --output json --quiet |
                jq --compact-output --arg target "$target" '.matches[] | {
                    fix: (.vulnerability.fix.versions | join(", ")),
                    id: .vulnerability.id,
                    package: .artifact.name,
                    severity: .vulnerability.severity,
                    target: $target,
                    type: .artifact.type,
                    version: .artifact.version
                }' >> "$work/matches.jsonl"
            rm --recursive --force "$root"
        done

        if [ ! -s "$work/matches.jsonl" ]; then
            echo "No fixable vulnerabilities in $tag"
            continue
        fi

        # One row per vulnerability and package version, with the targets it
        # was found on.
        {
            echo '| Vulnerability | Severity | Package | Installed | Fixed in | Targets |'
            echo '| --- | --- | --- | --- | --- | --- |'
            jq --raw-output --slurp '
                group_by([.id, .package, .version])
                | map(.[0] + {targets: (map(.target) | unique | join(", "))})
                | sort_by(.id, .package)
                | .[]
                | "| \(.id) | \(.severity) | \(.package) (\(.type)) | \(.version) | \(.fix) | \(.targets) |"
            ' "$work/matches.jsonl"
        } > "$out/$tag.md"
        cat "$out/$tag.md"
    done
done
