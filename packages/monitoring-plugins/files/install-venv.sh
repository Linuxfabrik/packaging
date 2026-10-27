#!/usr/bin/env bash
#
# Author:  Linuxfabrik GmbH, Zurich, Switzerland
# Contact: info (at) linuxfabrik (dot) ch
#          https://www.linuxfabrik.ch/
# License: The Unlicense, see LICENSE file.
#
# Create the dependency venv of the monitoring plugins at $2 with the
# interpreter $1, and install the hash-pinned dependencies from the lockfile of
# that interpreter (lockfiles/py3xx/requirements.txt in the monitoring-plugins
# source tree in the current directory). Used by the RPM spec and debian/rules.

set -e -o pipefail -u -x

python="$1"
venv="$2"

py_tag="py$("$python" -c 'import sys; print(f"{sys.version_info.major}{sys.version_info.minor}")')"
requirements="lockfiles/$py_tag/requirements.txt"
if [ ! -f "$requirements" ]; then
    echo "❌ No requirements file for Python $py_tag at $requirements" >&2
    exit 1
fi

"$python" -m venv "$venv"

# Download first, then install from the download only, so that pip never
# reaches for an index while it installs. setuptools and wheel are needed to
# build an sdist and are removed again afterwards.
wheels="$(mktemp --directory)"
"$venv/bin/pip" download --dest "$wheels" setuptools wheel
# --no-dependencies: every dependency is pinned with its hash in the lockfile
# anyway, and openstack's pbr declares an unpinned setuptools that would
# otherwise be fetched again.
"$venv/bin/pip" download \
    --dest "$wheels" \
    --no-dependencies \
    --require-hashes \
    --requirement "$requirements"

"$venv/bin/pip" install --no-index --find-links "$wheels" setuptools wheel
"$venv/bin/pip" install \
    --find-links "$wheels" \
    --no-dependencies \
    --no-index \
    --require-hashes \
    --requirement "$requirements"
"$venv/bin/pip" uninstall --yes setuptools wheel

rm --recursive --force "$wheels"
