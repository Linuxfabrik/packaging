<h1 align="center">
  <a href="https://linuxfabrik.ch" target="_blank">Linuxfabrik</a> Packaging
</h1>
<p align="center">
  Build pipeline that turns Linuxfabrik's own and third-party software into RPM and DEB packages and publishes them on <a href="https://repo.linuxfabrik.ch">repo.linuxfabrik.ch</a>.
  <span>&#8226;</span>
  <b>made by <a href="https://linuxfabrik.ch/">Linuxfabrik</a></b>
</p>
<div align="center" markdown>

![License](https://img.shields.io/github/license/linuxfabrik/packaging)
![GitHub Issues](https://img.shields.io/github/issues/linuxfabrik/packaging)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/Linuxfabrik/packaging/badge)](https://scorecard.dev/viewer/?uri=github.com/Linuxfabrik/packaging)
[![GitHubSponsors](https://img.shields.io/github/sponsors/Linuxfabrik?label=GitHub%20Sponsors)](https://github.com/sponsors/Linuxfabrik)
[![PayPal](https://img.shields.io/badge/Donate-PayPal-green.svg)](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=7AW3VVX62TR4A&source=url)

</div>

<br />


# Linuxfabrik Packaging

This repository is the single, organization-wide place where Linuxfabrik software is turned into
RPM and DEB packages for [repo.linuxfabrik.ch](https://repo.linuxfabrik.ch). It packages both
Linuxfabrik's own products (e.g. FirewallFabrik) and third-party upstream software (e.g. glances,
mysqltuner, mydumper). Source repositories stay source-only; the build recipes and pipeline live
here once instead of being duplicated into every project's CI.

Each package lives under `packages/<name>/` and brings its RPM and/or DEB recipe plus a small
`package.conf` manifest. The build is package-agnostic: the manifest declares the source and the
target distributions, and the shared scripts under `build/` fetch the source, build inside a
per-distro container and collect the resulting packages, one file per distro and version.

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to add a package and for the packaging conventions
(distro-native builds, basing third-party recipes on the official packaging, the split-package
pattern for GUI apps, and the release trigger).


## Using the repository

`linuxfabrik-release` sets up the signed Linuxfabrik repository on a host, the way `epel-release` does for EPEL: the repository configuration with the `release` channel enabled and the `testing` channel disabled, and the key the packages and the repository metadata are signed with.

RHEL 8, 9 and 10 and compatibles (replace `el10` with `el8` or `el9`):

```bash
sudo dnf install https://repo.linuxfabrik.ch/linuxfabrik-release-latest-el10.noarch.rpm
```

Fedora:

```bash
sudo dnf install https://repo.linuxfabrik.ch/linuxfabrik-release-latest-fedora44.noarch.rpm
```

SLES and openSUSE Leap 15 and 16 (replace `sle16` with `sle15`):

```bash
sudo rpm --import https://repo.linuxfabrik.ch/linuxfabrik.key
sudo zypper install https://repo.linuxfabrik.ch/linuxfabrik-release-latest-sle16.noarch.rpm
```

Debian 12 and 13, Ubuntu 22.04, 24.04 and 26.04 (replace `debian13` with `debian12`, `ubuntu22.04`, `ubuntu24.04` or `ubuntu26.04`):

```bash
curl --fail --location --remote-name https://repo.linuxfabrik.ch/linuxfabrik-release-latest-debian13.deb
sudo apt install ./linuxfabrik-release-latest-debian13.deb
sudo apt update
```

Then install packages as usual, e.g. `sudo dnf install glances`. On RHEL and compatibles, some packages depend on EPEL; glances, for example, needs `epel-release` and the CRB repository.

New package versions wait in the `testing` channel for 7 days before they reach `release`. To try them earlier, enable `linuxfabrik-testing` (`dnf config-manager --set-enabled linuxfabrik-testing`, `zypper modifyrepo --enable linuxfabrik-testing`), or on Debian and Ubuntu set `Enabled: yes` for the testing entry in `/etc/apt/sources.list.d/linuxfabrik.sources`.


## Repository layout

```
packages/<name>/
  package.conf            # manifest: source, version, per-format distro targets
  src/                    # own source, for packages without an upstream (PKG_SOURCE_DIR)
  rpm/<name>.spec         # RPM recipe (EL, Fedora, SLES)
  deb/debian/             # DEB recipe (control, rules, copyright, source/format)
  files/                  # shared assets, e.g. the systemd unit
build/
  changed-packages.sh     # which packages a commit range touches (for CI)
  check-upstream.sh       # is a package behind its upstream release?
  containerfiles/         # one build environment per distro (rocky-*, fedora-*, debian-*, ...)
  create-package.sh       # entry point: fetch source, dispatch to the format builder
  create-rpm.sh           # build a binary RPM from a spec (dnf or zypper)
  create-deb.sh           # build a binary .deb from a debian/ recipe
  matrix-package.sh       # build one package across many distros, each in a container
  publish.sh              # on the repo server: pull, verify, sign and publish releases
  smoke-test-package.sh   # install a build into a fresh container and run its smoke test
```


## Adding a package

1. Create `packages/<name>/` with `package.conf`, the recipes you need (`rpm/`, `deb/`) and any shared `files/`.
2. Set the source, version and the `PKG_RPM_DISTROS` / `PKG_DEB_DISTROS` targets in `package.conf`.
3. Build locally to verify (see below).
4. Open a pull request. On merge, the pipeline builds the package and publishes it to the `testing` channel; seven days later it moves to `release`.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the details.


## Building locally

```bash
PKG_NAME=glances \
PKG_TARGET_DISTROS='rocky-v10 debian-v13' \
PKG_PACKAGE_ITERATION=1 \
PKG_ARCH=x86_64 \
PKG_DIR_REPO="$(pwd)" \
PKG_DIR_PACKAGED="$(pwd)/packaged" \
bash build/matrix-package.sh
```

Built packages are collected under `packaged/<distro>/`. Each one is then installed into a fresh container of its distro and smoke-tested.


## Support the Project

Enterprise support, including an SLA, is available via a [Service Contract](https://www.linuxfabrik.ch/en/products/service-support).

If this project helps you, consider a donation via
[GitHub Sponsors](https://github.com/sponsors/Linuxfabrik) or
[PayPal](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=7AW3VVX62TR4A&source=url).

There is no fixed roadmap. Milestones are driven by customer needs and by contributors' time.
