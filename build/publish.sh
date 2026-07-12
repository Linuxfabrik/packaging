#!/usr/bin/env bash
#
# Author:  Linuxfabrik GmbH, Zurich, Switzerland
# Contact: info (at) linuxfabrik (dot) ch
#          https://www.linuxfabrik.ch/
# License: The Unlicense, see LICENSE file.
#
# Publish the built packages to the Linuxfabrik package repository, served under
# repo.linuxfabrik.ch.
#
# Not implemented yet, and intentionally deferred: publishing targets a Pulp server
# that is not deployed yet. publish.sh uploads the built packages into the aggregated
# Linuxfabrik Pulp repositories and triggers a publication; Pulp signs the metadata
# itself via its signing service (the Linuxfabrik GPG key), so nothing is signed here.
# Do NOT wire the legacy createrepo/freight publishing path -- it is being retired.
#
# Intended flow per distro family:
#   RPM (el/<ver>):       pulp rpm content upload --repository=<repo> --file=<rpm>
#                         pulp rpm publication create --repository=<repo>
#   DEB (debian, ubuntu): pulp deb content upload --repository=<repo> --file=<deb>
#                         pulp deb publication create --repository=<repo>
# Channels release/testing map to the target repository/distribution. Distributions
# are created with --repository, so the newest publication is served immediately.
# See CONTRIBUTING.md "Publishing to Pulp".
#
# Required environment (planned):
#   PKG_NAME, PKG_VERSION, PKG_REPO_SUBDIR
#   PKG_DIR_PACKAGED   directory holding the built packages, grouped per distro

set -e -o pipefail -u

echo "publish.sh is not implemented yet." >&2
echo "Built packages are available under: ${PKG_DIR_PACKAGED:-<unset>}" >&2
exit 1
