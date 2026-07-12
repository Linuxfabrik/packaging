# Version and release are injected by build/create-rpm.sh via --define. Provide
# defaults so the spec still parses (e.g. for `dnf builddep`) without them.
%{!?pkg_version: %global pkg_version 0}
%{!?pkg_release: %global pkg_release 0}

%global desc %{expand: \
Glances is a cross-platform monitoring tool which aims to present a large
amount of monitoring information through a curses or Web based interface.
The information dynamically adapts depending on the size of the user interface.

It can also work in client/server mode. Remote monitoring could be done via
terminal, Web interface or API (XML-RPC and RESTful). Stats can also be
exported to files or external time/value databases.

Glances is written in Python and uses libraries to grab information from your
system. It is based on an open architecture where developers can add new
plugins or exports modules.}

Name:           glances
Version:        %{pkg_version}
Release:        %{pkg_release}%{?dist}
Summary:        A cross-platform system monitoring tool

License:        LGPL-3.0-only AND MIT
URL:            https://nicolargo.github.io/glances/
Source0:        https://github.com/nicolargo/glances/archive/v%{version}/%{name}-%{version}.tar.gz
Source1:        %{name}.service

BuildArch:      noarch

BuildRequires:  python3-devel
BuildRequires:  pyproject-rpm-macros
BuildRequires:  systemd-rpm-macros

# The web interface (glances -w) imports these at runtime; they are not part of
# the project's core metadata, so the automatic dependency generator misses them.
Requires:       python3-fastapi
Requires:       python3-jinja2
Requires:       python3-uvicorn

%description
%{desc}

%prep
%autosetup -p1 -n %{name}-%{version}

# pyinstrument is declared in pyproject.toml but never imported by glances, and
# it is not packaged for EL10. Drop it so the build does not pull an unmet dep.
sed -i '/pyinstrument/d' pyproject.toml

# EL10 ships setuptools 69, which predates the PEP 639 SPDX license string.
# Rewrite `license = "..."` into the older table form it accepts.
sed -i 's/^license = "\(.*\)"$/license = {text = "\1"}/' pyproject.toml

# Disable the "a new version is available" check. It needs network access and
# suggests `pip install --upgrade`, which is wrong for an RPM-managed install.
sed -i 's/^check_update=true/check_update=false/' conf/glances.conf

%generate_buildrequires
%pyproject_buildrequires

%build
%pyproject_wheel

%install
%pyproject_install
%pyproject_save_files glances

install -D -p -m 0644 %{SOURCE1} %{buildroot}%{_unitdir}/%{name}.service
install -D -p -m 0644 conf/glances.conf %{buildroot}%{_sysconfdir}/glances/glances.conf

%post
%systemd_post %{name}.service

%preun
%systemd_preun %{name}.service

%postun
%systemd_postun_with_restart %{name}.service

%files -f %{pyproject_files}
%doc AUTHORS README.rst
%license COPYING
# Upstream installs a copy of the docs and the bundled config into the
# datadir doc directory; ship our own %%doc instead and keep the real config
# under /etc/glances.
%exclude %{_datadir}/doc/glances
%config(noreplace) %{_sysconfdir}/glances/glances.conf
%{_bindir}/glances
%{_mandir}/man1/glances.1*
%{_unitdir}/%{name}.service

%changelog
* Mon Jun 15 2026 Linuxfabrik GmbH <info@linuxfabrik.ch> - 4.5.4-1
- Initial Linuxfabrik build for EL10, ported from the Fedora/EPEL glances spec.
