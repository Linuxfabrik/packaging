#!/usr/bin/env bash
#
# Author:  Linuxfabrik GmbH, Zurich, Switzerland
# Contact: info (at) linuxfabrik (dot) ch
#          https://www.linuxfabrik.ch/
# License: The Unlicense, see LICENSE file.
#
# Build exo, its man pages and its shell completions in the exoscale/cli source
# tree in the current directory, with the same flags as upstream's
# .goreleaser.yml. Shared by the RPM and the DEB recipe, which only install the
# results.
#
# $1: the version exo reports (`exo version`)
# $2: the source tarball from GitHub, for the commit exo reports
#
# Go comes from go.dev, not from the distribution: exoscale/cli raises its
# minimum Go version (the `go` line in go.mod) shortly after every Go release,
# and no target distro keeps up (go.mod asked for Go 1.27 while EL 8 to 10 and
# Fedora 44 shipped 1.26 and Debian 13 1.24, checked 2026-10-26). The script
# takes the newest patch release of the Go version go.mod names. The modules
# come from the vendor/ directory upstream commits, so the build itself needs
# no network.

set -e -o pipefail -u -x

version="$1"
tarball="$2"

# Upstream builds from a git checkout and embeds the short commit (8 digits,
# as in `exo 1.103.2 63db060a`). A GitHub archive has no .git, but git archive
# records the commit in the pax header at the start of the tarball.
commit="$(gzip --decompress --stdout "$tarball" | head --bytes=1024 |
    grep --text --only-matching 'comment=[0-9a-f]\{40\}' || true)"
commit="${commit#comment=}"
if [ -z "$commit" ]; then
    echo "No commit found in the pax header of $tarball" >&2
    exit 1
fi
commit="${commit:0:8}"

# cobra writes the date into the man pages. Take the time of the upstream
# commit, which git archive gives every file, instead of the build date that
# rpmbuild and dpkg export, so the man pages match upstream's byte for byte.
SOURCE_DATE_EPOCH="$(stat --format=%Y go.mod)"
export SOURCE_DATE_EPOCH

case "$(uname -m)" in
aarch64) go_arch='arm64' ;;
x86_64) go_arch='amd64' ;;
*)
    echo "Unsupported architecture: $(uname -m)" >&2
    exit 1
    ;;
esac

# `go 1.27` or `go 1.26.9` -> go1.27 or go1.26; the newest patch release of that
# series is at least as new as any patch version go.mod may name
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
export GOFLAGS='-mod=vendor'
export GOPATH="$PWD/.go-path"
# vendor/ only, and never switch to another toolchain
export GOPROXY='off'
export GOTOOLCHAIN='local'

echo "✅ Build exo $version"
go build -trimpath -ldflags "-s -w -X main.version=$version -X main.commit=$commit" -o exo .
./exo version

# the steps of upstream's `make manpages completions`, without the Makefile,
# which clones exoscale/go.mk from GitHub first
echo "✅ Generate man pages and shell completions"
mkdir manpage
go run docs/main.go --man-page
for shell in bash fish zsh; do
    go run completion/main.go "$shell"
done

# exo links the vendored modules statically, and their licenses (MIT, BSD and
# others) ask for their texts to travel with the binary. Collect them per module
# path, e.g. vendor-licenses/github.com/spf13/cobra/LICENSE.txt.
echo "✅ Collect the licenses of the vendored modules"
find vendor -type f \( -iname 'COPYING*' -o -iname 'LICENSE*' -o -iname 'NOTICE*' -o -iname 'PATENTS*' \) |
    while read -r file; do
        install -D -m 0644 "$file" "vendor-licenses/${file#vendor/}"
    done
