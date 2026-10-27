#!/usr/bin/env bash
#
# Author:  Linuxfabrik GmbH, Zurich, Switzerland
# Contact: info (at) linuxfabrik (dot) ch
#          https://www.linuxfabrik.ch/
# License: The Unlicense, see LICENSE file.
#
# Install the packages just built for the target distro given as $1 into a fresh
# container of that distro and run the package's smoke test in it. The build
# container is no stand-in for a real host: it carries compilers and headers and
# never installs the package, so a missing runtime dependency only shows here.
#
# EL targets get EPEL and CRB first, because packages built against them may
# depend on both.
#
# Required environment:
#   PKG_NAME
#   PKG_OCI_ARCH       architecture in podman's naming (amd64, arm64), set by
#                      matrix-package.sh
#   PKG_DIR_REPO       absolute path to this repository checkout (host)
#   PKG_DIR_PACKAGED   absolute path holding the built packages per distro (host)
#
# The command in PKG_SMOKE_TEST (from package.conf) runs as the unprivileged user
# nobody. Without it, the smoke test only checks that the packages install. The
# package's files/ directory is mounted read-only at /files, for a smoke test
# that needs more than a one-liner.

set -e -o pipefail -u -x

distro="$1"

# shellcheck source=/dev/null
source "$PKG_DIR_REPO/packages/$PKG_NAME/package.conf"

container="packaging-smoke-test-$PKG_NAME-$distro"
# the plain distro image the build container starts from
image="$(awk '/^FROM / { print $2; exit }' "$PKG_DIR_REPO/build/containerfiles/$distro")"

files_mount=()
if [ -d "$PKG_DIR_REPO/packages/$PKG_NAME/files" ]; then
    files_mount=(--mount "type=bind,source=$PKG_DIR_REPO/packages/$PKG_NAME/files,destination=/files,relabel=shared,ro=true")
fi

echo "✅ Install the $distro packages into a fresh $image container"
podman run \
    --arch "$PKG_OCI_ARCH" \
    --detach \
    "${files_mount[@]}" \
    --mount "type=bind,source=$PKG_DIR_PACKAGED/$distro,destination=/packaged,relabel=private,ro=true" \
    --name "$container" \
    --replace \
    --rm \
    "$image" \
    sleep infinity
trap 'podman stop --time 0 "$container" >/dev/null' EXIT

case "$distro" in
debian-v11)
    # the same snapshot sources as in build/containerfiles/debian-v11
    podman exec --env=DEBIAN_FRONTEND=noninteractive "$container" /bin/bash -c \
        'sed --in-place \
             --expression="s|^deb http|# deb http|" \
             --expression="s|^# deb http://snapshot|deb http://snapshot|" \
             /etc/apt/sources.list &&
         echo "Acquire::Check-Valid-Until \"false\";" > /etc/apt/apt.conf.d/99snapshot &&
         apt-get update && apt-get install --no-install-recommends --yes /packaged/*.deb'
    ;;
debian-* | ubuntu-*)
    podman exec --env=DEBIAN_FRONTEND=noninteractive "$container" /bin/bash -c \
        'apt-get update && apt-get install --no-install-recommends --yes /packaged/*.deb'
    ;;
rocky-* | rhel-* | almalinux-* | centos-*)
    # same CDN instead of the mirrorlist as in build/containerfiles/rocky-v*
    podman exec "$container" /bin/bash -c \
        'sed --in-place --expression="s|^mirrorlist=|#mirrorlist=|" \
             --expression="s|^#baseurl=http://dl.rockylinux.org|baseurl=https://dl.rockylinux.org|" \
             /etc/yum.repos.d/[Rr]ocky*.repo 2>/dev/null || true
         dnf --assumeyes install dnf-plugins-core epel-release && crb enable &&
         dnf --assumeyes --setopt=install_weak_deps=False install /packaged/*.rpm'
    ;;
fedora-*)
    podman exec "$container" /bin/bash -c \
        'dnf --assumeyes --setopt=install_weak_deps=False install /packaged/*.rpm'
    ;;
sles-*)
    podman exec "$container" /bin/bash -c \
        'zypper --non-interactive --no-gpg-checks install --allow-unsigned-rpm --no-recommends /packaged/*.rpm'
    ;;
*)
    echo "Unsupported target distro: $distro" >&2
    exit 1
    ;;
esac

if [ -n "${PKG_SMOKE_TEST:-}" ]; then
    echo "✅ Run the smoke test: $PKG_SMOKE_TEST"
    # nobody exists on every distro and owns nothing the package installs
    podman exec --user=65534:65534 "$container" /bin/bash -c "$PKG_SMOKE_TEST"
fi
