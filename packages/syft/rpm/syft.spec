# Version and release are injected by build/create-rpm.sh via --define. Provide
# defaults so the spec still parses (e.g. for `dnf builddep`) without them.
%{!?pkg_version: %global pkg_version 0}
%{!?pkg_release: %global pkg_release 0}

# syft is a static Go binary, stripped at link time as upstream does it (-s -w),
# so there is no debug information to extract.
%global debug_package %{nil}

Name:           syft
Version:        %{pkg_version}
Release:        %{pkg_release}%{?dist}
Summary:        Generate a Software Bill of Materials from filesystems and container images

# anchore/syft is Apache-2.0, the rest comes from the linked Go modules; the
# OR expression is github.com/spdx/tools-golang. Determined with syft itself on
# the linked modules, checked by hand where it found more than one license.
License:        0BSD AND Apache-2.0 AND BSD-2-Clause AND BSD-2-Clause-Views AND BSD-3-Clause AND CC0-1.0 AND ISC AND MIT AND MPL-2.0 AND Unicode-DFS-2016 AND Unlicense AND (Apache-2.0 OR GPL-2.0-or-later)
URL:            https://github.com/anchore/syft
Source0:        https://github.com/anchore/syft/archive/v%{version}/%{name}-%{version}.tar.gz
Source1:        build-syft.sh

# No BuildRequires: build-syft.sh fetches Go from go.dev with curl, which every
# build container has, and Go downloads the modules itself.

%if 0%{?suse_version}
# openSUSE Leap ships syft with the completions in subpackages that require
# their exact syft version; this package carries the completions itself.
Obsoletes:      syft-bash-completion < %{version}-%{release}
Obsoletes:      syft-fish-completion < %{version}-%{release}
Obsoletes:      syft-zsh-completion < %{version}-%{release}
Provides:       syft-bash-completion = %{version}-%{release}
Provides:       syft-fish-completion = %{version}-%{release}
Provides:       syft-zsh-completion = %{version}-%{release}
%endif

%description
Syft generates a Software Bill of Materials (SBOM) from filesystems and
container images, in CycloneDX, SPDX and its own JSON format. It catalogs the
packages of the operating system (rpm, dpkg, apk) and of the language
ecosystems such as Python, Java, JavaScript, Ruby and Go.

This package turns off the check for new syft releases at anchore.io by
default (turn it on with SYFT_CHECK_FOR_APP_UPDATE=true); updates come through
the package manager.

%prep
%autosetup -n syft-%{version}

%build
bash %{SOURCE1} %{version} %{SOURCE0}

%install
install -D -p -m 0755 bin/syft %{buildroot}%{_bindir}/syft
install -D -p -m 0644 completion.bash %{buildroot}%{_datadir}/bash-completion/completions/syft
install -D -p -m 0644 completion.fish %{buildroot}%{_datadir}/fish/vendor_completions.d/syft.fish
install -D -p -m 0644 completion.zsh %{buildroot}%{_datadir}/zsh/site-functions/_syft

%files
%license LICENSE module-licenses
%doc README.md
%{_bindir}/syft
%{_datadir}/bash-completion/completions/syft
%{_datadir}/fish/vendor_completions.d/syft.fish
%{_datadir}/zsh/site-functions/_syft

%changelog
