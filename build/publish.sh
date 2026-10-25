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
#   RPM: <el|fedora|sles>/<os-version>/<arch>/linuxfabrik/<channel>/
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
# Needs: createrepo_c, freight, gh, gpg, jq, rpm-sign, sha256sum.

set -e -o pipefail -u

PUBLISH_FREIGHT_LIB="${PUBLISH_FREIGHT_LIB:-/var/lib/freight}"
PUBLISH_GITHUB_REPO="${PUBLISH_GITHUB_REPO:-Linuxfabrik/packaging}"
PUBLISH_RPM_ARCHES="${PUBLISH_RPM_ARCHES:-aarch64 x86_64}"
PUBLISH_SIGNER_WORKFLOW="${PUBLISH_SIGNER_WORKFLOW:-$PUBLISH_GITHUB_REPO/.github/workflows/lf-release.yml}"
PUBLISH_STATE_DIR="${PUBLISH_STATE_DIR:-/var/lib/linuxfabrik-publish}"
PUBLISH_WEBROOT="${PUBLISH_WEBROOT:-/var/www/html/repo.linuxfabrik.ch}"

# Distro name as used by the build (build/containerfiles/) -> repository path.
# RPM targets map to "<os>/<os-version>", DEB targets to "<os> <codename>".
repo_target() {
    case "$1" in
    almalinux-v* | centos-v* | rhel-v* | rocky-v*) echo "el/${1#*-v}" ;;
    fedora-v*) echo "fedora/${1#fedora-v}" ;;
    sles-v*) echo "sles/${1#sles-v}" ;;
    debian-v11) echo 'debian bullseye' ;;
    debian-v12) echo 'debian bookworm' ;;
    debian-v13) echo 'debian trixie' ;;
    debian-v14) echo 'debian forky' ;;
    ubuntu-v2004) echo 'ubuntu focal' ;;
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
    createrepo_c --update --quiet "$dir"
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

main() {
    local tag name prerelease channel workdir
    local done_dir="$PUBLISH_STATE_DIR/done"

    mkdir --parents "$done_dir"

    # one run at a time, the timer may fire while a long run is still going
    exec 9> "$PUBLISH_STATE_DIR/lock"
    if ! flock --nonblock 9; then
        echo 'Another run is still active, skipping.'
        return 0
    fi

    gh release list \
        --exclude-drafts \
        --json 'isPrerelease,name,tagName' \
        --limit 1000 \
        --repo "$PUBLISH_GITHUB_REPO" \
        --jq '.[] | "\(.tagName) \(.isPrerelease) \(.name)"' \
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
}

main "$@"
