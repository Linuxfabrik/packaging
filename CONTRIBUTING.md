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

The audience is a Linux system engineer with 30 seconds to decide whether an update is worth it. Write for that reader:

* **Lead with highlights.** Begin every release section with three to five sentences of running text, directly below the version heading and above the first `###` section. Cover what drives the update decision, including any manual step it requires. No bullet list, no issue links, no repetition of the individual entries. A release with only a handful of entries does not need one, since the entries themselves already fit on a screen.
* **State the change before its scope.** Up to five affected components keep the `component: what changed` form. From six on, put the statement first and close it with either a collective name (`all *-version checks`) or the components in parentheses, so the entry is understood from its first line. These broad entries come first in their subsection, ahead of the alphabetically sorted per-component entries.
* **One sentence per entry.** `Added`, `Changed` and `Fixed` say what an administrator notices. Root cause, reproduction steps and internal reasoning belong in the commit body and the issue.
* **Migration instructions only under `Breaking Changes`.** Wording such as "rename x to y" or "set z to restore the previous behaviour" anywhere else means the entry sits in the wrong section. Entries under `Breaking Changes` may run longer than one sentence.
* **Leave out contributor-only changes.** Lockfile and pin bumps, Dependabot and pre-commit configuration, GitHub Actions bumps and test infrastructure are covered by the git history and the pull request. Keep an entry only where an administrator sees the effect, for example when it changes the released artifact.

A release section starts like this:

```markdown
## [v6.1.0] - 2026-09-15

**Highlights:** Two long-standing sources of false alarms are gone, and container workloads are now covered. Cumulative counters are reported as rates instead of totals, so any dashboard built on them has to be re-imported.

### Added
```

The scope rule, on an entry affecting 43 components. Instead of:

```markdown
* about-me, borgbackup, deb-lastactivity, file-ownership, fs-xfs-stats, getent, ...: `--always-ok` to force an OK result
```

write:

```markdown
* `--always-ok` forces an OK result on 43 further components (about-me, borgbackup, deb-lastactivity, ...)
```


### Language

Code, comments, commit messages, and documentation must be written in English.


### CI Supply Chain

GitHub Actions in `.github/workflows/` are pinned by commit SHA, not by tag. Dependabot's `github-actions` ecosystem keeps these pins up to date.

Python packages installed via `pip` inside workflows follow a two-tier policy:

- `pre-commit` is installed from a hash-pinned requirements file at `.github/pre-commit/requirements.txt`, generated with `pip-compile --generate-hashes --strip-extras` from `.github/pre-commit/requirements.in`. Dependabot's `pip` ecosystem watches that directory and maintains both files.
- Every other tool a workflow installs with `pip` (`ansible-builder`, `build`, `mkdocs`, `pdoc`, `ruff`, `tox`, ...) follows the same model: a version pin in `.github/<name>/requirements.in`, a hash-pinned `requirements.txt` generated from it the same way, `pip install --require-hashes --requirement .github/<name>/requirements.txt` in the workflow, and a Dependabot `pip` entry for that directory. Dependabot does not read `run:` lines, so a version pinned there (`package==X.Y.Z`) is never updated, and a Scorecard `pipCommand not pinned by hash` finding on it is a real one.


### Coding Conventions

