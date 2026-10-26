# Version and release are injected by build/create-rpm.sh via --define. Provide
# defaults so the spec still parses (e.g. for `dnf builddep`) without them.
%{!?pkg_version: %global pkg_version 0}
%{!?pkg_release: %global pkg_release 0}

Name:           acme.sh
Version:        %{pkg_version}
Release:        %{pkg_release}%{?dist}
Summary:        Pure Unix shell script implementing the ACME client protocol

# acme.sh is GPLv3 (README.md, LICENSE.md); deploy/cleverreach.sh,
# deploy/cpanel_uapi.sh, deploy/gcore_cdn.sh and deploy/ruckus.sh are public
# domain.
License:        GPL-3.0-only AND LicenseRef-Fedora-Public-Domain
URL:            https://github.com/acmesh-official/acme.sh
Source0:        https://github.com/acmesh-official/acme.sh/archive/%{version}/%{name}-%{version}.tar.gz
Source1:        acme.sh-wrapper

BuildArch:      noarch

BuildRequires:  help2man

Requires:       (curl or wget)
Requires:       openssl
# for the standalone and TLS-ALPN modes
Recommends:     socat

%description
acme.sh issues, renews and deploys certificates from Let's Encrypt, ZeroSSL and
other ACME certificate authorities. It is a POSIX shell script with hooks for
many DNS providers (dnsapi), deployment targets (deploy) and notification
services (notify).

This package turns off the self-upgrade of acme.sh (ACME_PACKAGED); updates
come through the package manager.

%prep
%autosetup -n %{name}-%{version}

%build
# the man page from --help, as the Debian package does it. HOME: acme.sh
# initialises its default config home below it on every call.
HOME="$(mktemp --directory)" ACME_PACKAGED=1 help2man \
    --name='Pure Unix shell script implementing the ACME client protocol' \
    --no-info \
    --version-string='%{version}' \
    ./acme.sh > acme.sh.1

%install
install -D -p -m 0755 acme.sh %{buildroot}%{_datadir}/acme.sh/acme.sh
cp -p -r deploy dnsapi notify %{buildroot}%{_datadir}/acme.sh/
rm -f %{buildroot}%{_datadir}/acme.sh/*/README.md
# executable like in the Debian package, they carry a shebang
find %{buildroot}%{_datadir}/acme.sh -name '*.sh' -exec chmod 0755 '{}' +
install -D -p -m 0755 %{SOURCE1} %{buildroot}%{_bindir}/acme.sh
install -D -p -m 0644 acme.sh.1 %{buildroot}%{_mandir}/man1/acme.sh.1
install -D -p -m 0644 acme.sh.completion %{buildroot}%{_datadir}/bash-completion/completions/acme.sh

%files
%license LICENSE.md
%doc README.md
%{_bindir}/acme.sh
%{_datadir}/acme.sh/
%{_datadir}/bash-completion/completions/acme.sh
%{_mandir}/man1/acme.sh.1*

%changelog
