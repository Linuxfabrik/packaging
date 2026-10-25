#!/usr/bin/env bash
#
# Author:  Linuxfabrik GmbH, Zurich, Switzerland
# Contact: info (at) linuxfabrik (dot) ch
#          https://www.linuxfabrik.ch/
# License: The Unlicense, see LICENSE file.
#
# For every target distro in PKG_TARGET_DISTROS, build the matching container
# image from build/containerfiles/<distro> and run create-package.sh inside it,
# then smoke-test the result in a fresh container of the same distro.
# Built packages land on the host under PKG_DIR_PACKAGED/<distro>.
#
# Required environment:
#   PKG_NAME, PKG_PACKAGE_ITERATION, PKG_ARCH
#   PKG_TARGET_DISTROS   space-separated list of distros to build for
#   PKG_DIR_REPO         absolute path to this repository checkout (host)
#   PKG_DIR_PACKAGED     absolute path to collect built packages (host)

set -e -o pipefail -u -x

# podman names the architectures the OCI way. Passing it explicitly builds and
# runs the image for PKG_ARCH: natively on a matching host (the GitHub runners),
# emulated through qemu-user elsewhere, e.g. aarch64 on an x86_64 workstation.
case "$PKG_ARCH" in
aarch64) oci_arch='arm64' ;;
x86_64) oci_arch='amd64' ;;
*)
    echo "Unsupported PKG_ARCH: $PKG_ARCH" >&2
    exit 1
    ;;
esac
export PKG_OCI_ARCH="$oci_arch"

for distro in $PKG_TARGET_DISTROS; do
    mkdir --parents "$PKG_DIR_PACKAGED/$distro"

    echo "✅ Build container image for $distro"
    podman build \
        --arch "$oci_arch" \
        --file "$PKG_DIR_REPO/build/containerfiles/$distro" \
        --tag "packaging-build-$distro-$PKG_ARCH"

    echo "✅ Build $PKG_NAME on $distro"
    podman run \
        --arch "$oci_arch" \
        --env=PKG_NAME="$PKG_NAME" \
        --env=PKG_ARCH="$PKG_ARCH" \
        --env=PKG_PACKAGE_ITERATION="$PKG_PACKAGE_ITERATION" \
        --env=PKG_TARGET_DISTRO="$distro" \
        --env=PKG_DIR_REPO=/repo \
        --env=PKG_DIR_PACKAGED=/packaged \
        --mount type=bind,source="$PKG_DIR_PACKAGED/$distro",destination=/packaged,relabel=private \
        --mount type=bind,source="$PKG_DIR_REPO",destination=/repo,relabel=shared,ro=true \
        --rm \
        "packaging-build-$distro-$PKG_ARCH" \
        /bin/bash /repo/build/create-package.sh

    bash "$PKG_DIR_REPO/build/smoke-test-package.sh" "$distro"
done
