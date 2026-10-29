# Version and release are injected by build/create-rpm.sh via --define. Provide
# defaults so the spec still parses (e.g. for `dnf builddep`) without them.
%{!?pkg_version: %global pkg_version 0}
%{!?pkg_release: %global pkg_release 0}

%global appdir %{_prefix}/lib/swisscom-schweiz-ag/cdr-client
%global confdir %{_sysconfdir}/swisscom-schweiz-ag/cdr-client
%global statedir %{_sharedstatedir}/swisscom-schweiz-ag/cdr-client

# The tarball is a prebuilt application with its own Java runtime. Leave the
# binaries as Swisscom built them: no debug package, no stripping, and no
# build-id links, which the identical launchers of both packages would clash on.
%global debug_package %{nil}
%global _build_id_links none
%global __brp_strip %{nil}
%global __brp_strip_comment_note %{nil}
%global __brp_strip_static_archive %{nil}
%global __strip /bin/true
# The launchers find the bundled runtime through the runpath
# ${ORIGIN}/../lib/runtime/lib, which check-rpaths rejects for the braces.
%global __brp_check_rpaths %{nil}

# The libraries of the bundled runtime are private: provide none of them, and
# require none of them or the libraries only the UI loads. The -gui package
# requires the latter explicitly.
%global __provides_exclude_from ^%{appdir}/
%global __requires_exclude ^lib(asound\\.so\\.2|awt|dbus-1\\.so\\.3|fontconfig\\.so\\.1|freetype|GL\\.so\\.1|java|jli|jvm|net|stdc\\+\\+\\.so\\.6|systemd\\.so\\.0|X11\\.so\\.6|Xext\\.so\\.6|Xi\\.so\\.6|Xrender\\.so\\.1|Xtst\\.so\\.6)

# the native libraries of the UI toolkit (Compose, tray icon, desktop theme),
# which go into the -gui package
%global guilibs libLinuxTray.so libnucleus_linux_theme.so libskiko-linux-x64.so

# The UI needs glibc 2.34, which EL 8 and SLES 15 do not have.
%if 0%{?rhel} >= 9 || 0%{?fedora} || 0%{?suse_version} >= 1600
%bcond_without gui
%else
%bcond_with gui
%endif

Name:           swisscom-schweiz-ag-cdr-client
Version:        %{pkg_version}
Release:        %{pkg_release}%{?dist}
Summary:        Client for the curaLINE Document Routing (CDR) service

# the client is Apache-2.0, the bundled Java runtime GPL-2.0 with the Classpath
# exception, the bundled Java libraries come under their own licenses
License:        Apache-2.0 AND GPL-2.0-only WITH Classpath-exception-2.0
URL:            https://github.com/swisscom/cdr-client
Source0:        https://cdr.health.swisscom.ch/share/downloads/cdr-client-%{version}-linux-amd64.tar.gz
Source1:        %{name}.service
Source2:        %{name}.sysusers

ExclusiveArch:  x86_64

BuildRequires:  systemd-rpm-macros
%if 0%{?suse_version}
Requires(pre):  shadow
%else
Requires(pre):  shadow-utils
%endif
# /usr/bin/env in the unit
Requires:       coreutils

%description
The curaLINE Client exchanges documents with the curaLINE Document Routing
(CDR) service of Swisscom for participants in the Swiss healthcare system. It
uploads the files of a source folder and puts the documents it downloads into
a target folder.

This package contains the service. The UI is in %{name}-gui.

%if %{with gui}
%package gui
Summary:        UI of the curaLINE Client
Requires:       %{name}%{?_isa} = %{version}-%{release}
Requires:       hicolor-icon-theme
Requires:       libasound.so.2()(64bit)
Requires:       libdbus-1.so.3()(64bit)
Requires:       libfontconfig.so.1()(64bit)
Requires:       libGL.so.1()(64bit)
Requires:       libstdc++.so.6()(64bit)
Requires:       libsystemd.so.0()(64bit)
Requires:       libX11.so.6()(64bit)
Requires:       libXext.so.6()(64bit)
Requires:       libXi.so.6()(64bit)
Requires:       libXrender.so.1()(64bit)
Requires:       libXtst.so.6()(64bit)

%description gui
The curaLINE Client exchanges documents with the curaLINE Document Routing
(CDR) service of Swisscom for participants in the Swiss healthcare system.

This package contains the desktop UI, cdr-client-ui, to configure and watch
the client.
%endif

%prep
%autosetup -n cdr-client-%{version}

