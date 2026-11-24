#!/usr/bin/env bash
#
# Author:  Linuxfabrik GmbH, Zurich, Switzerland
# Contact: info (at) linuxfabrik (dot) ch
#          https://www.linuxfabrik.ch/
# License: The Unlicense, see LICENSE file.
#
# Build syft and its shell completions in the anchore/syft source tree in the
# current directory, with the same flags and build tags as upstream's
# .goreleaser.yaml. Shared by the RPM and the DEB recipe, which only install the
# results.
#
# $1: the version syft reports (`syft version`)
# $2: the source tarball from GitHub, for the commit syft reports
#
# Go comes from go.dev, not from the distribution: go.mod asked for Go 1.26.8
# while Debian 13 shipped 1.24 and EL 8 to 10 lag behind the patch releases
# (checked 2026-11-24). The script takes the newest patch release of the Go
# version go.mod names. anchore/syft commits no vendor/ directory, so the
# modules come from proxy.golang.org and are verified against go.sum and
# sum.golang.org.

set -e -o pipefail -u -x

version="$1"
tarball="$2"

# Upstream builds from a git checkout and embeds the full commit. A GitHub
# archive has no .git, but git archive records the commit in the pax header at
# the start of the tarball.
commit="$(gzip --decompress --stdout "$tarball" | head --bytes=1024 |
    grep --text --only-matching 'comment=[0-9a-f]\{40\}' || true)"
commit="${commit#comment=}"
if [ -z "$commit" ]; then
    echo "No commit found in the pax header of $tarball" >&2
    exit 1
fi

# Embed the time of the upstream commit, which git archive gives every file,
# instead of the build date, in the RFC 3339 form goreleaser uses.
build_date="$(date --utc --date="@$(stat --format=%Y go.mod)" '+%Y-%m-%dT%H:%M:%SZ')"

case "$(uname -m)" in
aarch64) go_arch='arm64' ;;
x86_64) go_arch='amd64' ;;
*)
    echo "Unsupported architecture: $(uname -m)" >&2
    exit 1
    ;;
esac

# `go 1.27` or `go 1.26.8` -> go1.27 or go1.26; the newest patch release of
# that series is at least as new as any patch version go.mod may name
go_series="go$(awk '$1 == "go" { split($2, v, "."); print v[1] "." v[2]; exit }' go.mod)"
# stable releases only: go1.27 and go1.27.3 match, go1.27rc1 does not
go_version="$(
    curl --fail --silent --show-error --location 'https://go.dev/dl/?mode=json&include=all' |
        grep --only-matching "\"version\": *\"${go_series//./\\.}\(\.[0-9]\+\)\?\"" |
        grep --only-matching 'go[0-9.]\+' |
        sort --version-sort |
        tail --lines=1
)"
if [ -z "$go_version" ]; then
    echo "No stable Go release found for $go_series" >&2
    exit 1
fi

echo "✅ Fetch $go_version for linux-$go_arch"
go_tarball="$go_version.linux-$go_arch.tar.gz"
curl --fail --silent --show-error --location \
    "https://dl.google.com/go/$go_tarball" \
    --output "$go_tarball"
echo "$(curl --fail --silent --show-error --location "https://dl.google.com/go/$go_tarball.sha256")  $go_tarball" |
    sha256sum --check
mkdir .go-toolchain
tar --extract --gzip --file "$go_tarball" --directory .go-toolchain
rm "$go_tarball"

export PATH="$PWD/.go-toolchain/go/bin:$PATH"
export CGO_ENABLED=0
export GOCACHE="$PWD/.go-cache"
# -modcacherw: the module cache is read-only by default, which makes the
# cleanup of the build directory by rpmbuild and debuild fail
export GOFLAGS='-modcacherw'
export GOMODCACHE="$PWD/.go-mod"
export GOPATH="$PWD/.go-path"
export GOTOOLCHAIN='local'

# Upstream asks toolbox-data.anchore.io for the latest syft release on every
# start and points to it. Updates come through the package manager, so the
# package turns the check off by default. Only the default changes, so an
# administrator can still turn it on with SYFT_CHECK_FOR_APP_UPDATE=true or
# `check-for-app-update: true` in the syft config. Verified against syft 1.57.2
# on Rocky 10: `syft scan -vv` logs "checking if a new version of syft is
# available" with upstream's RPM, not with the packaged one, and again with
# SYFT_CHECK_FOR_APP_UPDATE=true.
echo "✅ Turn off the version check against anchore.io by default"
update_check='cmd/syft/internal/options/update_check.go'
sed --in-place 's/^\t\tCheckForAppUpdate: true,$/\t\tCheckForAppUpdate: false,/' "$update_check"
if ! grep --quiet --line-regexp --fixed-strings "$(printf '\t\tCheckForAppUpdate: false,')" "$update_check"; then
    echo "Could not turn off the update check default in $update_check" >&2
    exit 1
fi

# The tags are upstream's: containers_image_openpgp verifies image signatures
# in Go instead of through the C library gpgme, which a static build cannot
# link, and exclude_graphdriver_btrfs drops the btrfs storage driver, which
# needs the btrfs headers. gitDescription is what `git describe --tags` gives
# upstream on a release tag (goreleaser's {{.Summary}}).
echo "✅ Build syft $version"
go build -trimpath \
    -tags 'containers_image_openpgp exclude_graphdriver_btrfs' \
    -ldflags "-s -w -X main.version=$version -X main.gitCommit=$commit -X main.buildDate=$build_date -X main.gitDescription=v$version" \
    -o bin/syft ./cmd/syft
HOME="$PWD/.home" bin/syft version

echo "✅ Generate shell completions"
for shell in bash fish zsh; do
    HOME="$PWD/.home" bin/syft completion "$shell" > "completion.$shell"
done

# syft links its Go modules statically, and their licenses (MIT, BSD and others)
# ask for their texts to travel with the binary. Collect them for every module
# linked into syft, per module path, e.g.
# module-licenses/github.com/spf13/cobra/LICENSE.txt.
echo "✅ Collect the licenses of the linked Go modules"
go list -deps -tags 'containers_image_openpgp exclude_graphdriver_btrfs' \
    -f '{{with .Module}}{{if not .Main}}{{.Path}} {{.Dir}}{{end}}{{end}}' ./cmd/syft |
    sort --unique |
    while read -r module dir; do
        # not license.go, as go-openapi/spec has one
        find "$dir" -maxdepth 1 -type f \
            \( -iname 'COPYING*' -o -iname 'LICENSE*' -o -iname 'NOTICE*' -o -iname 'PATENTS*' -o -iname 'UNLICENSE*' \) \
            ! -name '*.go' |
            while read -r file; do
                install -D -m 0644 "$file" "module-licenses/$module/$(basename "$file")"
            done
        if [ ! -d "module-licenses/$module" ]; then
            echo "No license file found for the Go module $module" >&2
            exit 1
        fi
    done
