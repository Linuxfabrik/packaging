#!/usr/bin/env bash
#
# Author:  Linuxfabrik GmbH, Zurich, Switzerland
# Contact: info (at) linuxfabrik (dot) ch
#          https://www.linuxfabrik.ch/
# License: The Unlicense, see LICENSE file.
#
# Runs on the repository server behind repo.linuxfabrik.ch, from a systemd timer.
# Mirrors the state of the GitHub releases of Linuxfabrik/packaging into the
# Linuxfabrik package repositories:
#
#   GitHub prerelease               -> channel `testing`
#   GitHub release                  -> channel `release`
#   prerelease titled "(rejected)"  -> removed from `testing` again
#
# Pull, not push: CI attaches the packages unsigned, and only this script, on
# our own server, holds the signing key. Before anything is published, every
# asset is checked against its build provenance attestation, so only files
# built by the release workflow of this repository are accepted.
#
# Repository layout below PUBLISH_WEBROOT (see GitLab 001/project-big-picture
# #1252):
#
#   RPM: <el|fedora|sle>/<os-version>/<arch>/linuxfabrik/<channel>/
#        (packages signed with rpmsign, repodata/repomd.xml signed detached)
#   DEB: <debian|ubuntu>/linuxfabrik/ with dists/<codename>-<channel>/main
#        (freight, Release files signed)
#
# Required environment:
#   GH_TOKEN                     read-only GitHub token, for the API and for
#                                `gh attestation verify`
#   PUBLISH_GPG_KEY              fingerprint of the signing key in the GnuPG
#                                keyring of the user running this script
#   PUBLISH_GPG_PASSPHRASE_FILE  file holding the passphrase of that key
#
# Optional environment (defaults in brackets):
#   PUBLISH_BASE_URL         [https://repo.linuxfabrik.ch] public URL of the
#                            webroot, for the commands on the start page
#   PUBLISH_BOOTSTRAP_PACKAGES  [linuxfabrik-release] packages that get a
#                            stable <name>-latest-<distro> link in the webroot
#   PUBLISH_FREIGHT_LIB      [/var/lib/freight] the freight libraries go to
#                            linuxfabrik-debian/ and linuxfabrik-ubuntu/ below it
#   PUBLISH_GITHUB_REPO      [Linuxfabrik/packaging]
#   PUBLISH_RPM_ARCHES       [aarch64 x86_64] arch directories that receive
#                            noarch packages
#   PUBLISH_SIGNER_WORKFLOW  [<PUBLISH_GITHUB_REPO>/.github/workflows/lf-release.yml]
#   PUBLISH_STATE_DIR        [/var/lib/linuxfabrik-publish] what was published
#                            already, and the generated freight configuration
#   PUBLISH_WEBROOT          [/var/www/html/repo.linuxfabrik.ch]
#
# Needs: createrepo_c, dpkg (dpkg-deb), freight, gh, gpg, jq, rpm-sign, sha256sum.
# The web server must follow symbolic links (bootstrap links, freight's dists/).
# PUBLISH_FREIGHT_LIB and PUBLISH_WEBROOT must be on one mount, in the mount
# namespace the script runs in (see check_freight_links).

set -e -o pipefail -u

PUBLISH_BASE_URL="${PUBLISH_BASE_URL:-https://repo.linuxfabrik.ch}"
PUBLISH_BOOTSTRAP_PACKAGES="${PUBLISH_BOOTSTRAP_PACKAGES:-linuxfabrik-release}"
PUBLISH_FREIGHT_LIB="${PUBLISH_FREIGHT_LIB:-/var/lib/freight}"
PUBLISH_GITHUB_REPO="${PUBLISH_GITHUB_REPO:-Linuxfabrik/packaging}"
PUBLISH_RPM_ARCHES="${PUBLISH_RPM_ARCHES:-aarch64 x86_64}"
PUBLISH_SIGNER_WORKFLOW="${PUBLISH_SIGNER_WORKFLOW:-$PUBLISH_GITHUB_REPO/.github/workflows/lf-release.yml}"
PUBLISH_STATE_DIR="${PUBLISH_STATE_DIR:-/var/lib/linuxfabrik-publish}"
PUBLISH_WEBROOT="${PUBLISH_WEBROOT:-/var/www/html/repo.linuxfabrik.ch}"

