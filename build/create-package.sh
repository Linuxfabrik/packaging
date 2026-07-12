#!/usr/bin/env bash
#
# Author:  Linuxfabrik GmbH, Zurich, Switzerland
# Contact: info (at) linuxfabrik (dot) ch
#          https://www.linuxfabrik.ch/
# License: The Unlicense, see LICENSE file.
#
# Build one product for one target distro. This is the product-agnostic entry
# point: it reads the per-product manifest (packages/<product>/package.conf),
# fetches the upstream source and dispatches to the RPM or DEB builder.
#
# Required environment:
#   PKG_NAME             product name, matching a directory under packages/
#   PKG_TARGET_DISTRO       e.g. rocky-v10, debian-v13, ubuntu-v2404
#   PKG_PACKAGE_ITERATION   build iteration of this version, starts at 1
#   PKG_ARCH                target architecture, e.g. x86_64 or aarch64
#   PKG_DIR_REPO            absolute path to this repository checkout
#   PKG_DIR_PACKAGED        absolute path where built packages are collected

set -e -o pipefail -u -x

export PKG_DIR_PACKAGE="$PKG_DIR_REPO/packages/$PKG_NAME"
export PKG_DIR_SOURCES
PKG_DIR_SOURCES="$(mktemp --directory)"

# Load the product manifest. It defines at least PKG_VERSION, PKG_SOURCE_URL,
# PKG_SOURCE_TARBALL and the per-format distro lists and recipe paths.
# shellcheck source=/dev/null
source "$PKG_DIR_PACKAGE/package.conf"
export PKG_NAME PKG_VERSION PKG_SOURCE_TARBALL

echo "✅ Fetch upstream source for $PKG_NAME $PKG_VERSION"
curl --fail --silent --show-error --location \
    "$PKG_SOURCE_URL" \
    --output "$PKG_DIR_SOURCES/$PKG_SOURCE_TARBALL"

echo "✅ Build $PKG_NAME for $PKG_TARGET_DISTRO"
case "$PKG_TARGET_DISTRO" in
rocky-* | rhel-* | almalinux-* | centos-* | fedora-* | sles-*)
    bash "$PKG_DIR_REPO/build/create-rpm.sh" "$PKG_DIR_PACKAGE/$PKG_RPM_SPEC"
    ;;
debian-* | ubuntu-*)
    bash "$PKG_DIR_REPO/build/create-deb.sh" "$PKG_DIR_PACKAGE/$PKG_DEB_DEBIAN_DIR"
    ;;
arch | arch-*)
    bash "$PKG_DIR_REPO/build/create-pacman.sh" "$PKG_DIR_PACKAGE/$PKG_PKGBUILD"
    ;;
*)
    echo "Unsupported target distro: $PKG_TARGET_DISTRO" >&2
    exit 1
    ;;
esac
