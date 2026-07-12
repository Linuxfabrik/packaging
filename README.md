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


## Repository layout

```
packages/<name>/
  package.conf            # manifest: source, version, per-format distro targets
  rpm/<name>.spec         # RPM recipe (EL, Fedora, SLES)
  deb/debian/             # DEB recipe (control, rules, copyright, source/format)
  files/                  # shared assets, e.g. the systemd unit
build/
  containerfiles/         # one build environment per distro (rocky-*, fedora-*, debian-*, ...)
  create-package.sh       # entry point: fetch source, dispatch to the format builder
  create-rpm.sh           # build a binary RPM from a spec (dnf or zypper)
  create-deb.sh           # build a binary .deb from a debian/ recipe
  matrix-package.sh       # build one package across many distros, each in a container
  publish.sh              # hand the built packages to the repo server
```


## Adding a package

1. Create `packages/<name>/` with `package.conf`, the recipes you need (`rpm/`, `deb/`) and any shared `files/`.
2. Set the source, version and the `PKG_RPM_DISTROS` / `PKG_DEB_DISTROS` targets in `package.conf`.
3. Build locally to verify (see below).
4. Open a pull request. On merge, the pipeline builds and publishes the package.

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

Built packages are collected under `packaged/<distro>/`.


## Support the Project

Enterprise support, including an SLA, is available via a [Service Contract](https://www.linuxfabrik.ch/en/products/service-support).

If this project helps you, consider a donation via
[GitHub Sponsors](https://github.com/sponsors/Linuxfabrik) or
[PayPal](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=7AW3VVX62TR4A&source=url).

There is no fixed roadmap. Milestones are driven by customer needs and by contributors' time.