# Codename -> "<name> <version>" for the start page.
deb_release_name() {
    case "$1" in
    bookworm) echo 'Debian 12' ;;
    trixie) echo 'Debian 13' ;;
    forky) echo 'Debian 14' ;;
    jammy) echo 'Ubuntu 22.04' ;;
    noble) echo 'Ubuntu 24.04' ;;
    resolute) echo 'Ubuntu 26.04' ;;
    *) echo "$1" ;;
    esac
}

# Distro name as used by the build (build/containerfiles/) -> repository path.
# RPM targets map to "<os>/<os-version>", DEB targets to "<os> <codename>".
repo_target() {
    case "$1" in
    almalinux-v* | centos-v* | rhel-v* | rocky-v*) echo "el/${1#*-v}" ;;
    fedora-v*) echo "fedora/${1#fedora-v}" ;;
    # sle, not sles: the same repository serves SLES, SLED and openSUSE Leap
    # (verified with Leap 15.5 and 16.0), as repo.linuxfabrik.ch/monitoring-plugins/sle/ does
    sles-v*) echo "sle/${1#sles-v}" ;;
    debian-v12) echo 'debian bookworm' ;;
    debian-v13) echo 'debian trixie' ;;
    debian-v14) echo 'debian forky' ;;
    ubuntu-v2204) echo 'ubuntu jammy' ;;
    ubuntu-v2404) echo 'ubuntu noble' ;;
    ubuntu-v2604) echo 'ubuntu resolute' ;;
    *)
        echo "No repository target for distro $1" >&2
        return 1
        ;;
    esac
}

# Write the freight configuration for one DEB repository (debian or ubuntu).
freight_conf() {
    local os="$1"
    local conf="$PUBLISH_STATE_DIR/freight-$os.conf"
    cat > "$conf" <<EOF
VARLIB='$PUBLISH_FREIGHT_LIB/linuxfabrik-$os'
# freight defaults to "i386 amd64"; arm64 clients would not see Architecture: all
ARCHS='amd64 arm64'
VARCACHE='$PUBLISH_WEBROOT/$os/linuxfabrik'
ORIGIN='Linuxfabrik'
LABEL='Linuxfabrik'
CACHE='off'
GPG='$PUBLISH_GPG_KEY'
GPG_PASSPHRASE_FILE='$PUBLISH_GPG_PASSPHRASE_FILE'
GPG_DIGEST_ALGO='SHA512'
SYMLINKS='off'
EOF
    echo "$conf"
}

# Regenerate the metadata of one RPM repository directory and sign it.
rpm_update_repo() {
    local dir="$1"
    # gzip, not the zstd default of createrepo_c 1.x: libdnf on EL 8 cannot read
    # zstd metadata (verified: dnf 4.7 on Rocky 8 aborts with
    # "Assertion `fp_primary' failed" on a repository built on Rocky 10).
    createrepo_c --general-compress-type=gz --update --quiet "$dir"
    gpg --armor --batch --detach-sign --yes \
        --local-user "$PUBLISH_GPG_KEY" \
        --passphrase-file "$PUBLISH_GPG_PASSPHRASE_FILE" \
        --pinentry-mode loopback \
        "$dir/repodata/repomd.xml"
}

# The arch directories an RPM goes to: its own arch, or all for noarch.
rpm_arches() {
    local arch
    arch="$(rpm --query --queryformat '%{ARCH}' --package "$1")"
    if [ "$arch" = 'noarch' ]; then
        echo "$PUBLISH_RPM_ARCHES"
    else
        echo "$arch"
    fi
}

