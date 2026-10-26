# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).


## [Unreleased]

### Added

* Build pipeline that turns Linuxfabrik's own and third-party software into RPM and DEB packages for EL, Fedora, SLES, Debian and Ubuntu.
* DEB packages carry the target distro in their version (e.g. `4.5.8-1+debian13`), so each suite gets its own build.
* exoscale-cli (`exo`) packages for RHEL 8 to 10, Fedora, SLES and openSUSE Leap 15 and 16, Debian 12 and 13 and Ubuntu 22.04 to 26.04, built from source; they replace the upstream RPM mirrored under repo.linuxfabrik.ch/exoscale/cli and update hosts that installed it.
* FirewallFabrik packages for RHEL 10, Fedora 44, Debian 13 and Ubuntu 26.04, split into the compilers (`linuxfabrik-firewallfabrik`) and the GUI (`linuxfabrik-firewallfabrik-gui`), with man pages; they replace the `firewallfabrik` packages from mirror.plustech.de.
* glances packages for EL, Fedora, Debian and Ubuntu.
* `linuxfabrik-release` sets up the Linuxfabrik repository with one install command, for RHEL 8 to 10, Fedora, SLES and openSUSE Leap 15 and 16, Debian 12 and 13 and Ubuntu 22.04 to 26.04.
* New upstream releases are packaged and published automatically, first to the `testing` channel and after seven days to `release`.
* One signed repository per distribution for all Linuxfabrik packages on repo.linuxfabrik.ch, with signed metadata for `repo_gpgcheck=1`.
* Packages are built and smoke-tested for aarch64 (arm64) as well, natively on arm64 build machines.

### Changed

* `linuxfabrik-release`: if repo.linuxfabrik.ch cannot be reached, dnf skips the Linuxfabrik repositories with a warning instead of failing.
* `linuxfabrik-release`: unattended dnf runs such as `dnf-makecache.service` work right after the installation. The check of the repository metadata signature (`repo_gpgcheck`) is off, packages are still signature-checked.

### Fixed

* RPM packages carry a changelog entry for their own version instead of a fixed one.

[Unreleased]: https://github.com/Linuxfabrik/packaging/commits/main
