#!/usr/bin/env bash
#
# Author:  Linuxfabrik GmbH, Zurich, Switzerland
# Contact: info (at) linuxfabrik (dot) ch
#          https://www.linuxfabrik.ch/
# License: The Unlicense, see LICENSE file.
#
# Compare the target distros (build/containerfiles/) with the release data of
# endoflife.date and report what needs a change, following the rule in
# CONTRIBUTING.md (a release stays a target until six months after its vendor
# date):
#
# - add:  a release of RHEL, Fedora, SLES, Debian or Ubuntu LTS that is out and
#         newer than every target of its distribution
# - drop: a target whose drop date (vendor date + 6 months) has passed
# - date: a target whose drop date in CONTRIBUTING.md is missing or differs
#         from the one computed here, e.g. because a vendor extended its
#         support or a SLES service pack moved the date
#
# The vendor date is endoflife.date's `eolFrom`, which is Maintenance Support
# for RHEL, LTS for Debian, Standard Support for Ubuntu, General Support for SLE
# and the end of life for Fedora. For SLES it is the latest `eolFrom` of all
# service packs of the major release. Checked against the dates in
# CONTRIBUTING.md on 2026-11-24.
#
# Usage: check-distros.sh <output-dir>
#
# Writes one <output-dir>/<action>-<distro>.md per finding: its first line is
# the issue title, the rest the issue body. No finding, no file.
#
# Needs: curl, jq.

set -e -o pipefail -u

out="$1"
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
api='https://endoflife.date/api/v1/products'
today="$(date --utc '+%Y-%m-%d')"

mkdir --parents "$out"

# last day of the month of $1 (YYYY-MM-DD)
last_day() {
    date --utc --date="${1:0:7}-01 +1 month -1 day" '+%d'
}