# Download the assets of a release into $1 and verify them: each file must be
# listed in SHA256SUMS and carry a valid build provenance attestation from the
# release workflow. Prints "<distro> <path>" per package file.
fetch_release() {
    local tag="$1" dir="$2"
    local file sha line distro name

    gh release download "$tag" --dir "$dir" --repo "$PUBLISH_GITHUB_REPO"

    for file in "$dir"/*; do
        gh attestation verify "$file" \
            --repo "$PUBLISH_GITHUB_REPO" \
            --signer-workflow "$PUBLISH_SIGNER_WORKFLOW" >/dev/null
    done

    # Map the files back to their distro by checksum. GitHub may rename an
    # asset, the checksum stays.
    declare -A by_sha=()
    for file in "$dir"/*; do
        [ "$(basename "$file")" = 'SHA256SUMS' ] && continue
        sha="$(sha256sum "$file" | cut --delimiter=' ' --fields=1)"
        by_sha[$sha]="$file"
    done
    while read -r sha line; do
        distro="${line%%/*}"
        name="${line#*/}"
        if [ -z "${by_sha[$sha]:-}" ]; then
            echo "$tag: $name for $distro is listed in SHA256SUMS but missing" >&2
            return 1
        fi
        # restore the original file name, freight and rpm care about it
        if [ "$(basename "${by_sha[$sha]}")" != "$name" ]; then
            mv "${by_sha[$sha]}" "$dir/$name"
        fi
        echo "$distro $dir/$name"
    done < "$dir/SHA256SUMS"
}

# Add the verified packages of a release to a channel.
publish_release() {
    local tag="$1" channel="$2" dir="$3"
    local distro file target os codename arch repo_dir
    local -A deb_dirty=()
    local -A rpm_dirty=()

    # Not `done < <(fetch_release ...)`: bash ignores the exit code of a process
    # substitution, and a failed verification must stop the run.
    fetch_release "$tag" "$dir" > "$dir.files"
    while read -r distro file; do
        target="$(repo_target "$distro")"
        case "$file" in
        *.rpm)
            rpmsign --addsign \
                --define "_gpg_name $PUBLISH_GPG_KEY" \
                --define "_gpg_sign_cmd_extra_args --batch --pinentry-mode loopback --passphrase-file $PUBLISH_GPG_PASSPHRASE_FILE" \
                "$file" >/dev/null
            for arch in $(rpm_arches "$file"); do
                repo_dir="$PUBLISH_WEBROOT/$target/$arch/linuxfabrik/$channel"
                mkdir --parents "$repo_dir"
                cp "$file" "$repo_dir/"
                rpm_dirty[$repo_dir]=1
            done
            ;;
        *.deb)
            read -r os codename <<< "$target"
            freight-add --conf="$(freight_conf "$os")" "$file" "apt/$codename-$channel"
            deb_dirty[$os]=1
            ;;
        esac
        echo "$tag: $(basename "$file") -> $target $channel"
    done < "$dir.files"

    for repo_dir in "${!rpm_dirty[@]}"; do
        rpm_update_repo "$repo_dir"
    done
    for os in "${!deb_dirty[@]}"; do
        freight-cache --conf="$(freight_conf "$os")"
    done

    if [ "$channel" = 'release' ]; then
        while read -r distro file; do
            bootstrap_link "$distro" "$file"
        done < "$dir.files"
    fi
}

