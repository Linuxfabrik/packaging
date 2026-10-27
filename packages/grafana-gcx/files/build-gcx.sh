#!/usr/bin/env bash
#
# Author:  Linuxfabrik GmbH, Zurich, Switzerland
# Contact: info (at) linuxfabrik (dot) ch
#          https://www.linuxfabrik.ch/
# License: The Unlicense, see LICENSE file.
#
# Build gcx and its shell completions in the grafana/gcx source tree in the
# current directory, with the same flags as upstream's .goreleaser.yaml. Shared
# by the RPM and the DEB recipe, which only install the results.
#
# $1: the version gcx reports (`gcx --version`)
# $2: the source tarball from GitHub, for the commit gcx reports
#
# Go comes from go.dev, not from the distribution: go.mod asked for Go 1.26.10
# while Debian 13 shipped 1.24 and EL 8 to 10 lag behind the patch releases
# (checked 2026-10-27). The script takes the newest patch release of the Go
# version go.mod names. grafana/gcx commits no vendor/ directory, so the
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

# `go 1.27` or `go 1.26.10` -> go1.27 or go1.26; the newest patch release of
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

# Upstream sends anonymous usage telemetry to Grafana unless it is opted out of.
# The package turns it off by default instead. This changes only the last step
# of upstream's resolution (GCX_TELEMETRY, then DO_NOT_TRACK, then
# `diagnostics.telemetry` in the config file, then this default), so an
# administrator can still opt in through any of them, and the first-run notice,
# which gcx only shows while telemetry is on, stays away as well. Verified
# against gcx 1.7.1 on Rocky 10: in a pty, the packaged gcx shows no notice and
# writes no device-id, with GCX_TELEMETRY=enabled it does both.
echo "✅ Turn off telemetry by default"
sed --in-place 's/^const defaultMode = ModeEnabled$/const defaultMode = ModeDisabled/' \
    internal/telemetry/telemetry.go
if ! grep --quiet '^const defaultMode = ModeDisabled$' internal/telemetry/telemetry.go; then
    echo "Could not turn off the telemetry default in internal/telemetry/telemetry.go" >&2
    exit 1
fi

# Upstream asks GitHub for the latest gcx release in interactive runs and points
# to the release page. Updates come through the package manager, so drop that
# check. GCX_NO_UPDATE_NOTIFIER is no alternative: it also silences the notice
# that the installed Agent Skills are older than the ones gcx ships, which is
# what an administrator wants to see after a package update. Verified against
# gcx 1.7.1 on Rocky 10: upstream's binary records gcx_version_notice and
# skills_update_notice in ~/.local/state/gcx/notifier.yml, the packaged one only
# skills_update_notice.
echo "✅ Turn off the version check against GitHub"
version_check='func MaybeNotifyVersion(ctx context.Context, dst io.Writer, currentVersion string) error {'
if ! grep --quiet --line-regexp --fixed-strings "$version_check" internal/notifier/run.go; then
    echo "Could not find the version check in internal/notifier/run.go" >&2
    exit 1
fi
# return right at the start; the rest of the function stays as unreachable code
sed --in-place "/^func MaybeNotifyVersion(/a\\
	return nil // packaged: updates come through the package manager" \
    internal/notifier/run.go

echo "✅ Build gcx $version"
go build -trimpath \
    -ldflags "-s -w -X main.version=$version -X main.commit=$commit -X main.date=$build_date" \
    -o gcx ./cmd/gcx
HOME="$PWD/.home" ./gcx --version

echo "✅ Generate shell completions"
for shell in bash fish zsh; do
    HOME="$PWD/.home" ./gcx completion "$shell" > "completion.$shell"
done

# gcx links its Go modules statically, and their licenses (MIT, BSD and others)
# ask for their texts to travel with the binary. Collect them for every module
# linked into gcx, per module path, e.g.
# module-licenses/github.com/spf13/cobra/LICENSE.txt.
echo "✅ Collect the licenses of the linked Go modules"
go list -deps -f '{{with .Module}}{{if not .Main}}{{.Path}} {{.Dir}}{{end}}{{end}}' ./cmd/gcx |
    sort --unique |
    while read -r module dir; do
        # not license.go, as go-openapi/spec has one
        find "$dir" -maxdepth 1 -type f \
            \( -iname 'COPYING*' -o -iname 'LICENSE*' -o -iname 'NOTICE*' -o -iname 'PATENTS*' \) \
            ! -name '*.go' |
            while read -r file; do
                install -D -m 0644 "$file" "module-licenses/$module/$(basename "$file")"
            done
        if [ ! -d "module-licenses/$module" ]; then
            echo "No license file found for the Go module $module" >&2
            exit 1
        fi
    done
