#!/usr/bin/env bash
#
# Author:  Linuxfabrik GmbH, Zurich, Switzerland
# Contact: info (at) linuxfabrik (dot) ch
#          https://www.linuxfabrik.ch/
# License: The Unlicense, see LICENSE file.
#
# Build a pacman package from a product's PKGBUILD. Product-agnostic: the PKGBUILD
# path is passed as $1, version and source tarball come from the environment set
# by create-package.sh.
#
# Required environment:
#   PKG_NAME, PKG_VERSION, PKG_PACKAGE_ITERATION, PKG_SOURCE_TARBALL
#   PKG_DIR_PACKAGE   product directory (for shared files such as the unit file)
#   PKG_DIR_SOURCES   directory holding the fetched source tarball
#   PKG_DIR_PACKAGED  directory to copy the resulting package(s) into

set -e -o pipefail -u -x

PKGBUILD="$1"

echo "✅ Prepare makepkg build tree"
build="$(mktemp --directory)"
cp "$PKGBUILD" "$build/PKGBUILD"

# Hand makepkg the already-fetched tarball as a local source, under the name the
# PKGBUILD references ($pkgname-$pkgver.tar.gz), so it does not download again.
cp "$PKG_DIR_SOURCES/$PKG_SOURCE_TARBALL" "$build/$PKG_NAME-$PKG_VERSION.tar.gz"

# Shared assets (e.g. the systemd unit) that the PKGBUILD lists as local sources.
if [ -d "$PKG_DIR_PACKAGE/files" ]; then
    cp "$PKG_DIR_PACKAGE/files/"* "$build/"
fi

# Single-source the version: inject pkgver/pkgrel so it lives only in package.conf.
sed --in-place \
    --expression="s/^pkgver=.*/pkgver=$PKG_VERSION/" \
    --expression="s/^pkgrel=.*/pkgrel=$PKG_PACKAGE_ITERATION/" \
    "$build/PKGBUILD"

echo "✅ Create pacman package"
# makepkg refuses to run as root; build as the unprivileged user from the image.
# --syncdeps installs the declared build/runtime dependencies via sudo pacman.
chown --recursive builder:builder "$build"
sudo --user=builder --set-home \
    bash -c "cd '$build' && makepkg --syncdeps --force --noconfirm"

cp --archive "$build"/*.pkg.tar.* "$PKG_DIR_PACKAGED"
