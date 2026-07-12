#!/usr/bin/env bash
#
# Author:  Linuxfabrik GmbH, Zurich, Switzerland
# Contact: info (at) linuxfabrik (dot) ch
#          https://www.linuxfabrik.ch/
# License: The Unlicense, see LICENSE file.
#
# Publish the built packages to the Linuxfabrik package repository, where they
# are served under repo.linuxfabrik.ch/<PKG_REPO_SUBDIR>/.
#
# Not implemented yet. This step uploads the built packages from PKG_DIR_PACKAGED
# to the repository and refreshes the per-format repository metadata:
#   - RPM (EL/Fedora):    createrepo_c + gpg-signed repodata
#   - DEB (Debian/Ubuntu): reprepro/aptly + signed Release
#   - pacman (Arch):       repo-add + pacman-key signature
#
# Required environment (planned):
#   PKG_NAME, PKG_VERSION, PKG_REPO_SUBDIR
#   PKG_DIR_PACKAGED   directory holding the built packages, grouped per distro

set -e -o pipefail -u

echo "publish.sh is not implemented yet." >&2
echo "Built packages are available under: ${PKG_DIR_PACKAGED:-<unset>}" >&2
exit 1
