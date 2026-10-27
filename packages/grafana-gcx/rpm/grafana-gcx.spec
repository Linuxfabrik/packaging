# Version and release are injected by build/create-rpm.sh via --define. Provide
# defaults so the spec still parses (e.g. for `dnf builddep`) without them.
%{!?pkg_version: %global pkg_version 0}
%{!?pkg_release: %global pkg_release 0}

# gcx is a static Go binary, stripped at link time as upstream does it (-s -w),
# so there is no debug information to extract.
%global debug_package %{nil}

Name:           grafana-gcx
Version:        %{pkg_version}
Release:        %{pkg_release}%{?dist}
Summary:        Command-line tool for Grafana and Grafana Cloud

# grafana/gcx is Apache-2.0, the rest comes from the linked Go modules;
# AGPL-3.0-only is github.com/grafana/grafana/pkg/apimachinery.
License:        Apache-2.0 AND AGPL-3.0-only AND BSD-2-Clause AND BSD-3-Clause AND ISC AND MIT
URL:            https://github.com/grafana/gcx
Source0:        https://github.com/grafana/gcx/archive/v%{version}/%{name}-%{version}.tar.gz
Source1:        build-gcx.sh

# No BuildRequires: build-gcx.sh fetches Go from go.dev with curl, which every
# build container has, and Go downloads the modules itself.

%description
gcx manages Grafana and Grafana Cloud resources from the command line:
dashboards, datasources, alerting, and the Cloud product APIs such as SLO, IRM,
Synthetic Monitoring, Fleet and k6. It is designed to be driven by AI agents as
well as by people.

This package turns off the anonymous usage telemetry by default (opt in with
GCX_TELEMETRY=enabled or `diagnostics.telemetry: enabled` in the gcx config)
and the check for new gcx releases on GitHub; updates come through the package
manager.

%prep
%autosetup -n gcx-%{version}

%build
bash %{SOURCE1} %{version} %{SOURCE0}

%install
install -D -p -m 0755 gcx %{buildroot}%{_bindir}/gcx
install -D -p -m 0644 completion.bash %{buildroot}%{_datadir}/bash-completion/completions/gcx
install -D -p -m 0644 completion.fish %{buildroot}%{_datadir}/fish/vendor_completions.d/gcx.fish
install -D -p -m 0644 completion.zsh %{buildroot}%{_datadir}/zsh/site-functions/_gcx

%files
%license LICENSE module-licenses
%doc CHANGELOG.md README.md
%{_bindir}/gcx
%{_datadir}/bash-completion/completions/gcx
%{_datadir}/fish/vendor_completions.d/gcx.fish
%{_datadir}/zsh/site-functions/_gcx

%changelog
