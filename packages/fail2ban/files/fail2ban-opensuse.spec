# SLES and openSUSE Leap part of rpm/fail2ban.spec, which includes it on
# SUSE. Ported from the openSUSE Factory fail2ban spec (1.1.1-0). It lives in
# files/ because rpmbuild needs it in SOURCES when it parses the spec.
# Linuxfabrik deltas:
# - version and release injected from package.conf
# - the tarball signature is checked with gpgv in %%prep; OBS does this on its
#   own with fail2ban.keyring, rpmbuild does not
# - sources renamed fail2ban-opensuse.{logrotate,sysconfig,tmpfiles}, since
#   create-deb.sh copies files/ into debian/, where fail2ban.logrotate is
#   Debian's
# - no monitoring-plugins-fail2ban subpackage: nagios-rpm-macros is not in the
#   SLES repositories
# - fail2ban-tests subpackage with fail2ban-testcases, as on Fedora, for the
#   smoke test, which runs the filter tests against the installed config
# - fail2ban-python is a link to the interpreter, as on Fedora, not a copy of
#   it: fail2ban-testcases replaces a copy with a link on every start, which
#   fails for any user but root
# - no debugsource package, there is no compiled code
# - BuildRequires python3-NAME instead of %%{python_module NAME}, the same
#   with `pythons python3`: rpmspec resolves them before python-rpm-macros,
#   which defines the macro, is installed (SLES 15)
# Everything else follows openSUSE, so a later openSUSE spec can be diffed
# against this one and merged. The package stays a single `fail2ban`, as on
# openSUSE Leap, so it updates hosts that installed Leap's package.

%define pythons python3

# Linuxfabrik: no compiled code to debug
%global debug_package %{nil}

%{!?tmpfiles_create:%global tmpfiles_create systemd-tmpfiles --create}
#Compat macro for new _fillupdir macro introduced in Nov 2017
%if ! %{defined _fillupdir}
  %define _fillupdir %{_localstatedir}/adm/fillup-templates
%endif
Name:           fail2ban
Version:        %{pkg_version}
Release:        %{pkg_release}%{?dist}
Summary:        Bans IP addresses that make too many authentication failures
License:        GPL-2.0-or-later
Group:          Productivity/Networking/Security
URL:            https://www.fail2ban.org/
Source0:        https://github.com/fail2ban/fail2ban/archive/%{version}.tar.gz#/%{name}-%{version}.tar.gz
Source1:        https://github.com/fail2ban/fail2ban/releases/download/%{version}/%{version}.tar.gz.asc
Source2:        %{name}-opensuse.sysconfig
Source3:        %{name}-opensuse.logrotate
Source5:        %{name}-opensuse.tmpfiles
# Path definitions have been submitted to upstream
Source8:        paths-opensuse.conf
Source200:      gpgkey-8738559E26F671DF9E2C6D9E683BF1BEBD0A882C.asc
# PATCH-FIX-OPENSUSE fail2ban-opensuse-locations.patch bnc#878028 jweberhofer@weberhofer.at -- update default locations for logfiles
Patch100:       %{name}-opensuse-locations.patch
# PATCH-FIX-OPENSUSE fail2ban-0.10.4-env-script-interpreter.patch jweberhofer@weberhofer.at -- use exact path to define interpretor
Patch201:       %{name}-0.10.4-env-script-interpreter.patch
# PATCH-FEATURE-OPENSUSE fail2ban_service.patch chris@computersalat.de -- Add [Service] EnvironmentFile
Patch300:       %{name}_service.patch
# PATCH-FEATURE-OPENSUSE harden_fail2ban.service.patch jsegitz@suse.com -- Added hardening to systemd service(s) bsc#1181400
Patch301:       harden_fail2ban.service.patch
# PATCH-FIX-OPENSUSE setup-py-install-dir.patch ncutler@suse.com -- fix unit file population broken by switch to pyproject_wheel macro
Patch303:       setup-py-install-dir.patch
BuildRequires:  python3-base >= 3.5
BuildRequires:  python3-pip
BuildRequires:  python3-pyinotify >= 0.8.3
BuildRequires:  python3-setuptools
BuildRequires:  python3-systemd
BuildRequires:  python3-tools
BuildRequires:  python3-wheel
BuildRequires:  fdupes
# Linuxfabrik: for the signature check in %%prep
BuildRequires:  gpg2
BuildRequires:  logrotate
BuildRequires:  python-rpm-macros
# timezone package is required to run the tests
BuildRequires:  timezone
Requires:       cron
Requires:       ed
Requires:       nftables
Requires:       logrotate
Requires:       python3 >= 3.5
Requires:       python3-setuptools
Requires:       whois
BuildRequires:  pkgconfig(systemd)
Requires:       python3-systemd
Requires:       systemd > 204
%{?systemd_requires}
Requires:       python3-pyinotify >= 0.8.3
%if 0%{?suse_version} < 1600
Provides:       SuSEfirewall2-%{name} = %{version}
Obsoletes:      SuSEfirewall2-%{name} < %{version}
%endif