# Point the stable bootstrap URL of a package in PUBLISH_BOOTSTRAP_PACKAGES at
# its newest build in the release channel, e.g.
#   linuxfabrik-release-latest-el10.noarch.rpm -> el/10/aarch64/linuxfabrik/release/...
#   linuxfabrik-release-latest-debian13.deb    -> debian/linuxfabrik/pool/trixie-release/...
# A host without the repository installs the package from there, the way
# epel-release-latest-10.noarch.rpm works for EPEL.
bootstrap_link() {
    local distro="$1" file="$2"
    local name distro_tag target os codename arch published link
    local -a arch_dirs

    case "$file" in
    *.rpm) name="$(rpm --query --queryformat '%{NAME}' --package "$file" 2>/dev/null)" ;;
    *.deb) name="$(dpkg-deb --field "$file" Package)" ;;
    esac
    if [[ " $PUBLISH_BOOTSTRAP_PACKAGES " != *" $name "* ]]; then
        return 0
    fi

    case "$distro" in
    almalinux-v* | centos-v* | rhel-v* | rocky-v*) distro_tag="el${distro#*-v}" ;;
    sles-v*) distro_tag="sle${distro#sles-v}" ;;
    ubuntu-v*)
        distro_tag="${distro#ubuntu-v}"
        distro_tag="ubuntu${distro_tag:0:2}.${distro_tag:2}"
        ;;
    *) distro_tag="${distro/-v/}" ;;
    esac

    target="$(repo_target "$distro")"
    case "$file" in
    *.rpm)
        arch="$(rpm --query --queryformat '%{ARCH}' --package "$file" 2>/dev/null)"
        read -r -a arch_dirs <<< "$(rpm_arches "$file")"
        published="$target/${arch_dirs[0]}/linuxfabrik/release/$(basename "$file")"
        link="$name-latest-$distro_tag.$arch.rpm"
        ;;
    *.deb)
        read -r os codename <<< "$target"
        published="$(cd "$PUBLISH_WEBROOT" \
            && find "$os/linuxfabrik/pool/$codename-release" -name "$(basename "$file")" -print -quit)"
        link="$name-latest-$distro_tag.deb"
        ;;
    esac
    if [ ! -f "$PUBLISH_WEBROOT/$published" ]; then
        echo "Cannot link $link: $published is not published" >&2
        return 1
    fi
    # relative, so the link survives a move of the webroot
    ln --force --no-dereference --symbolic "$published" "$PUBLISH_WEBROOT/$link"
    echo "$link -> $published"
}

# Remove the packages of a rejected release from the testing channel.
reject_release() {
    local tag="$1" dir="$2"
    local distro file target os codename arch repo_dir
    local -A deb_dirty=()
    local -A rpm_dirty=()

    fetch_release "$tag" "$dir" > "$dir.files"
    while read -r distro file; do
        target="$(repo_target "$distro")"
        case "$file" in
        *.rpm)
            for arch in $(rpm_arches "$file"); do
                repo_dir="$PUBLISH_WEBROOT/$target/$arch/linuxfabrik/testing"
                rm --force "$repo_dir/$(basename "$file")"
                rpm_dirty[$repo_dir]=1
            done
            ;;
        *.deb)
            read -r os codename <<< "$target"
            # freight-cache rebuilds the suite from what is left in its library
            rm --force "$PUBLISH_FREIGHT_LIB/linuxfabrik-$os/apt/$codename-testing/$(basename "$file")"
            deb_dirty[$os]=1
            ;;
        esac
        echo "$tag: $(basename "$file") removed from $target testing"
    done < "$dir.files"

    for repo_dir in "${!rpm_dirty[@]}"; do
        rpm_update_repo "$repo_dir"
    done
    for os in "${!deb_dirty[@]}"; do
        freight-cache --conf="$(freight_conf "$os")"
    done
}

