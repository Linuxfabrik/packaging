# Version and release are injected by build/create-rpm.sh via --define. Provide
# defaults so the spec still parses (e.g. for `dnf builddep`) without them.
%{!?pkg_version: %global pkg_version 0}
%{!?pkg_release: %global pkg_release 0}

%global srcname firewallfabrik
%global appid ch.linuxfabrik.firewallfabrik

%global desc %{expand: \
FirewallFabrik manages iptables and nftables policies for many Linux firewalls
from one central policy database with reusable objects, and compiles them into
deployment-ready shell scripts. It reads Firewall Builder (fwbuilder) files and
continues its approach with a modern code base.}

Name:           linuxfabrik-firewallfabrik
Version:        %{pkg_version}
Release:        %{pkg_release}%{?dist}
Summary:        Firewall policy compiler for iptables and nftables

License:        GPL-2.0-or-later
URL:            https://github.com/Linuxfabrik/firewallfabrik
Source0:        https://github.com/Linuxfabrik/firewallfabrik/archive/v%{version}/%{srcname}-%{version}.tar.gz

BuildArch:      noarch

BuildRequires:  desktop-file-utils
BuildRequires:  python3-devel
BuildRequires:  pyproject-rpm-macros
# setup.py compiles the Qt resources with pyside6-rcc during the build.
BuildRequires:  pyside6-tools

%description
%{desc}

This package contains the core and the command line compilers fwf-ipt and
fwf-nft. The GUI is in %{name}-gui.

%package gui
Summary:        Qt GUI of FirewallFabrik
Requires:       %{name} = %{version}-%{release}
Requires:       python3-pyside6 >= 6.8
Requires:       hicolor-icon-theme

%description gui
%{desc}

This package contains the Qt GUI, fwf.

%prep
%autosetup -n %{srcname}-%{version}

# EL 10 ships setuptools 69, which predates PEP 639: it rejects the
# `license-files` key and does not meet `setuptools >= 77.0.3`. The license
# files are installed through %%license below instead.
sed -i '/^license-files = /d; s/"setuptools >= 77.0.3"/"setuptools"/' pyproject.toml

%generate_buildrequires
%pyproject_buildrequires

%build
%pyproject_wheel

%install
%pyproject_install
%pyproject_save_files %{srcname}

# Split the file list: the gui subpackage owns firewallfabrik/gui, the main
# package everything else.
grep '/%{srcname}/gui' %{pyproject_files} > gui.files
grep -v '/%{srcname}/gui' %{pyproject_files} > core.files

# Not below %%{_docdir}: minimal images and many hosts skip docs on install
# (tsflags=nodocs).
install -D -p -m 0644 examples/vdc.fwf %{buildroot}%{_datadir}/%{name}/examples/vdc.fwf
install -D -p -m 0644 examples/README.md %{buildroot}%{_datadir}/%{name}/examples/README.md

install -D -p -m 0644 assets/%{appid}.desktop %{buildroot}%{_datadir}/applications/%{appid}.desktop
install -D -p -m 0644 assets/%{appid}.xml %{buildroot}%{_datadir}/mime/packages/%{appid}.xml
install -D -p -m 0644 src/%{srcname}/gui/ui/Icons/firewallfabrik.svg \
    %{buildroot}%{_datadir}/icons/hicolor/scalable/apps/%{appid}.svg
for size in 16 24 32 48; do
    install -D -p -m 0644 src/%{srcname}/gui/ui/Icons/firewallfabrik_${size}.png \
        %{buildroot}%{_datadir}/icons/hicolor/${size}x${size}/apps/%{appid}.png
done

%check
desktop-file-validate %{buildroot}%{_datadir}/applications/%{appid}.desktop
# Only the core here; the smoke test in package.conf loads the GUI after
# installing both packages.
%pyproject_check_import -e '%{srcname}.gui*'

%files -f core.files
%license LICENSE COPYRIGHT
%doc README.md
%{_datadir}/%{name}/
%{_bindir}/fwf-ipt
%{_bindir}/fwf-nft
%{_bindir}/fwf-upgrade

%files gui -f gui.files
%{_bindir}/fwf
%{_datadir}/applications/%{appid}.desktop
%{_datadir}/icons/hicolor/*/apps/%{appid}.*
%{_datadir}/mime/packages/%{appid}.xml

%changelog
* Sun Oct 25 2026 Linuxfabrik GmbH <info@linuxfabrik.ch> - 3.5.0-1
- Initial package, split into core and gui.
