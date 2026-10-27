#!/usr/bin/env bash
#
# Author:  Linuxfabrik GmbH, Zurich, Switzerland
# Contact: info (at) linuxfabrik (dot) ch
#          https://www.linuxfabrik.ch/
# License: The Unlicense, see LICENSE file.
#
# Smoke test of linuxfabrik-monitoring-plugins, run by build/smoke-test-package.sh
# as user nobody in a fresh container with the packages installed. Checks it the
# way a monitored host uses it: every .pyc in the venv loads and is used, and
# every plugin starts. monitoring-plugins#1543 shipped in every RPM since 2.0.0
# for want of this.

set -e -o pipefail -u

plugin_dir=/usr/lib64/nagios/plugins
venv=/usr/lib64/linuxfabrik-monitoring-plugins/venv

echo "✅ Check the bytecode in the venv"
"$venv/bin/python" /files/check-bytecode.py

echo "✅ Start every plugin"
# --version still imports every module the plugin needs, which is where a broken
# venv shows, and it needs neither a service nor privileges
failed=0
total=0
for plugin in "$plugin_dir"/*; do
    [ -f "$plugin" ] || continue
    total=$((total + 1))
    retc=0
    output="$("$plugin" --version 2>&1)" || retc=$?
    # argparse ends --version with 0, the plugins turn that into 3 (UNKNOWN)
    if { [ $retc -ne 0 ] && [ $retc -ne 3 ]; } || grep --quiet Traceback <<< "$output"; then
        echo "❌ $plugin --version, exit code $retc:"
        echo "$output"
        failed=$((failed + 1))
    fi
done
echo "$total plugins started, $failed failed"
[ $total -gt 0 ] && [ $failed -eq 0 ]
