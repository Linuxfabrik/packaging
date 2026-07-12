# Contributing


## Linuxfabrik Standards

The following standards apply to all Linuxfabrik repositories.


### Code of Conduct

Please read and follow our [Code of Conduct](CODE_OF_CONDUCT.md).


### Issue Tracking

Open issues are tracked on GitHub Issues in the respective repository. In addition to the GitHub default labels (`bug`, `documentation`, `duplicate`, `enhancement`, `good first issue`, `help wanted`, `invalid`, `question`, `wontfix`), the following project-specific labels are used:

| Label | Use for |
|---|---|
| `build` | Packaging, build scripts, distribution artifacts. |
| `ci/cd` | Continuous integration, GitHub Actions workflows, release automation, test automation. |
| `dependencies` | Pull requests opened by Dependabot. |
| `github_actions` | Pull requests that update GitHub Actions workflow definitions or pinned action SHAs. |
| `python` | Pull requests that update Python dependencies. |

When opening a new issue, attach the label that matches the area of work. The `build` and `ci/cd` labels mirror the conventional commit scopes used in the same areas (`fix(build): ...`, `chore(ci/cd): ...`).


### Pre-commit

Some repositories use [pre-commit](https://pre-commit.com/) for automated linting and formatting checks. If the repository contains a `.pre-commit-config.yaml`, install [pre-commit](https://pre-commit.com/#install) and configure the hooks after cloning:

```bash
pre-commit install
```


### Commit Messages

Commit messages follow the [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) specification:

```
<type>(<scope>): <subject>
```

If there is a related issue, append `(fix #N)`:

```
<type>(<scope>): <subject> (fix #N)
```

`<type>` must be one of:

- `chore`: Changes to the build process or auxiliary tools and libraries
- `docs`: Documentation only changes
- `feat`: A new feature
- `fix`: A bug fix
- `perf`: A code change that improves performance
- `refactor`: A code change that neither fixes a bug nor adds a feature
- `style`: Changes that do not affect the meaning of the code (whitespace, formatting, etc.)
- `test`: Adding missing tests


### Changelog

Document all changes in `CHANGELOG.md` following [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Sort entries within sections alphabetically.


### Language

Code, comments, commit messages, and documentation must be written in English.


### CI Supply Chain

GitHub Actions in `.github/workflows/` are pinned by commit SHA, not by tag. Dependabot's `github-actions` ecosystem keeps these pins up to date.

Python packages installed via `pip` inside workflows follow a two-tier policy:

- `pre-commit` is installed from a hash-pinned requirements file at `.github/pre-commit/requirements.txt`, generated with `pip-compile --generate-hashes --strip-extras` from `.github/pre-commit/requirements.in`. Dependabot's `pip` ecosystem watches that directory and maintains both files.
- One-shot installs such as `ansible-builder`, `build`, `mkdocs`, `pdoc`, and `ruff` in release, docs, or test workflows are version-pinned only (`package==X.Y.Z`) and kept fresh by Dependabot. Scorecard's `pipCommand not pinned by hash` findings for these are considered acceptable risk and may be dismissed.


### Coding Conventions

- Sort variables, parameters, lists, and similar items alphabetically where possible.
- Always use long parameters when using shell commands.
- Use RFC [5737](https://datatracker.ietf.org/doc/html/rfc5737), [3849](https://datatracker.ietf.org/doc/html/rfc3849), [7042](https://datatracker.ietf.org/doc/html/rfc7042#section-2.1.1), and [2606](https://datatracker.ietf.org/doc/html/rfc2606) in examples and documentation:
    - IPv4: `192.0.2.0/24`, `198.51.100.0/24`, `203.0.113.0/24`
    - IPv6: `2001:DB8::/32`
    - MAC: `00-00-5E-00-53-00` through `00-00-5E-00-53-FF` (unicast), `01-00-5E-90-10-00` through `01-00-5E-90-10-FF` (multicast)
    - Domains: `*.example`, `example.com`


---


This repository builds Linuxfabrik RPM, DEB and pacman packages from both
Linuxfabrik's own products and third-party upstream software, and publishes them
on [repo.linuxfabrik.ch](https://repo.linuxfabrik.ch). It is open to an arbitrary
number of packages.


## Concepts

A *package* is one piece of software we ship, living under `packages/<name>/`.
Each package brings:

- `package.conf`: the manifest, sourced by the build scripts. It declares the
  source, the version to package and the per-format target distributions.
- `rpm/<name>.spec`: the RPM recipe (EL, Fedora, SLES).
- `deb/debian/`: the DEB recipe (`control`, `rules`, `copyright`, `source/format`).
- `arch/PKGBUILD`: the pacman recipe (Arch).
- `files/`: assets shared between the formats, e.g. the systemd unit.

A package only ships the recipes for the formats it targets. The build is
package-agnostic: `build/create-package.sh` reads the manifest, fetches the
source and dispatches to `create-rpm.sh`, `create-deb.sh` or `create-pacman.sh`
depending on the target distro. `matrix-package.sh` runs that across many distros,
each inside the matching container from `build/containerfiles/`.


## Package formats

Each `package.conf` declares, per format, the recipe and the distro targets it applies to. A
package only targets the formats and distros it needs:

- **RPM** (`PKG_RPM_SPEC`, `PKG_RPM_DISTROS`): EL (`rocky-*`, `rhel-*`, `almalinux-*`,
  `centos-*`), `fedora-*` and `sles-*`. Built with `rpmbuild`; build dependencies are resolved
  with `dnf builddep` on EL/Fedora and with a zypper fallback on SLES.
- **DEB** (`PKG_DEB_DEBIAN_DIR`, `PKG_DEB_DISTROS`): `debian-*`, `ubuntu-*`. Built with `debuild`.
- **pacman** (`PKG_PKGBUILD`, `PKG_PACMAN_DISTROS`): `arch`. Built with `makepkg` as an
  unprivileged user, since makepkg refuses to run as root.


## Why native recipes, not FPM

We build with each format's native tooling (`rpmbuild` / `debuild` / `makepkg`) and hand-written
recipes rather than a cross-format generator such as [FPM](https://github.com/jordansissel/fpm).
Linuxfabrik used FPM before and dropped it: it is not flexible enough for real packaging,
especially for Python virtual environments (control over the venv layout, interpreter paths,
`%pyproject` macro integration and precise dependency generation). Native recipes also let us
adopt an upstream or distribution recipe (a `.spec`, a `debian/` directory, a `PKGBUILD`) almost
as-is and base each package on the official packaging (see below), instead of reconstructing its
logic through FPM flags.


## The manifest (`package.conf`)

```bash
PKG_VERSION='4.5.4'                 # upstream release tag we package (without leading v)
PKG_GITHUB_USER='nicolargo'
PKG_GITHUB_REPO='glances'
PKG_SOURCE_TARBALL="glances-${PKG_VERSION}.tar.gz"
PKG_SOURCE_URL="https://github.com/${PKG_GITHUB_USER}/${PKG_GITHUB_REPO}/archive/v${PKG_VERSION}/${PKG_SOURCE_TARBALL}"
PKG_RPM_SPEC='rpm/glances.spec'
PKG_RPM_DISTROS='rocky-v10 fedora-v44'   # EL and Fedora targets
PKG_DEB_DEBIAN_DIR='deb/debian'
PKG_DEB_DISTROS='debian-v13 ubuntu-v2404'
PKG_PKGBUILD='arch/PKGBUILD'
PKG_PACMAN_DISTROS='arch'
PKG_REPO_SUBDIR='glances'           # sub-directory under repo.linuxfabrik.ch
```

The spec uses `%{pkg_version}` / `%{pkg_release}`, injected by `create-rpm.sh`,
so the version lives only in the manifest.


## Distro-native builds

The default build model is **distro-native**: recipes use each format's standard toolchain
(`pyproject-rpm-macros` / `pybuild` / a plain `PKGBUILD`), and the runtime dependencies (and,
for GUI apps, PySide6/Qt) are pulled from the target distribution. This keeps packages small
(noarch / `any` where possible) and lets the distribution own the interpreter and the dependency
stack.

We build one package file per distro and version, never a single universal artifact: RPMs carry
the distribution's `%{?dist}` tag (`...-1.el10.noarch.rpm`, `...-1.fc44.noarch.rpm`), DEBs are
built per suite and pacman packages per Arch build. Each distro+version is published into its own
repository tree, because dependency names and versions differ per release.

A product can therefore only target distributions that ship a recent enough interpreter and
dependency versions. Verify this per product, in a container, before declaring a target. Two
recurring pitfalls:

- **Interpreter version.** A product's `requires-python` has to be met by a distro-provided
  interpreter. Pin it as low as the code truly needs, not aspirationally. Distros lag.
- **Dependency versions.** Many current distros still ship SQLAlchemy 1.4, not 2.0, and do not
  package niche libraries at all. Loosen the product's pins to floors (`>=`) so distro versions
  satisfy them, and drop targets that cannot provide a required major version.

Distributions that are too old for distro-native are simply not targeted. Covering them would
require a heavier build mode that bundles the interpreter and dependencies; out of scope until a
product actually needs it.


## Base third-party recipes on the official packaging

For third-party software, do not write a recipe from scratch. Start from the distribution's own
reference packaging and adapt it to the conventions here:

- RPM: the Fedora/EPEL spec.
- DEB: the Debian package's `debian/` directory.
- pacman: the official Arch `PKGBUILD`.

This gets the per-distro details right, and they differ more than they look: dependency names,
the split between hard dependencies and optional ones, the license identifier and the build
steps. For example, glances' web-UI dependencies are hard requirements in the Fedora spec but
`optdepends` on Arch, and `uvicorn` is not even in the official Arch repositories. Keep only the
Linuxfabrik-specific deltas on top of the reference: the shared `files/`, the version injected
from `package.conf`, and the locally provided source tarball.


## Split packages for GUI applications

A GUI application ships as two packages from one source, so that a CLI-only install never pulls
the heavy GUI stack. The base package owns the CLI/library code and its dependencies; a separate
`-gui` package owns only the GUI code and depends on the distro GUI toolkit (`python3-pyside6` on
EL/Debian/Ubuntu, `pyside6` on Arch). Because the toolkit dependency lives only in the `-gui`
package, installing the base alone never pulls it. FirewallFabrik is the first such case
(issue #114): `linuxfabrik-firewallfabrik` and `linuxfabrik-firewallfabrik-gui`.


## Adding a package

1. Create `packages/<name>/` with the manifest and the recipes you need (`rpm/`, `deb/`, `arch/`).
2. Pick the smallest set of `PKG_RPM_DISTROS` / `PKG_DEB_DISTROS` / `PKG_PACMAN_DISTROS` that
   the package actually needs. Not every package targets every distro or format.
3. Build locally and verify the package installs and runs:

   ```bash
   PKG_NAME=<name> PKG_TARGET_DISTROS='rocky-v10' PKG_PACKAGE_ITERATION=1 \
   PKG_ARCH=x86_64 PKG_DIR_REPO="$(pwd)" PKG_DIR_PACKAGED="$(pwd)/packaged" \
   bash build/matrix-package.sh
   ```

4. Open a pull request.


## Build and publish pipeline

- **Build**: the `Linuxfabrik: Build Linux (x86_64)` workflow
  (`.github/workflows/lf-build-linux-x86_64.yml`) builds a package across its
  configured distros, one matrix job per distro, and uploads the results as
  artifacts. It can be triggered manually (`workflow_dispatch`) or by another
  workflow (`workflow_call`).
- **Version detection**: a scheduled workflow compares each `package.conf`
  `PKG_VERSION` against the latest upstream release and proposes a bump when the
  upstream is ahead. Merging the bump triggers a build.
- **Publish**: `build/publish.sh` hands the built packages to the repo server,
  which serves them under `repo.linuxfabrik.ch/<PKG_REPO_SUBDIR>/`.
- **Release trigger (first-party)**: a Linuxfabrik product's own release workflow
  fires a `repository_dispatch` to this repository with the package name and
  version, which runs the matrix build and publish. The scheduled version-detection
  workflow acts as a delayed safety net.

`build/publish.sh` is currently a stub. Repo-side publishing to `repo.linuxfabrik.ch`
still has to be built: upload to the repo server, `createrepo_c` +
GPG-signed repodata for the EL/Fedora trees, `reprepro`/`aptly` + signed `Release` for
the Debian/Ubuntu suites, `repo-add` + `pacman-key` signing for the Arch tree, and
shipping the client repo definitions. Package signing keys still need provisioning.


## Code style

The [Linuxfabrik Standards](#linuxfabrik-standards) above apply (long options,
Conventional Commits, English, alphabetical sorting). On top of that:

- Shell scripts start with `set -e -o pipefail -u`.
- Keep the per-package recipes minimal; put anything reusable into `build/`.