# $1 plus six months. The end of a month gives the end of the month (2028-06-30
# gives 2028-12-31, 2029-05-31 gives 2029-11-30, not 2029-12-01 as
# `date --date='+6 months'` would), as in the list of dates in CONTRIBUTING.md.
plus_six_months() {
    local year month day target_last
    IFS=- read -r year month day <<< "$1"
    year=$((10#$year))
    month=$((10#$month + 6))
    if [ "$month" -gt 12 ]; then
        month=$((month - 12))
        year=$((year + 1))
    fi
    target_last="$(last_day "$(printf '%04d-%02d-01' "$year" "$month")")"
    if [ "$day" = "$(last_day "$1")" ] || [ "$((10#$day))" -gt "$((10#$target_last))" ]; then
        day="$target_last"
    fi
    printf '%04d-%02d-%02d' "$year" "$month" "$((10#$day))"
}

# distro prefix -> endoflife.date product, and the name CONTRIBUTING.md uses
declare -A product=([debian]='debian' [fedora]='fedora' [rocky]='rhel' [sles]='sles' [ubuntu]='ubuntu')
declare -A label=([debian]='Debian' [fedora]='Fedora' [rocky]='RHEL' [sles]='SLE' [ubuntu]='Ubuntu')

# releases of one product as `<version> <release date> <vendor date>`, one per
# line, newest first; only Ubuntu LTS, SLES per major release
releases() {
    curl --fail --silent --show-error --location "$api/$1" |
        jq --raw-output --arg product "$1" '
            .result.releases
            | if $product == "ubuntu" then map(select(.isLts)) else . end
            | if $product == "sles" then
                group_by(.name | split(".")[0])
                | map({
                    name: (.[0].name | split(".")[0]),
                    releaseDate: (map(.releaseDate) | min),
                    eolFrom: (map(.eolFrom // "") | max)
                  })
              else . end
            | sort_by(.releaseDate) | reverse
            | .[] | "\(.name) \(.releaseDate) \(.eolFrom // "")"'
}

# `rocky-v10` -> `10`, `ubuntu-v2404` -> `24.04`
version_of() {
    local version="${1#*-v}"
    case "$1" in
    ubuntu-*) echo "${version:0:2}.${version:2}" ;;
    *) echo "$version" ;;
    esac
}

# `10` -> `rocky-v10`, `24.04` -> `ubuntu-v2404`
distro_of() {
    echo "$1-v${2//./}"
}

# the drop dates in CONTRIBUTING.md, as `<name>=<date>`, e.g. `RHEL 8=2029-11-30`
declare -A documented=()
while read -r date name; do
    documented["$name"]="$date"
done < <(sed --quiet 's/^- \([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}\): \(.*\)$/\1 \2/p' "$repo_root/CONTRIBUTING.md")

for prefix in debian fedora rocky sles ubuntu; do
    targets="$(find "$repo_root/build/containerfiles" -maxdepth 1 -name "$prefix-v*" -printf '%f\n' | sort --version-sort)"
    if [ -z "$targets" ]; then
        continue
    fi
    data="$(releases "${product[$prefix]}")"
    if [ -z "$data" ]; then
        echo "No releases of ${product[$prefix]} at endoflife.date" >&2
        exit 1
    fi
    newest_target="$(version_of "$(tail --lines=1 <<< "$targets")")"

    # add: released, and newer than the newest target
    while read -r version released vendor_date; do
        distro="$(distro_of "$prefix" "$version")"
        if [[ "$released" > "$today" ]] ||
            [ "$(printf '%s\n%s\n' "$version" "$newest_target" | sort --version-sort | tail --lines=1)" = "$newest_target" ]; then
            continue
        fi
        name="${label[$prefix]} $version"
        drop_date="$(plus_six_months "$vendor_date")"
        {
            echo "Distro release: add $distro"
            echo
            echo "$name was released on $released and is not a target yet. Its drop date would be $drop_date (vendor date $vendor_date plus six months, [endoflife.date](https://endoflife.date/${product[$prefix]}))."
            echo
            echo 'To add it:'
            echo
            echo "- [ ] \`build/containerfiles/$distro\`, based on the one of the previous release"
            echo "- [ ] \`$distro\` in the \`PKG_*_DISTROS\` of every package that targets the previous release, and build them"
            echo "- [ ] CONTRIBUTING.md: the list of targets and \`- $drop_date: $name\` in the list of dates"
            echo '- [ ] README.md (setup command), if it names the release'
            echo "- [ ] the list of supported distros in \`.github/workflows/lf-build-linux.yml\`"
            echo '- [ ] CHANGELOG.md'
        } > "$out/add-$distro.md"
    done <<< "$data"

    for distro in $targets; do
        version="$(version_of "$distro")"
        name="${label[$prefix]} $version"
        vendor_date="$(awk -v version="$version" '$1 == version { print $3 }' <<< "$data")"
        if [ -z "$vendor_date" ]; then
            echo "No vendor date for $name at endoflife.date" >&2
            exit 1
        fi
        drop_date="$(plus_six_months "$vendor_date")"

        # drop: the drop date has passed
        if [[ ! "$today" < "$drop_date" ]]; then
            {
                echo "Distro release: drop $distro"
                echo
                echo "The drop date of $name was $drop_date (vendor date $vendor_date plus six months, [endoflife.date](https://endoflife.date/${product[$prefix]}))."
                echo
                echo 'To drop it:'
                echo
                echo "- [ ] \`$distro\` out of every \`package.conf\`"
                echo "- [ ] \`build/containerfiles/$distro\` and any workaround for it, e.g. in \`build/smoke-test-package.sh\`"
                echo "- [ ] CONTRIBUTING.md: the list of targets and the date of $name"
                echo '- [ ] README.md (setup command), if it names the release'
                echo "- [ ] the list of supported distros in \`.github/workflows/lf-build-linux.yml\`"
                echo '- [ ] CHANGELOG.md'
            } > "$out/drop-$distro.md"
            continue
        fi

        # date: CONTRIBUTING.md disagrees
        if [ "${documented[$name]:-}" != "$drop_date" ]; then
            {
                echo "Distro release: drop date of $distro"
                echo
                echo "CONTRIBUTING.md gives ${documented[$name]:-no drop date} for $name, endoflife.date gives the vendor date $vendor_date, so the drop date is $drop_date ([endoflife.date](https://endoflife.date/${product[$prefix]}))."
                echo
                echo "- [ ] \`- $drop_date: $name\` in the list of dates in CONTRIBUTING.md, kept in date order"
            } > "$out/date-$distro.md"
        fi
    done
done