- Sort variables, parameters, lists, and similar items alphabetically where possible.
- Always use long parameters when using shell commands.
- Use RFC [5737](https://datatracker.ietf.org/doc/html/rfc5737), [3849](https://datatracker.ietf.org/doc/html/rfc3849), [7042](https://datatracker.ietf.org/doc/html/rfc7042#section-2.1.1), and [2606](https://datatracker.ietf.org/doc/html/rfc2606) in examples and documentation:
    - IPv4: `192.0.2.0/24`, `198.51.100.0/24`, `203.0.113.0/24`
    - IPv6: `2001:DB8::/32`
    - MAC: `00-00-5E-00-53-00` through `00-00-5E-00-53-FF` (unicast), `01-00-5E-90-10-00` through `01-00-5E-90-10-FF` (multicast)
    - Domains: `*.example`, `example.com`


---


This repository builds Linuxfabrik RPM and DEB packages from both Linuxfabrik's own
products and third-party upstream software, and publishes them on
[repo.linuxfabrik.ch](https://repo.linuxfabrik.ch). It is open to an arbitrary number
of packages.


## Concepts

A *package* is one piece of software we ship, living under `packages/<name>/`.
Each package brings:

- `package.conf`: the manifest, sourced by the build scripts. It declares the
  source, the version to package, the per-format target distributions and the
  smoke test.
- `rpm/<name>.spec`: the RPM recipe (EL, Fedora, SLES).
- `deb/debian/`: the DEB recipe (`control`, `rules`, `copyright`, `source/format`).
- `files/`: assets shared between the formats, e.g. the systemd unit.
- `src/`: the source itself, only for packages without an upstream, such as
  `linuxfabrik-release` (`PKG_SOURCE_DIR`).

A package only ships the recipes for the formats it targets. The build is
package-agnostic: `build/create-package.sh` reads the manifest, fetches the
source (or packs `src/`) and dispatches to `create-rpm.sh` or `create-deb.sh`
depending on the target distro. `matrix-package.sh` runs that across many
distros, each inside the matching container from `build/containerfiles/`, and
then installs every result into a fresh container of its distro to run the
smoke test (`build/smoke-test-package.sh`).


## Package formats

Each `package.conf` declares, per format, the recipe and the distro targets it applies to. A
package only targets the formats and distros it needs:

- **RPM** (`PKG_RPM_SPEC`, `PKG_RPM_DISTROS`): EL (`rocky-*`, `rhel-*`, `almalinux-*`,
  `centos-*`), `fedora-*` and `sles-*`. Built with `rpmbuild`; build dependencies are resolved
  with `dnf builddep` on EL/Fedora and with a zypper fallback on SLES.
- **DEB** (`PKG_DEB_DEBIAN_DIR`, `PKG_DEB_DISTROS`): `debian-*`, `ubuntu-*`. Built with `debuild`.

Targets are RHEL 8, 9 and 10 and compatibles (`rocky-v8`, `rocky-v9`, `rocky-v10`), Fedora
(`fedora-v44`), SLES 15 and 16 (`sles-v15`, `sles-v16`, also serving openSUSE Leap), Debian 11,
12 and 13 (`debian-v11`, `debian-v12`, `debian-v13`) and Ubuntu 22.04, 24.04 and 26.04
(`ubuntu-v2204`, `ubuntu-v2404`, `ubuntu-v2604`).

A release stays a target until six months after its vendor stops shipping updates free of
charge: Maintenance Support for RHEL, LTS for Debian, Standard Support for Ubuntu, General
Support for SLE, end of life for Fedora. Paid extensions (RHEL ELS, Debian ELTS, Ubuntu Pro /
ESM, SUSE LTSS) do not count. The six months give administrators one more maintenance window
after the vendor date. After that, the release is dropped from every `package.conf` and its
containerfile goes with it. A package may leave a release earlier, for example when the
distribution's dependencies are too old for it.

The dates, six months after the vendor date (sources:
[RHEL](https://endoflife.date/rhel), [Debian](https://endoflife.date/debian),
[Ubuntu](https://endoflife.date/ubuntu), [SLES](https://endoflife.date/sles),
[Fedora](https://endoflife.date/fedora)):

- 2027-02-28: Debian 11
- 2027-10-01: Ubuntu 22.04
- 2027-12-02: Fedora 44
- 2028-05-31: SLE 16
- 2028-12-31: Debian 12
- 2029-11-30: RHEL 8
- 2029-11-30: Ubuntu 24.04
- 2030-12-31: Debian 13
- 2031-10-31: Ubuntu 26.04
- 2032-01-31: SLE 15
- 2032-11-30: RHEL 9
- 2035-11-30: RHEL 10

A release whose vendor date has passed may need its apt or dnf sources moved to an archive;
`build/containerfiles/debian-v11` and `build/smoke-test-package.sh` show how for Debian 11.

On EL, a package may depend on EPEL and the CRB repository, as glances does. The build
containers and the smoke test enable both, and the README tells administrators to do the
same.

### Architectures

`PKG_ARCHES` in `package.conf` lists the architectures a package is built for, by default
`aarch64 x86_64`. Every package is built and smoke-tested on both, so a dependency that is
missing on aarch64 shows up before the release, noarch packages included. A noarch package
(`BuildArch: noarch`, `Architecture: all`) is published once: the release job keeps the first
of the identical file names, the repository server copies noarch RPMs into every arch
directory, and apt picks `Architecture: all` up on `amd64` and `arm64`. For any other file
name, two builds with the same name fail the release. A package that cannot be built for one
architecture sets `PKG_ARCHES='x86_64'`.

aarch64 builds run natively on GitHub's `ubuntu-24.04-arm` runners. Locally,
`matrix-package.sh` passes the architecture to podman (`--arch`), so on an x86_64 workstation
with qemu-user-static an aarch64 build runs emulated, slowly but with the same scripts.


## Why native recipes, not FPM

We build with each format's native tooling (`rpmbuild` / `debuild`) and hand-written recipes
rather than a cross-format generator such as [FPM](https://github.com/jordansissel/fpm).
Linuxfabrik used FPM before and dropped it: it is not flexible enough for real packaging,
especially for Python virtual environments (control over the venv layout, interpreter paths,
`%pyproject` macro integration and precise dependency generation). Native recipes also let us
adopt an upstream or distribution recipe (a `.spec` or a `debian/` directory) almost as-is and
base each package on the official packaging (see below), instead of reconstructing its logic
through FPM flags.


## The manifest (`package.conf`)

```bash
PKG_VERSION='4.5.8'                 # upstream version we package (tag without prefix)
PKG_UPSTREAM_TYPE='github'          # github | gitlab | none
PKG_UPSTREAM_PROJECT='nicolargo/glances'
PKG_SOURCE_TARBALL="glances-${PKG_VERSION}.tar.gz"
PKG_SOURCE_URL="https://github.com/${PKG_UPSTREAM_PROJECT}/archive/v${PKG_VERSION}/${PKG_SOURCE_TARBALL}"
PKG_RPM_SPEC='rpm/glances.spec'
PKG_RPM_DISTROS='rocky-v10 fedora-v44'   # EL and Fedora targets
PKG_DEB_DEBIAN_DIR='deb/debian'
PKG_DEB_DISTROS='debian-v13 ubuntu-v2404'
PKG_SMOKE_TEST='glances --version'  # run as nobody after installing into a fresh container
# PKG_ARCHES='x86_64'               # default 'aarch64 x86_64'
```

`build/check-upstream.sh` watches the upstream for new versions. Besides
`PKG_UPSTREAM_TYPE` and `PKG_UPSTREAM_PROJECT` it reads, all optional:

- `PKG_UPSTREAM_SOURCE`: `releases` (default) takes the release the upstream marks as
  latest; drafts and prereleases never count. `tags` takes the highest version among
  all tags and skips alpha, beta, dev, pre and rc tags. Use it for projects that tag
  without publishing releases.
- `PKG_UPSTREAM_TAG_PREFIX`: stripped from the tag to get the version, default `v`.
  duplicity, for example, tags `rel.3.2.2`.
- `PKG_UPSTREAM_URL`: the GitLab instance, default `https://gitlab.com`.

`PKG_UPSTREAM_TYPE='none'` is for packages without an upstream, such as
`linuxfabrik-release`; they are rebuilt by changing their package directory. Such a
package keeps its source in the repository and sets `PKG_SOURCE_DIR` (e.g. `src`)
instead of `PKG_SOURCE_URL`: `create-package.sh` packs that directory into
`PKG_SOURCE_TARBALL` with a top-level `<name>-<version>/` directory, the way an
upstream tarball looks, so the recipes need no special case.

The spec uses `%{pkg_version}` / `%{pkg_release}`, injected by `create-rpm.sh`,
so the version lives only in the manifest. The build iteration is not part of the
manifest: the release workflow counts it up per version (see below).

DEB versions carry the target distro after the iteration, as packages.sury.org does:
`4.5.8-1+debian13`, `4.5.8-1+ubuntu24.04`. Without it, the builds for different
suites share one file name, which a repository with one pool for all suites cannot
hold. A newer distro release also sorts higher, so a dist-upgrade picks up its build.


## Distro-native builds

The default build model is **distro-native**: recipes use each format's standard toolchain
(`pyproject-rpm-macros` / `pybuild`), and the runtime dependencies (and, for GUI apps, PySide6/Qt)
are pulled from the target distribution. This keeps packages small (noarch where possible) and
lets the distribution own the interpreter and the dependency stack.

We build one package file per distro and version, never a single universal artifact: RPMs carry
the distribution's `%{?dist}` tag (`...-1.el10.noarch.rpm`, `...-1.fc44.noarch.rpm`) and DEBs are
built per suite. SLES defines no `%{dist}`; `create-rpm.sh` sets `.sle15` / `.sle16` there, so
the builds for both releases do not share a file name. Each distro+version is published into
its own repository tree, because dependency names and versions differ per release.

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

This gets the per-distro details right, and they differ more than they look: dependency names,
the split between hard dependencies and optional ones, the license identifier and the build
steps. For example, glances' web-UI dependencies are hard requirements in the Fedora spec but
optional in another distribution's packaging. Keep only the
Linuxfabrik-specific deltas on top of the reference: the shared `files/`, the version injected
from `package.conf`, and the locally provided source tarball.


## Split packages for GUI applications

A GUI application ships as two packages from one source, so that a CLI-only install never pulls
the heavy GUI stack. The base package owns the CLI/library code and its dependencies; a separate
`-gui` package owns only the GUI code and depends on the distro GUI toolkit (`python3-pyside6` on
EL/Debian/Ubuntu). Because the toolkit dependency lives only in the `-gui`
package, installing the base alone never pulls it. FirewallFabrik is the first such case
(issue #114): `linuxfabrik-firewallfabrik` and `linuxfabrik-firewallfabrik-gui`.


## Adding a package

1. Create `packages/<name>/` with the manifest and the recipes you need (`rpm/`, `deb/`), plus
   `files/` for shared assets, or `src/` if the package has no upstream.
2. Pick the smallest set of `PKG_RPM_DISTROS` / `PKG_DEB_DISTROS` that the package actually
   needs. Not every package targets every distro or format.
3. Set `PKG_SMOKE_TEST` to a command that proves the installed package works, e.g.
   `<name> --version`.
4. Build locally. `matrix-package.sh` installs each result into a fresh container of
   its distro and runs the smoke test there:

   ```bash
   PKG_NAME=<name> PKG_TARGET_DISTROS='rocky-v10' PKG_PACKAGE_ITERATION=1 \
   PKG_ARCH=x86_64 PKG_DIR_REPO="$(pwd)" PKG_DIR_PACKAGED="$(pwd)/packaged" \
   bash build/matrix-package.sh
   ```

5. Open a pull request. Merging it publishes the package to the `testing` channel.

### Testing beyond the smoke test

The smoke test proves that a package installs and starts on a fresh container of its distro.
Changes that affect how hosts reach the repository need more: the repository configuration in
`linuxfabrik-release`, `build/publish.sh`, the repository layout, or a new target distro. Test
those end to end on fresh VMs of every affected distro, against a test repository server set up
like the real one (see [The repository server](#the-repository-server)) and serving
`repo.linuxfabrik.ch` with a test certificate:

- install `linuxfabrik-release` through its bootstrap link only, refresh the package index with
  signature checks on, and install a package from the repository
- check that a bad signature is refused: a key that does not match the repository, and a
  `repomd.xml.asc` that does not match its `repomd.xml`

Use VMs rather than containers here, so the test runs exactly what an administrator runs on an
installed host, from the bootstrap link to the first update.


## Build and publish pipeline

Every release of a packaged project ends up on repo.linuxfabrik.ch without a manual
step, first in the `testing` channel and seven days later in `release`. The workflows
of this pipeline carry a number in their display name that follows the order below
(`Linuxfabrik: 10 - Check upstream versions` to `Linuxfabrik: 50 - Promote releases`),
so the Actions list reads like the pipeline. Only the display names are numbered: the
file names stay, because `publish.sh` checks the attestations against the path of
`lf-release.yml`. The workflows shared with all Linuxfabrik repositories (auto-merge,
pre-commit, CodeQL, Scorecard, dependency review) keep their common names.

1. **Version detection**: `lf-check-upstream.yml` runs hourly and compares each
   `PKG_VERSION` with the latest upstream version. When the upstream is ahead,
   it opens a bump pull request. Upstreams on GitHub and GitLab are supported, by
   release or by tag (see `PKG_UPSTREAM_SOURCE`). An upstream that cannot be
   queried fails the run. Linuxfabrik's own projects do not have to wait for
   the next run: their release workflow sends a `repository_dispatch` of type
   `upstream-release` to this repository.
2. **Build and smoke test**: `lf-build-pr.yml` builds every package a pull request
   touches on all its target distros and architectures (`lf-build-linux.yml`), installs each
   result into a fresh container and runs `PKG_SMOKE_TEST`. A change below `build/`
   rebuilds every package. `Build result` is a required check.
3. **Merge**: bump pull requests are merged automatically once the required checks
   pass (`auto-merge.yml`), without review. The `testing` channel takes the place of
   the review.
4. **Release**: a push to `main` that changes `packages/<name>/` runs
   `lf-release.yml`. It builds the package again and creates the GitHub prerelease
   `<name>-<version>-<iteration>` with the unsigned packages, a `SHA256SUMS` that
   records the distro of each file, and a build provenance attestation. The
   iteration starts at 1 for a new version and counts up with every further change
   to the package directory, e.g. a recipe fix. A rebuild without a change:
   `gh workflow run lf-release.yml --field package=<name>`.
5. **Promotion**: `lf-promote.yml` turns every prerelease that is 7 days old into a
   full release. Intervene by hand with
   `gh workflow run lf-promote.yml --field release=<tag> --field action=promote`
   (release now) or `action=reject` (never release, remove from `testing`). A rejected
   prerelease keeps its tag, with "(rejected)" appended to its title; fix the package and
   merge again to build the next iteration.
6. **Publish**: `build/publish.sh` runs from a systemd timer on the repository
   server. It mirrors the GitHub releases into the repositories: prerelease to
   `testing`, release to `release`, rejected prerelease out of `testing` again.
   Before publishing, it verifies every file against its attestation
   (`gh attestation verify`), signs the RPMs and the repository metadata with the
   Linuxfabrik key and updates the repositories (`createrepo_c`, freight). RPM
   metadata is gzip-compressed, because EL 8 cannot read the zstd default of
   current `createrepo_c`. For `linuxfabrik-release` it also keeps the bootstrap
   links `linuxfabrik-release-latest-<distro>.<ext>` in the webroot pointing at the
   newest build in `release`. At the end of every run it renders the start page
   `index.html` from the published contents: setup command and packages per distro
   (release and testing), an overview of all packages, channels, signing key.
   Its stylesheet goes to `index.css` instead of an inline `<style>`, which the
   CSP of the proxy in front blocks; the directory listings keep
   `/assets/style.css`.

The signing key never leaves the repository server: CI only ever handles unsigned
packages, and the server pulls instead of GitHub pushing to it. The GitHub releases
double as the archive of every package ever built.

### Repository layout

One aggregated Linuxfabrik repository per distribution, the same layout the Pulp
server will serve later (GitLab `001/project-big-picture` #1252), so client
configuration does not change when it takes over:

- RPM: `<el|fedora|sle>/<os-version>/<arch>/linuxfabrik/<release|testing>/`. EL covers Rocky,
  Alma, RHEL and CentOS; `linuxfabrik-release` writes the EL major version at build time,
  because EL 8 has no `$releasever_major`, and uses `$basearch` for the arch. noarch packages go
  into every arch directory. Packages are signed, and so is `repodata/repomd.xml`, so clients
  can set `repo_gpgcheck=1`; `linuxfabrik-release` leaves it off, see the comment in its
  `linuxfabrik.repo`. `sle` (not `sles`) serves SLES, SLED and openSUSE Leap alike, as
  the monitoring-plugins repository does; the build containers keep the `sles-v*` names.
- DEB: `<debian|ubuntu>/linuxfabrik/` with `dists/<codename>-<release|testing>/main`,
  e.g. `deb [signed-by=/usr/share/keyrings/linuxfabrik.gpg] https://repo.linuxfabrik.ch/debian/linuxfabrik trixie-release main`.
  No architecture in the path, apt picks it from the `Release` file
  (`amd64 arm64`).

### The repository server

`build/publish.sh` is the only part that runs outside GitHub. Its header lists the details;
in short, the server needs:

- `createrepo_c`, `dpkg` (for `dpkg-deb`), freight, `gh`, `gpg`, `jq` and `rpm-sign`
- the Linuxfabrik signing key in the GnuPG keyring of the user running the script, its
  fingerprint in `PUBLISH_GPG_KEY` and the passphrase in the file named by
  `PUBLISH_GPG_PASSPHRASE_FILE`, readable by that user only
- a read-only GitHub token in `GH_TOKEN`, for the API and `gh attestation verify`
- a web server that serves `PUBLISH_WEBROOT` and follows symbolic links (bootstrap links,
  freight's `dists/`)
- `PUBLISH_FREIGHT_LIB` and `PUBLISH_WEBROOT` on one mount: freight hard-links its library into
  the webroot, and where that fails, it copies and later deletes the pool files of earlier
  releases. systemd's `ReadWritePaths=` makes every listed path its own bind mount, so list a
  common parent such as `/var`. `publish.sh` checks this at start and refuses to run otherwise.
- until `PUBLISH_LEGACY_MP_UNTIL` (2026-12-31), write access for that user to the former
  Monitoring Plugins tree (`PUBLISH_WEBROOT/monitoring-plugins/` and the freight libraries
  `PUBLISH_FREIGHT_LIB/monitoring-plugins-{debian,ubuntu}`), which the script publishes the
  `linuxfabrik-monitoring-plugins*` packages to as well
- a systemd timer that runs the script; it locks itself against overlapping runs

### linuxfabrik-release

`packages/linuxfabrik-release/` holds the repository configuration as templates in `src/`
(`linuxfabrik.repo`, `linuxfabrik.sources`) and the public signing key
(`RPM-GPG-KEY-linuxfabrik`). The recipes fill in the placeholders at build time: `@REPO_PATH@`
from the RPM macros of the build distro, `@OS@` and `@CODENAME@` from its `/etc/os-release`.
Any change below the package directory builds the next iteration and reaches every host that
has the package installed, so treat it like a change to all of them: the configuration files
are `%config(noreplace)` / conffiles, and a host keeps its local edits.

Replacing the signing key means shipping the new key in `linuxfabrik-release` first and
signing with it only after that release has reached the hosts; otherwise they refuse the
repository.

**Arch/pacman is intentionally out of scope.** Pulp ships `pulp_rpm`, `pulp_deb` and
`pulp_file` but no pacman plugin (verified against the Pulp source), so there is no Linuxfabrik
distribution channel for pacman packages; the packaging repo therefore does not build them.


## Code style

The [Linuxfabrik Standards](#linuxfabrik-standards) above apply (long options,
Conventional Commits, English, alphabetical sorting). On top of that:

- Shell scripts start with `set -e -o pipefail -u`.
- Keep the per-package recipes minimal; put anything reusable into `build/`.