# The default configuration downloads into java.io.tmpdir, which is private to
# the service (PrivateTmp=yes) and emptied on every restart, so the documents
# being downloaded would be lost. Use the state directory instead.
sed --in-place 's|^\(  local-folder:\).*|\1 %{statedir}|' lib/app/conf/application-customer.yaml

%build
# prebuilt

%install
install -d %{buildroot}%{appdir}
cp --archive bin lib %{buildroot}%{appdir}/
install -d %{buildroot}%{_bindir}
ln --symbolic %{appdir}/bin/cdr-client-service %{buildroot}%{_bindir}/cdr-client-service
install -d %{buildroot}%{confdir}
install -D -p -m 0644 %{SOURCE1} %{buildroot}%{_unitdir}/%{name}.service
install -D -p -m 0644 %{SOURCE2} %{buildroot}%{_sysusersdir}/%{name}.conf
# Conveyor's own unit; ours replaces it
rm --recursive %{buildroot}%{appdir}/lib/systemd

%if %{with gui}
ln --symbolic %{appdir}/bin/cdr-client-ui %{buildroot}%{_bindir}/cdr-client-ui
install -d %{buildroot}%{_datadir}
cp --archive share/applications share/icons share/metainfo %{buildroot}%{_datadir}/
%else
rm %{buildroot}%{appdir}/bin/cdr-client-ui %{buildroot}%{appdir}/lib/app/conf/logback-ui.xml
for lib in %{guilibs}; do
    rm %{buildroot}%{appdir}/lib/runtime/lib/$lib
done
%endif

%pre
# the account of sysusers.d/%{name}.conf, for the rpm versions that do not
# create it from there
getent group %{name} >/dev/null || groupadd --system %{name}
getent passwd %{name} >/dev/null || \
    useradd --system --gid %{name} --home-dir %{statedir} --no-create-home \
        --shell /usr/sbin/nologin --comment 'curaLINE Client' %{name}
exit 0

%post
# The configuration is not part of the package. It holds the client secret,
# the client rewrites it when it renews its credential, and it may belong to
# another account such as `hnet` (see the unit). Create it from the defaults
# if it is missing, and hand it to the service account if it belongs to root,
# since the client refuses to start with a file it does not own.
for file in application-customer.yaml logback-service.xml; do
    if [ ! -e %{confdir}/$file ]; then
        install -m 0640 %{appdir}/lib/app/conf/$file %{confdir}/$file
    fi
    if [ "$(stat --format='%%u' %{confdir}/$file)" = 0 ]; then
        chown %{name}:%{name} %{confdir}/$file
        chmod 0640 %{confdir}/$file
    fi
done
%systemd_post %{name}.service

%preun
%systemd_preun %{name}.service

%postun
%systemd_postun_with_restart %{name}.service

%files
%license lib/runtime/legal
%dir %{_prefix}/lib/swisscom-schweiz-ag
%dir %{appdir}
%dir %{appdir}/bin
%{appdir}/bin/cdr-client-service
%dir %{appdir}/lib
%dir %{appdir}/lib/app
%{appdir}/lib/app/*.jar
%{appdir}/lib/app/icon*
%dir %{appdir}/lib/app/conf
%{appdir}/lib/app/conf/application-customer.yaml
%{appdir}/lib/app/conf/logback-service.xml
%{appdir}/lib/runtime
%if %{with gui}
%exclude %{appdir}/lib/runtime/lib/libLinuxTray.so
%exclude %{appdir}/lib/runtime/lib/libnucleus_linux_theme.so
%exclude %{appdir}/lib/runtime/lib/libskiko-linux-x64.so
%endif
%{_bindir}/cdr-client-service
%dir %{_sysconfdir}/swisscom-schweiz-ag
%dir %{confdir}
%{_sysusersdir}/%{name}.conf
%{_unitdir}/%{name}.service

%if %{with gui}
%files gui
%{appdir}/bin/cdr-client-ui
%{appdir}/lib/app/conf/logback-ui.xml
%{appdir}/lib/runtime/lib/libLinuxTray.so
%{appdir}/lib/runtime/lib/libnucleus_linux_theme.so
%{appdir}/lib/runtime/lib/libskiko-linux-x64.so
%{_bindir}/cdr-client-ui
%{_datadir}/applications/com.swisscom.health.des.cdr.cdr-client.desktop
%{_datadir}/icons/hicolor/*/apps/%{name}.png
%{_datadir}/metainfo/com.swisscom.health.des.cdr.cdr-client.metainfo.xml
%endif

%changelog