%description
Fail2ban scans log files like %{_localstatedir}/log/messages and bans IP
addresses that makes too many password failures. It updates firewall rules to
reject the IP address, can send e-mails, or set host.deny entries.  These rules
can be defined by the user. Fail2Ban can read multiple log files such as sshd
or Apache web server ones.

# Linuxfabrik: the test cases, which openSUSE leaves out of the package
%package tests
Summary:        Fail2Ban testcases
Requires:       %{name} = %{version}-%{release}

%description tests
This package contains Fail2Ban's testscases and scripts.

%prep
# Linuxfabrik: what %%{gpgverify} does on Fedora and EL
keyring="$(mktemp --directory)/keyring.gpg"
gpg2 --dearmor --output "$keyring" %{SOURCE200}
gpgv --keyring "$keyring" %{SOURCE1} %{SOURCE0}
%autosetup -p1
install -m644 %{SOURCE8} config/paths-opensuse.conf

# Use openSUSE paths
sed -i -e 's/^before = paths-.*/before = paths-opensuse.conf/' config/jail.conf

rm 	config/paths-arch.conf \
	config/paths-debian.conf \
	config/paths-fedora.conf \
	config/paths-freebsd.conf \
	config/paths-osx.conf

# correct doc-path
sed -i -e 's|%{_datadir}/doc/%{name}|%{_docdir}/%{name}|' setup.py

