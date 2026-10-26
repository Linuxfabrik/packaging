# Version and release are injected by build/create-rpm.sh via --define. Provide
# defaults so the spec still parses (e.g. for `dnf builddep`) without them.
%{!?pkg_version: %global pkg_version 0}
%{!?pkg_release: %global pkg_release 0}

# exo is a static Go binary, stripped at link time as upstream does it (-s -w),
# so there is no debug information to extract.
%global debug_package %{nil}

Name:           exoscale-cli
Version:        %{pkg_version}
Release:        %{pkg_release}%{?dist}
Summary:        Command-line tool for the Exoscale cloud

# exoscale/cli is Apache-2.0, the rest comes from the vendored Go modules.
License:        Apache-2.0 AND BSD-2-Clause AND BSD-3-Clause AND ISC AND LGPL-3.0-only WITH LGPL-3.0-linking-exception AND MIT AND MPL-2.0
URL:            https://github.com/exoscale/cli
Source0:        https://github.com/exoscale/cli/archive/v%{version}/%{name}-%{version}.tar.gz
Source1:        build-exo.sh

# No BuildRequires: build-exo.sh fetches Go from go.dev with curl, which every
# build container has, and the Go modules are vendored.

%description
exo manages Exoscale resources from the command line: compute instances and
instance pools, SKS Kubernetes clusters, DBaaS, DNS, object storage, IAM and
more.

%prep
%autosetup -n cli-%{version}

%build
bash %{SOURCE1} %{version} %{SOURCE0}

%install
install -D -p -m 0755 exo %{buildroot}%{_bindir}/exo
install -d %{buildroot}%{_mandir}/man1
install -p -m 0644 manpage/*.1 %{buildroot}%{_mandir}/man1/
install -D -p -m 0644 bash_completion %{buildroot}%{_datadir}/bash-completion/completions/exo
install -D -p -m 0644 fish_completion %{buildroot}%{_datadir}/fish/vendor_completions.d/exo.fish
install -D -p -m 0644 zsh_completion %{buildroot}%{_datadir}/zsh/site-functions/_exo

%files
%license LICENSE vendor-licenses
%doc CHANGELOG.md README.md
%{_bindir}/exo
%{_datadir}/bash-completion/completions/exo
%{_datadir}/fish/vendor_completions.d/exo.fish
%{_datadir}/zsh/site-functions/_exo
%{_mandir}/man1/exo*.1*

%changelog
