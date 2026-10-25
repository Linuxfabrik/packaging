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
#   PKG_DIR_REPO       absolute path to this repository checkout (host)
#   PKG_DIR_PACKAGED   absolute path holding the built packages per distro (host)
#
# The command in PKG_SMOKE_TEST (from package.conf) runs as the unprivileged user
# nobody. Without it, the smoke test only checks that the packages install.

set -e -o pipefail -u -x

distro="$1"

# shellcheck source=/dev/null
source "$PKG_DIR_REPO/packages/$PKG_NAME/package.conf"

container="packaging-smoke-test-$PKG_NAME-$distro"
# the plain distro image the build container starts from
image="$(awk '/^FROM / { print $2; exit }' "$PKG_DIR_REPO/build/containerfiles/$distro")"

echo "✅ Install the $distro packages into a fresh $image container"
podman run \
    --detach \
    --mount "type=bind,source=$PKG_DIR_PACKAGED/$distro,destination=/packaged,relabel=private,ro=true" \
    --name "$container" \
    --replace \
    --rm \
    "$image" \
    sleep infinity
trap 'podman stop --time 0 "$container" >/dev/null' EXIT

case "$distro" in
debian-* | ubuntu-*)
    podman exec --env=DEBIAN_FRONTEND=noninteractive "$container" /bin/bash -c \
        'apt-get update && apt-get install --no-install-recommends --yes /packaged/*.deb'
    ;;
rocky-* | rhel-* | almalinux-* | centos-*)
    podman exec "$container" /bin/bash -c \
        'dnf --assumeyes install dnf-plugins-core epel-release && crb enable &&
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