# Print the newest version of every package in one channel, "<name> <version>"
# per line, without the dist tag (.el10, .fc44, .sle16) or the distro suffix
# (+debian13). $2 is an RPM repository directory or a freight Packages file.
channel_packages() {
    local kind="$1" path="$2" file

    case "$kind" in
    rpm)
        for file in "$path"/*.rpm; do
            [ -e "$file" ] || continue
            rpm --query --queryformat '%{NAME} %{VERSION}-%{RELEASE}\n' --package "$file" 2>/dev/null
        done | sed -E 's/\.(el|fc|sle)[0-9]+$//'
        ;;
    deb)
        [ -r "$path" ] || return 0
        awk '/^Package:/ {p = $2} /^Version:/ {print p, $2}' "$path" \
            | sed -E 's/\+(debian|ubuntu)[0-9.]+$//'
        ;;
    esac | sort -k1,1 -k2,2V | awk '{v[$1] = $2} END {for (p in v) print p, v[p]}' | sort
}

# Print one <details> block of the start page: how to set up the repository on
# a distro, and which packages it has in release and testing.
render_distro() {
    local label="$1" kind="$2" tag="$3" release="$4" testing="$5"
    local url="$PUBLISH_BASE_URL" bootstrap name rel tst count

    case "$kind" in
    deb) bootstrap="linuxfabrik-release-latest-$tag.deb" ;;
    *) bootstrap="linuxfabrik-release-latest-$tag.noarch.rpm" ;;
    esac

    # names of all packages in either channel, except the setup package itself
    local names
    names="$( { channel_packages "${kind%%-*}" "$release"; channel_packages "${kind%%-*}" "$testing"; } \
        | awk '{print $1}' | grep -v -x -F "$PUBLISH_BOOTSTRAP_PACKAGES" | sort -u || true)"
    count="$(grep -c . <<< "$names" || true)"

    case "$count" in
    0) count='no packages yet' ;;
    1) count='1 package' ;;
    *) count="$count packages" ;;
    esac
    echo '<details>'
    echo "<summary><strong>$label</strong> &middot; $count</summary>"
    if [ -e "$PUBLISH_WEBROOT/$bootstrap" ]; then
        echo '<pre>'
        case "$kind" in
        rpm-dnf) echo "sudo dnf install $url/$bootstrap" ;;
        rpm-zypper)
            echo "sudo rpm --import $url/linuxfabrik.key"
            echo "sudo zypper install $url/$bootstrap"
            ;;
        deb)
            echo "curl --fail --location --remote-name $url/$bootstrap"
            echo "sudo apt install ./$bootstrap"
            echo 'sudo apt update'
            ;;
        esac
        echo '</pre>'
    else
        echo "<p class=\"warning\">$PUBLISH_BOOTSTRAP_PACKAGES is not released for this distro yet.</p>"
    fi
    if [ -n "$names" ]; then
        echo '<div class="markdown-body"><table>'
        echo '<tr><th>Package</th><th>release</th><th>testing</th></tr>'
        while read -r name; do
            rel="$(channel_packages "${kind%%-*}" "$release" | awk -v n="$name" '$1 == n {print $2}')"
            tst="$(channel_packages "${kind%%-*}" "$testing" | awk -v n="$name" '$1 == n {print $2}')"
            # testing only matters where it is ahead of release
            [ "$tst" = "$rel" ] && tst=''
            echo "<tr><td>$name</td><td>${rel:-&ndash;}</td><td>${tst:-&ndash;}</td></tr>"
        done <<< "$names"
        echo '</table></div>'
    fi
    echo '</details>'
}

# Write the start page of the webroot from what is published right now: setup
# commands and packages per distro, channels, signing key. Replaces the
# directory listing as the landing page; the directories stay browsable.
render_index() {
    local page="$PUBLISH_WEBROOT/index.html" tmp dir os version arch dist codename
    local fingerprint
    # style.css shows code as blocks, which breaks sentences apart. The override
    # is a file of its own, because the proxy in front of this server only
    # allows same-origin stylesheets (CSP style-src 'self'), no inline <style>.
    tmp="$(mktemp "$PUBLISH_WEBROOT/.index.css.XXXXXX")"
    echo 'p code { display: inline; }' > "$tmp"
    chmod 0644 "$tmp"
    mv "$tmp" "$PUBLISH_WEBROOT/index.css"

    tmp="$(mktemp "$PUBLISH_WEBROOT/.index.html.XXXXXX")"
    fingerprint="$(sed -E 's/(.{4})/\1 /g; s/ $//' <<< "$PUBLISH_GPG_KEY")"

    {
        cat <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Linuxfabrik Package Repository</title>
<link rel="stylesheet" href="/assets/style.css" type="text/css">
<link rel="stylesheet" href="/index.css" type="text/css">
</head>
<body>
<div id="header">
  <h1><a href="$PUBLISH_BASE_URL"><img src="/assets/linuxfabrik-logo.svg" alt="Linuxfabrik" class="inline" width="200" height="127"></a> Package Repository</h1>
</div>

<p>Signed RPM and DEB packages of Linuxfabrik's own software and of third-party software
that the distributions do not ship, built from the upstream sources in
<a href="https://github.com/$PUBLISH_GITHUB_REPO">$PUBLISH_GITHUB_REPO</a>.
One repository per distribution, for x86_64 and aarch64.</p>

<h2>Set up the repository</h2>
<p><code>linuxfabrik-release</code> configures the repository and installs the signing key.
Pick your distribution:</p>
EOF

        for dir in $(find "$PUBLISH_WEBROOT/el" "$PUBLISH_WEBROOT/fedora" "$PUBLISH_WEBROOT/sle" \
            -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -V); do
            os="$(basename "$(dirname "$dir")")"
            version="$(basename "$dir")"
            arch=''
            for arch in x86_64 aarch64; do
                [ -d "$dir/$arch/linuxfabrik" ] && break
            done
            case "$os" in
            el) render_distro "RHEL $version and compatibles" rpm-dnf "el$version" \
                "$dir/$arch/linuxfabrik/release" "$dir/$arch/linuxfabrik/testing" ;;
            fedora) render_distro "Fedora $version" rpm-dnf "fedora$version" \
                "$dir/$arch/linuxfabrik/release" "$dir/$arch/linuxfabrik/testing" ;;
            sle) render_distro "SLES and openSUSE Leap $version" rpm-zypper "sle$version" \
                "$dir/$arch/linuxfabrik/release" "$dir/$arch/linuxfabrik/testing" ;;
            esac
        done

        for os in debian ubuntu; do
            dist="$PUBLISH_WEBROOT/$os/linuxfabrik/dists"
            [ -d "$dist" ] || continue
            # freight keeps <suite>-<timestamp> directories next to the <suite> links
            for codename in $(find "$dist" -mindepth 1 -maxdepth 1 -printf '%f\n' \
                | sed -n -E 's/^([a-z]+)-(release|testing)$/\1/p' | sort -u); do
                version="$(deb_release_name "$codename")"
                render_distro "$version ($codename)" deb "$(tr -d ' ' <<< "${version,,}")" \
                    "$dist/$codename-release/main/binary-amd64/Packages" \
                    "$dist/$codename-testing/main/binary-amd64/Packages"
            done
        done

        cat <<EOF

<p>Derivatives use the repository of their base: Rocky Linux, AlmaLinux, Oracle Linux and
CentOS Stream the RHEL one, Linux Mint and other Ubuntu-based distributions the Ubuntu one
of their base release, LMDE the Debian one.</p>
<p>On RHEL and compatibles, some packages depend on EPEL and the CRB repository.</p>

<h2>Channels</h2>
<p>New versions land in <strong>testing</strong> first and move to <strong>release</strong>
after seven days. <code>linuxfabrik-release</code> enables release and configures testing,
disabled. To try new versions early, enable testing:</p>
<pre>
sudo dnf config-manager --set-enabled linuxfabrik-testing        # RHEL 8, 9 and 10
sudo dnf config-manager setopt linuxfabrik-testing.enabled=1     # Fedora
sudo zypper modifyrepo --enable linuxfabrik-testing              # SLES, openSUSE Leap
</pre>
<p>On Debian and Ubuntu, set <code>Enabled: yes</code> for the testing entry in
<code>/etc/apt/sources.list.d/linuxfabrik.sources</code>.</p>

<h2>Signing key</h2>
<p>Packages and repository metadata are signed with
<a href="$PUBLISH_BASE_URL/linuxfabrik.key">linuxfabrik.key</a>, fingerprint
<code>$fingerprint</code>. <code>linuxfabrik-release</code> installs it.</p>

<h2>How the packages are built</h2>
<p>From the upstream source, with the distribution's own toolchain and dependencies, on
GitHub Actions, and smoke-tested on every target before release. Each build is published
with a build provenance attestation, which this server verifies before it signs and
publishes the package. Details:
<a href="https://github.com/$PUBLISH_GITHUB_REPO/blob/main/CONTRIBUTING.md">CONTRIBUTING.md</a>,
all builds: <a href="https://github.com/$PUBLISH_GITHUB_REPO/releases">GitHub releases</a>.</p>

<h2>Other repositories on this server</h2>
<p>These repositories are not covered by <code>linuxfabrik-release</code> and have their
own setup.</p>
<ul>
<li><a href="/monitoring-plugins/">monitoring-plugins/</a>: the
<a href="https://github.com/Linuxfabrik/monitoring-plugins">Linuxfabrik Monitoring Plugins</a>,
installed with <a href="/install-monitoring-plugins">install-monitoring-plugins</a></li>
<li><a href="/exoscale/cli/">exoscale/cli/</a>: RPMs from the GitHub releases of
<a href="https://github.com/exoscale/cli">Exoscale's CLI</a></li>
<li><a href="/mydumper/">mydumper/</a>: RPMs from the GitHub releases of
<a href="https://github.com/mydumper/mydumper">MyDumper</a></li>
</ul>
<p>Browse the repositories directly: <a href="/el/">el/</a>, <a href="/fedora/">fedora/</a>,
<a href="/sle/">sle/</a>, <a href="/debian/">debian/</a>, <a href="/ubuntu/">ubuntu/</a>.</p>

<hr>
<address>Generated from the repository contents on $(date --utc '+%Y-%m-%d %H:%M UTC').</address>
</body>
</html>
EOF
    } > "$tmp"
    chmod 0644 "$tmp"
    mv "$tmp" "$page"
}

# freight hard-links the packages from its library into the webroot. If the two
# are on different mounts, ln fails with EXDEV and freight silently copies
# instead; at the end of every freight-cache it then deletes all pool files with
# a link count of 1 (`find pool -links 1 -delete`), i.e. the copies of earlier
# releases, which then answer 404 while still listed in Packages. Seen on
# 001-p-repo51 (freight 0.3.13, Rocky 9) with systemd's
# ReadWritePaths=/var/lib/freight /var/www/html/..., which makes each path its own
# bind mount even on one filesystem. Refuse to run in that setup.
check_freight_links() {
    local probe="$PUBLISH_FREIGHT_LIB/.publish-link-probe.$$"
    local target="$PUBLISH_WEBROOT/.publish-link-probe.$$"
    local rc=0

    touch "$probe"
    ln "$probe" "$target" 2>/dev/null || rc=$?
    rm --force "$probe" "$target"
    if [ "$rc" -ne 0 ]; then
        echo "Cannot hard-link from PUBLISH_FREIGHT_LIB ($PUBLISH_FREIGHT_LIB) into PUBLISH_WEBROOT ($PUBLISH_WEBROOT)." >&2
        echo 'They must be on one mount, or freight deletes the pool files of earlier releases.' >&2
        echo 'Under systemd sandboxing, list a common parent in ReadWritePaths= (e.g. /var).' >&2
        return 1
    fi
}

main() {
    local tag name prerelease channel workdir
    local done_dir="$PUBLISH_STATE_DIR/done"

    mkdir --parents "$done_dir" "$PUBLISH_FREIGHT_LIB" "$PUBLISH_WEBROOT"
    check_freight_links

    # one run at a time, the timer may fire while a long run is still going
    exec 9> "$PUBLISH_STATE_DIR/lock"
    if ! flock --nonblock 9; then
        echo 'Another run is still active, skipping.'
        return 0
    fi

    # Oldest first: a server set up from scratch replays the releases in the
    # order they happened, so the newest build ends up behind a bootstrap link.
    gh release list \
        --exclude-drafts \
        --json 'isPrerelease,name,tagName' \
        --limit 1000 \
        --repo "$PUBLISH_GITHUB_REPO" \
        --jq 'reverse | .[] | "\(.tagName) \(.isPrerelease) \(.name)"' \
        | while read -r tag prerelease name; do
            if [ "$prerelease" = 'true' ] && [[ "$name" == *'(rejected)' ]]; then
                channel='rejected'
            elif [ "$prerelease" = 'true' ]; then
                channel='testing'
            else
                channel='release'
            fi

            # A rejection only has to undo a testing publication that happened.
            if [ "$channel" = 'rejected' ] && [ ! -e "$done_dir/$tag.testing" ]; then
                continue
            fi
            [ -e "$done_dir/$tag.$channel" ] && continue

            workdir="$(mktemp --directory)"
            if [ "$channel" = 'rejected' ]; then
                reject_release "$tag" "$workdir"
                rm --force "$done_dir/$tag.testing"
            else
                publish_release "$tag" "$channel" "$workdir"
            fi
            touch "$done_dir/$tag.$channel"
            rm --recursive --force "$workdir" "$workdir.files"
        done

    render_index
}

main "$@"
