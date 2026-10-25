# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).


## [Unreleased]

### Added

* Build pipeline that turns Linuxfabrik's own and third-party software into RPM and DEB packages for EL, Fedora, SLES, Debian and Ubuntu.
* DEB packages carry the target distro in their version (e.g. `4.5.8-1+debian13`), so each suite gets its own build.
* glances packages for EL, Fedora, Debian and Ubuntu.
* New upstream releases are packaged and published automatically, first to the `testing` channel and after seven days to `release`.
* One signed repository per distribution for all Linuxfabrik packages on repo.linuxfabrik.ch, with signed metadata for `repo_gpgcheck=1`.

[Unreleased]: https://github.com/Linuxfabrik/packaging/commits/main
