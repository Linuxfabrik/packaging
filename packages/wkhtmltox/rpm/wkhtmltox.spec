# Repacks upstream's EL 9 RPM (wkhtmltopdf/packaging release 0.12.6.1-3) for
# EL 10, file by file and with upstream's dependencies, name, epoch and paths.
# Upstream archived the project, so there is no source build to port.

# Version and release are injected by build/create-rpm.sh via --define. Provide
# defaults so the spec still parses (e.g. for `dnf builddep`) without them.
%{!?pkg_version: %global pkg_version 0}
%{!?pkg_release: %global pkg_release 0}

# The release of upstream's RPM. It leads the release of this package, so
# 1:0.12.6.1-3.1.el10 sorts after upstream's 1:0.12.6.1-3.almalinux9 and
# updates a host that installed it.
%global upstream_release 3

# Prebuilt binaries: no debug package and no stripping, keep them as upstream
# built them.
%global debug_package %{nil}
%global __brp_strip %{nil}
%global __brp_strip_comment_note %{nil}
%global __brp_strip_static_archive %{nil}
%global __strip /bin/true

Name:           wkhtmltox
Epoch:          1
Version:        %{pkg_version}
Release:        %{upstream_release}.%{pkg_release}%{?dist}
Summary:        convert HTML to PDF and various image formats using QtWebkit

# wkhtmltopdf is LGPL-3.0-or-later, the statically linked, patched Qt 4.8
# LGPL-2.1 with the Qt LGPL exception
License:        LGPL-3.0-or-later AND LGPL-2.1-only WITH Qt-LGPL-exception-1.1
URL:            https://wkhtmltopdf.org/
Source0:        https://github.com/wkhtmltopdf/packaging/releases/download/%{version}-%{upstream_release}/%{name}-%{version}-%{upstream_release}.almalinux9.%{_arch}.rpm

ExclusiveArch:  aarch64 x86_64

BuildRequires:  cpio

# upstream's dependencies; the binaries load OpenSSL at runtime and the fonts
# are what QtWebKit falls back to
Requires:       ca-certificates
Requires:       fontconfig
Requires:       freetype
Requires:       glibc
Requires:       libjpeg
Requires:       libpng
Requires:       libstdc++
Requires:       libX11
Requires:       libXext
Requires:       libXrender
Requires:       openssl
Requires:       xorg-x11-fonts-75dpi
Requires:       xorg-x11-fonts-Type1
Requires:       zlib

%description
wkhtmltopdf and wkhtmltoimage are command line tools to render HTML into PDF
and various image formats using the QtWebKit rendering engine. This build is
linked against a patched Qt and supports headers, footers, tables of contents
and page breaks.

QtWebKit gets no security fixes anymore. Render trusted HTML only.

%prep
%setup -q -c -T
rpm2cpio %{SOURCE0} | cpio --extract --make-directories --preserve-modification-time --quiet

%build
# prebuilt

%install
cp --archive usr %{buildroot}/
# upstream's build-id links; rpmbuild creates its own
rm --recursive %{buildroot}/usr/lib/.build-id

%files
/usr/local/bin/wkhtmltoimage
/usr/local/bin/wkhtmltopdf
/usr/local/include/wkhtmltox
/usr/local/lib/libwkhtmltox.so
/usr/local/lib/libwkhtmltox.so.0
/usr/local/lib/libwkhtmltox.so.0.12
/usr/local/lib/libwkhtmltox.so.0.12.6
/usr/local/share/man/man1/wkhtmltoimage.1*
/usr/local/share/man/man1/wkhtmltopdf.1*

%changelog
