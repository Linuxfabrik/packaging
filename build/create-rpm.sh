#!/usr/bin/env bash
#
# Author:  Linuxfabrik GmbH, Zurich, Switzerland
# Contact: info (at) linuxfabrik (dot) ch
#          https://www.linuxfabrik.ch/
# License: The Unlicense, see LICENSE file.
#
# Build a binary RPM from a product spec. Product-agnostic: the spec path is
# passed as $1, the source tarball and version come from the environment set by
# create-package.sh.
#
# Required environment:
#   PKG_VERSION, PKG_PACKAGE_ITERATION, PKG_ARCH, PKG_TARGET_DISTRO
#   PKG_DIR_SOURCES   directory holding the fetched source tarball
#   PKG_DIR_PACKAGED  directory to copy the resulting RPM(s) into

set -e -o pipefail -u -x

SPEC="$1"

# Install BuildRequires for a spec or an (n)src rpm using whatever package manager
# the target distro provides: `dnf builddep` on EL/Fedora, a zypper fallback on
# SLES (which ships no dnf). The zypper path resolves the BuildRequires with
# rpmspec/rpm and installs them directly.
builddep() {
    if command -v dnf >/dev/null 2>&1; then
        dnf --assumeyes builddep "$@"
    else
        local reqs
        reqs="$(rpmspec --query --buildrequires "$@" 2>/dev/null \
            || rpm --query --requires --package "$@" 2>/dev/null)"
        if [ -n "$reqs" ]; then
            # shellcheck disable=SC2086
            zypper --non-interactive install --no-recommends $reqs
        fi
    fi
}

echo "✅ Setup rpm build tree"
# SLES builds in /usr/src/packages by default; pin the tree to ~/rpmbuild on
# every distro, as the monitoring-plugins build does.
echo "%_topdir $HOME/rpmbuild" > "$HOME/.rpmmacros"
# SLES defines no %{dist}, so the SLES 15 and SLES 16 builds of a package would
# share one file name, which the flat list of GitHub release assets cannot hold.
# Give them a tag after the platform instead (sles-v16 -> .sle16), matching the
# repository path sle/16 that also serves SLED and openSUSE Leap.
if [ -z "$(rpm --eval '%{?dist}')" ]; then
    case "$PKG_TARGET_DISTRO" in
    sles-v*) echo "%dist .sle${PKG_TARGET_DISTRO#sles-v}" >> "$HOME/.rpmmacros" ;;
    *) echo "%dist .${PKG_TARGET_DISTRO/-v/}" >> "$HOME/.rpmmacros" ;;
    esac
fi
mkdir --parent "$HOME"/rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
cp "$PKG_DIR_SOURCES"/* "$HOME/rpmbuild/SOURCES/"
# Additional spec sources (e.g. the systemd unit referenced as Source1) live in
# the package's files/ directory.
if [ -d "$PKG_DIR_PACKAGE/files" ]; then
    cp "$PKG_DIR_PACKAGE/files/"* "$HOME/rpmbuild/SOURCES/"
fi
cp "$SPEC" "$HOME/rpmbuild/SPECS/"
SPEC="$HOME/rpmbuild/SPECS/$(basename "$SPEC")"
# Write the %changelog for the version being built, as create-deb.sh does with
# debian/changelog. A fixed entry in the spec would name an older version than
# the package (rpmlint: incoherent-version-in-changelog). The entry carries the
# dist tag, since rpmlint only strips the ones it knows, not .sle16.
sed --in-place '/^%changelog/,$d' "$SPEC"
cat <<EOF >> "$SPEC"
%changelog
* $(LC_ALL=C date '+%a %b %d %Y') Linuxfabrik GmbH <info@linuxfabrik.ch> - $PKG_VERSION-$PKG_PACKAGE_ITERATION$(rpm --eval '%{?dist}')
- v$PKG_VERSION release.
EOF

# Install the statically declared BuildRequires. This is per-package and needs
# no changes to the container images.
echo "✅ Install static build dependencies"
builddep "$SPEC"

# Resolve the dynamically generated %pyproject_buildrequires. Each `rpmbuild -br`
# pass writes a *.buildreqs.nosrc.rpm carrying the BuildRequires discovered so
# far; install them and repeat until the source RPM builds cleanly. Specs
# without dynamic build requires succeed on the first pass.
echo "✅ Resolve dynamic build dependencies"
set +e
for _ in 1 2 3 4 5; do
    rpmbuild -br \
        --define "pkg_version $PKG_VERSION" \
        --define "pkg_release $PKG_PACKAGE_ITERATION" \
        "$SPEC" && break
    nosrc=("$HOME"/rpmbuild/SRPMS/*.buildreqs.nosrc.rpm)
    [ -e "${nosrc[0]}" ] || break
    builddep "${nosrc[@]}"
done
set -e

echo "✅ Create rpm"
rpmbuild -bb \
    --define "pkg_version $PKG_VERSION" \
    --define "pkg_release $PKG_PACKAGE_ITERATION" \
    "$SPEC"

find "$HOME/rpmbuild/RPMS" -name '*.rpm' -exec cp --archive {} "$PKG_DIR_PACKAGED" \;