%build
export CFLAGS="%{optflags}"
export SERVICE_BINDIR="%{_bindir}"
%pyproject_wheel
gzip man/*.{1,5}

%install
%pyproject_install
%python_expand %fdupes %{buildroot}%{python3_sitelib}
# Linuxfabrik: a link, see the header
ln -fs %{__python3} %{buildroot}%{_bindir}/fail2ban-python

install -d -m 755 %{buildroot}%{_mandir}/man{1,5}
install -m 644 man/fail2ban-*.1.gz %{buildroot}%{_mandir}/man1
install -m 644 man/jail.conf.5.gz %{buildroot}%{_mandir}/man5

install -d -m 755 %{buildroot}%{_initddir}
install -d -m 755 %{buildroot}%{_sbindir}

# use /run directory
install -d -m 755 %{buildroot}/run
touch %{buildroot}/run/%{name}

# systemd
if [ ! -f build/fail2ban.service ]; then
  sed -e "s|@BINDIR@|%{_bindir}|g" files/fail2ban.service.in > build/fail2ban.service
fi
install -D -m 644 build/fail2ban.service "%{buildroot}/%{_unitdir}/%{name}.service"
install -D -m 644 %{SOURCE5} %{buildroot}%{_tmpfilesdir}/%{name}.conf
ln -sf %{_sbindir}/service %{buildroot}%{_sbindir}/rc%{name}

install -d -m 755 %{buildroot}%{_sysconfdir}
mv %{buildroot}%{python3_sitelib}%{_sysconfdir}/%{name} %{buildroot}%{_sysconfdir}
rm -rv %{buildroot}%{_sysconfdir}/%{name}/action.d/__pycache__/
install -d -m 755 %{buildroot}%{_sysconfdir}/%{name}/fail2ban.d
install -d -m 755 %{buildroot}%{_sysconfdir}/%{name}/jail.d
install -d -m 755 %{buildroot}%{_docdir}
mv -v %{buildroot}%{python3_sitelib}%{_docdir}/%{name} %{buildroot}%{_docdir}
echo "# Do all your modifications to the jail's configuration in jail.local!" > %{buildroot}%{_sysconfdir}/%{name}/jail.local

install -d -m 0755 %{buildroot}%{_localstatedir}/lib/%{name}/

install -D -m 644 %{SOURCE2} %{buildroot}%{_fillupdir}/sysconfig.%{name}

install -D -m 644 %{SOURCE3}  %{buildroot}%{_sysconfdir}/logrotate.d/%{name}

%if 0%{?suse_version} < 1600
perl -i -lpe 's{(After|PartOf)=(.*)}{$1=$2 SuSEfirewall2.service}' \
	"%{buildroot}/%{_unitdir}/%{name}.service"
%endif

%check
# tests require python-pyinotify to be installed, so don't run them on older versions
%if 0%{?suse_version} >= 1500
# Need a UTF-8 locale to work
export LANG=en_US.UTF-8
./fail2ban-testcases-all --no-network || true
%endif

%pre
%service_add_pre %{name}.service

%post
%fillup_only
%tmpfiles_create %{_tmpfilesdir}/%{name}.conf
%service_add_post %{name}.service

%preun
%service_del_preun %{name}.service

%postun
%service_del_postun %{name}.service

%files
%dir %{_sysconfdir}/%{name}
%dir %{_sysconfdir}/%{name}/action.d
%dir %{_sysconfdir}/%{name}/%{name}.d
%dir %{_sysconfdir}/%{name}/filter.d
%dir %{_sysconfdir}/%{name}/jail.d
#
%config %{_sysconfdir}/%{name}/action.d/*
%config %{_sysconfdir}/%{name}/filter.d/*
#
%config(noreplace) %{_sysconfdir}/%{name}/%{name}.conf
%config %{_sysconfdir}/%{name}/jail.conf
%config %{_sysconfdir}/%{name}/paths-common.conf
%config %{_sysconfdir}/%{name}/paths-opensuse.conf
#
%config(noreplace) %{_sysconfdir}/%{name}/jail.local
#
%config %{_sysconfdir}/logrotate.d/%{name}
%dir %{_localstatedir}/lib/%{name}/
# use /run directory
%ghost /run/%{name}
# systemd
%{_unitdir}/%{name}.service
%{_tmpfilesdir}/%{name}.conf
%{_sbindir}/rc%{name}
%{_bindir}/%{name}-server
%{_bindir}/%{name}-client
%{_bindir}/%{name}-python
%{_bindir}/%{name}-regex
%{python3_sitelib}/%{name}
%exclude %{python3_sitelib}/%{name}/tests
%{python3_sitelib}/%{name}-*
%{_fillupdir}/sysconfig.%{name}
%{_mandir}/man1/*
%exclude %{_mandir}/man1/%{name}-testcases.1*
%{_mandir}/man5/*
%license COPYING
%doc README.md TODO ChangeLog doc/*.txt DEVELOP FILTERS

%pycache_only %exclude %{python_sitelib}/%{name}/__pycache__/*.pyc
%pycache_only %exclude %{python_sitelib}/%{name}/client/__pycache__/*.pyc
%pycache_only %exclude %{python_sitelib}/%{name}/compat/__pycache__/*.pyc
%pycache_only %exclude %{python_sitelib}/%{name}/server/__pycache__/*.pyc

# Linuxfabrik: the test cases go into fail2ban-tests
%files tests
%{_bindir}/%{name}-testcases
%{_mandir}/man1/%{name}-testcases.1*
%{python3_sitelib}/%{name}/tests
