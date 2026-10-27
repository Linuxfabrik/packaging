#!/usr/bin/env bash
#
# Author:  Linuxfabrik GmbH, Zurich, Switzerland
# Contact: info (at) linuxfabrik (dot) ch
#          https://www.linuxfabrik.ch/
# License: The Unlicense, see LICENSE file.
#
# Install the plugins, their assets and the snmp device data from the
# monitoring-plugins source tree in the current directory into the plugin
# directory given as $1. Used by the RPM spec and debian/rules. The layout
# follows the monitoring-plugins repository: a new kind of data next to the
# plugins has to be added here with the version bump that brings it.

set -e -o pipefail -u -x

target="$1"

# Discover and install plugins: <tree>/<name>/<name>
find check-plugins event-plugins notification-plugins \
    -maxdepth 2 \
    -type f \
    -not -name example \
    -regextype posix-extended \
    -regex '.*/([^/]+)/\1$' \
    -exec install {} "$target" \;

# Discover and install plugin assets, flat into <plugin-dir>/assets
install --directory "$target/assets"
find check-plugins event-plugins notification-plugins \
    -mindepth 3 \
    -type f \
    -path '*/assets/*' \
    -not -path '*/example/assets/*' \
    -exec install --mode 0644 {} "$target/assets" \;

# Install the data directories the snmp plugin reads next to itself (its OID
# lists and MIBs, see its README), keeping their structure
for dir in device-mibs device-oids; do
    find "check-plugins/snmp/$dir" -type f -printf '%P\n' | while read -r file; do
        install -D --mode 0644 "check-plugins/snmp/$dir/$file" "$target/$dir/$file"
    done
done
