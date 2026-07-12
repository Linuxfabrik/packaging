#!/usr/bin/env bash
#
# Author:  Linuxfabrik GmbH, Zurich, Switzerland
# Contact: info (at) linuxfabrik (dot) ch
#          https://www.linuxfabrik.ch/
# License: The Unlicense, see LICENSE file.
#
# Build a binary .deb from a product's debian/ recipe. Product-agnostic: the
# debian/ directory is passed as $1, version and source tarball come from the
# environment set by create-package.sh.
#
# Required environment:
#   PKG_NAME, PKG_VERSION, PKG_PACKAGE_ITERATION
#   PKG_DIR_PACKAGE   product directory (for product files such as the unit file)
#   PKG_DIR_SOURCES   directory holding the fetched source tarball
#   PKG_DIR_PACKAGED  directory to copy the resulting .deb(s) into

set -e -o pipefail -u -x

DEBIAN_DIR="$1"

echo "✅ Prepare debian source tree"
# debuild expects the upstream tarball as <source>_<version>.orig.tar.gz.
orig="$PKG_DIR_SOURCES/${PKG_NAME}_${PKG_VERSION}.orig.tar.gz"
mv "$PKG_DIR_SOURCES/$PKG_SOURCE_TARBALL" "$orig"

src="$PKG_DIR_SOURCES/$PKG_NAME-$PKG_VERSION"
mkdir "$src"
tar --extract --ungzip --file "$orig" --directory "$src" --strip 1

cp --archive "$DEBIAN_DIR" "$src/debian"

# Single-source the systemd unit: the product keeps it under files/, dh_installsystemd
# picks it up once it sits in debian/<package>.service.
if [ -d "$PKG_DIR_PACKAGE/files" ]; then
    cp "$PKG_DIR_PACKAGE/files/"* "$src/debian/"
fi

# Inject version and metadata debuild reads from the changelog.
cat <<EOF > "$src/debian/changelog"
$PKG_NAME ($PKG_VERSION-$PKG_PACKAGE_ITERATION) unstable; urgency=medium

  * v$PKG_VERSION release.

 -- Linuxfabrik GmbH <info@linuxfabrik.ch>  $(date --rfc-email)
EOF

echo "✅ Create deb"
pushd "$src"
debuild --build=binary --no-sign
popd

cp --archive "$PKG_DIR_SOURCES"/*.deb "$PKG_DIR_PACKAGED"
