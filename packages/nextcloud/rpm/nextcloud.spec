# Version and release are injected by build/create-rpm.sh via --define. Provide
# defaults so the spec still parses (e.g. for `dnf builddep`) without them.
%{!?pkg_version: %global pkg_version 0}
%{!?pkg_release: %global pkg_release 0}

%global ncdir /var/www/html/nextcloud

# The newest PHP the distribution ships (RHEL 10: php8.4), within the range of
# lib/versioncheck.php (8.3 to 8.5). Raise it when the distribution adds a newer
# PHP. Remi's PHP meets it as well.
%global php_min 8.4
%global php_max 8.6

# Nextcloud verifies the files of its release against a signed list of hashes
# (occ integrity:check-core). Leave the tarball byte for byte as it is: no
# shebang rewriting (occ), and no automatic dependencies from the scripts that
# the bundled libraries carry.
%global __brp_mangle_shebangs %{nil}
%global __requires_exclude_from ^%{ncdir}/.*$

Name:           nextcloud
Version:        %{pkg_version}
Release:        %{pkg_release}%{?dist}
Summary:        Private file sync and share server

# from the Fedora/EPEL spec: Nextcloud is AGPLv3+, the bundled libraries carry
# the others
License:        AGPL-3.0-or-later AND MIT AND BSD-3-Clause AND Apache-2.0 AND WTFPL AND CC-BY-SA-4.0 AND GPL-3.0-or-later AND Adobe-2006
URL:            https://nextcloud.com
Source0:        https://download.nextcloud.com/server/releases/%{name}-%{version}.tar.bz2
Source1:        nextcloud-package.config.php
Source2:        nextcloud-post-update
Source3:        nextcloud-jobs.service
Source4:        nextcloud-jobs.timer
Source5:        linuxfabrik_nextcloud.cil
Source6:        nextcloud-httpd.conf.example
Source7:        https://download.nextcloud.com/server/releases/%{name}-%{version}.tar.bz2.asc
Source8:        nextcloud.asc

BuildArch:      noarch

BuildRequires:  gnupg2
BuildRequires:  systemd-rpm-macros

# One web server and one database integration, as in the Fedora/EPEL package.
# Unversioned: the subpackages only pull in dependencies, and %%pre refusing a
# downgrade of nextcloud must not leave the others with broken dependencies.
Requires:       %{name}-database
Requires:       %{name}-webserver

# The extensions are the ones the Nextcloud admin manual lists as required; the
# recommended ones (apcu, imagick, intl, redis, ...) are left to the
# administrator or to LFOps. The capabilities are met by the PHP of RHEL and by
# Remi's alike.
Requires:       (php(language) >= %{php_min} with php(language) < %{php_max})
Requires:       php-cli >= %{php_min}
Requires:       php-ctype
Requires:       php-curl
Requires:       php-dom
Requires:       php-fileinfo
Requires:       php-filter
Requires:       php-gd
Requires:       php-hash
Requires:       php-json
Requires:       php-libxml
Requires:       php-mbstring
Requires:       php-openssl
Requires:       php-posix
Requires:       php-session
Requires:       php-simplexml
Requires:       php-xmlreader
Requires:       php-xmlwriter
Requires:       php-zip
Requires:       php-zlib
# %%pre reads the version of an existing installation, as root
Requires(pre):  php-cli
Requires(pre):  util-linux
Requires(posttrans): php-cli
Requires(posttrans): util-linux
Requires(post): (policycoreutils if selinux-policy-targeted)
Requires(postun): (policycoreutils if selinux-policy-targeted)
# the web server user
Requires(pre):  httpd-filesystem

%description
Nextcloud gives you access to your files through a web interface or WebDAV,
and syncs files, contacts and calendars across your devices.

The release is installed below %{ncdir}, as in the official Docker images:
the shipped apps read-only in apps/, apps from the app store in custom_apps/.
The code belongs to root; the web server can only write config/, custom_apps/,
data/ and .htaccess. Updates come through the package manager, which also runs
`occ upgrade`; the web updater is off.

An existing installation in %{ncdir} that was not installed by this package
is taken over: its apps from the app store move to custom_apps/, the rest of
the previous code is kept in /var/www/html/.nextcloud-before-package-*.

The package needs PHP %{php_min} or newer. A host on an older PHP stream has to
switch first, together with the PHP extensions it uses (e.g. php8.4-pecl-apcu,
php8.4-pecl-redis6), and enable php-fpm.service again afterwards: removing the
old php-fpm package disables the service.


%package httpd
Summary:        Apache httpd integration for Nextcloud
Provides:       %{name}-webserver = %{version}-%{release}
Requires:       %{name}
Requires:       httpd
Requires:       php-fpm

%description httpd
Pulls in Apache httpd and PHP-FPM. The vHost is not activated automatically;
an example is in %{_docdir}/%{name}-httpd/.


%package mysql
Summary:        MySQL and MariaDB support for Nextcloud
Provides:       %{name}-database = %{version}-%{release}
Requires:       %{name}
Requires:       php-pdo_mysql

%description mysql
The PHP driver for a local or remote MySQL or MariaDB server. The database
server itself is not pulled in.


%package postgresql
Summary:        PostgreSQL support for Nextcloud
Provides:       %{name}-database = %{version}-%{release}
Requires:       %{name}
Requires:       php-pdo_pgsql

%description postgresql
The PHP driver for a local or remote PostgreSQL server. The database server
itself is not pulled in.


%package sqlite
Summary:        SQLite support for Nextcloud
Provides:       %{name}-database = %{version}-%{release}
Requires:       %{name}
Requires:       php-pdo_sqlite

%description sqlite
The PHP driver for an SQLite database below the data directory. Only for
testing and small single-user setups.


%prep
%{gpgverify} --keyring='%{SOURCE8}' --signature='%{SOURCE7}' --data='%{SOURCE0}'
%setup -q -n %{name}

%build
# nothing to build

%install
install --directory %{buildroot}%{ncdir}
cp --archive . %{buildroot}%{ncdir}/
# The installer is enabled by %%posttrans only where Nextcloud is not installed
# yet. The updater replaces files that belong to the package.
rm %{buildroot}%{ncdir}/config/CAN_INSTALL
rm --recursive %{buildroot}%{ncdir}/updater
# 0644 in the tarball; the integrity check compares the content only
chmod 0755 %{buildroot}%{ncdir}/occ
install --directory %{buildroot}%{ncdir}/custom_apps %{buildroot}%{ncdir}/data
install -D -p -m 0640 %{SOURCE1} %{buildroot}%{ncdir}/config/package.config.php

install -D -p -m 0755 %{SOURCE2} %{buildroot}%{_libexecdir}/%{name}/post-update
install -D -p -m 0644 %{SOURCE3} %{buildroot}%{_unitdir}/nextcloud-jobs.service
install -D -p -m 0644 %{SOURCE4} %{buildroot}%{_unitdir}/nextcloud-jobs.timer
install -D -p -m 0644 %{SOURCE5} %{buildroot}%{_datadir}/selinux/packages/linuxfabrik_nextcloud.cil
cp -p %{SOURCE6} .

# Everything below ncdir belongs to root, except the entries listed in %%files
# with their own attributes.
(
    cd %{buildroot}%{ncdir}
    for entry in * .[!.]*; do
        case "$entry" in
        .htaccess | config | custom_apps | data) ;;
        *) echo "%{ncdir}/$entry" ;;
        esac
    done
) > files.list

%pre
ncdir=%{ncdir}
if [ -f "$ncdir/config/config.php" ]; then
    installed="$(php --run 'include $argv[1]; echo empty($CONFIG["installed"]) ? "" : ($CONFIG["version"] ?? "");' \
        "$ncdir/config/config.php")" || installed=''
    if [ -n "$installed" ]; then
        # Nextcloud neither downgrades nor skips a major release, see
        # $OC_VersionCanBeUpgradedFrom in version.php
        php --run '
            $installed = implode(".", array_slice(explode(".", $argv[1]), 0, 3));
            $package = $argv[2];
            if (version_compare($installed, $package, ">")) {
                fwrite(STDERR, "Nextcloud $installed is installed in $argv[3], newer than this package ($package). Nextcloud cannot be downgraded.\n");
                exit(1);
            }
            if ((int)$package - (int)$installed > 1) {
                fwrite(STDERR, "Nextcloud $installed is installed in $argv[3]. Nextcloud cannot skip a major release; update to " . ((int)$installed + 1) . " first.\n");
                exit(1);
            }' "$installed" '%{version}' "$ncdir" || exit 1
        # %%posttrans leaves it again once the database is migrated
        if runuser --user apache -- php "$ncdir/occ" --no-interaction maintenance:mode --on >/dev/null 2>&1; then
            touch /run/nextcloud-package-maintenance
        fi
    fi
fi

# Take over an installation that was not installed by this package, e.g. by the
# LFOps nextcloud role or from the tarball by hand. Its apps from the app store
# move to custom_apps/, the rest of the previous code out of the way, so no file
# of the previous release is left behind. config/, data/ and themes/ stay.
if [ "$1" -eq 1 ] && [ -f "$ncdir/version.php" ]; then
    shipped="$(php --run '
        $shipped = json_decode(file_get_contents($argv[1]), true);
        echo implode("\n", $shipped["shippedApps"]), "\n";' "$ncdir/core/shipped.json")" || {
        echo "Cannot read the list of shipped apps from $ncdir/core/shipped.json, not taking over the installation in $ncdir." >&2
        exit 1
    }
    backup="/var/www/html/.nextcloud-before-package-$(date +%%Y%%m%%d%%H%%M%%S)"
    mkdir --mode=0700 "$backup"
    mkdir --parents "$ncdir/custom_apps"
    for app in "$ncdir"/apps/*/; do
        app="$(basename "$app")"
        if ! printf '%%s' "$shipped" | grep --quiet --line-regexp --fixed-strings "$app" &&
            [ ! -e "$ncdir/custom_apps/$app" ]; then
            mv "$ncdir/apps/$app" "$ncdir/custom_apps/"
            echo "Moved the app $app to $ncdir/custom_apps/."
        fi
    done
    # a data directory inside the installation stays as well
    datadir=''
    if [ -f "$ncdir/config/config.php" ]; then
        datadir="$(php --run 'include $argv[1]; echo $CONFIG["datadirectory"] ?? "";' "$ncdir/config/config.php")" || datadir=''
    fi
    for entry in "$ncdir"/* "$ncdir"/.[!.]*; do
        [ -e "$entry" ] || continue
        case "$entry" in
        "$ncdir/config" | "$ncdir/custom_apps" | "$ncdir/data" | "$ncdir/themes" | "${datadir%%/}") ;;
        *) mv "$entry" "$backup/" ;;
        esac
    done
    echo "Moved the previous Nextcloud code to $backup. Remove it once the update works."
fi

%post
if [ -x /usr/sbin/semodule ]; then
    /usr/sbin/semodule --priority 200 --install %{_datadir}/selinux/packages/linuxfabrik_nextcloud.cil >/dev/null 2>&1 || :
    /usr/sbin/restorecon -R %{ncdir}/.htaccess %{ncdir}/config %{ncdir}/custom_apps >/dev/null 2>&1 || :
fi
%systemd_post nextcloud-jobs.timer

%preun
%systemd_preun nextcloud-jobs.timer

%postun
if [ "$1" -eq 0 ] && [ -x /usr/sbin/semodule ]; then
    /usr/sbin/semodule --priority 200 --remove linuxfabrik_nextcloud >/dev/null 2>&1 || :
fi
%systemd_postun nextcloud-jobs.timer

%posttrans
%{_libexecdir}/%{name}/post-update ||
    echo 'The Nextcloud update did not finish. Fix the cause and run %{_libexecdir}/%{name}/post-update.' >&2

%files -f files.list
%license COPYING
%dir %{ncdir}
%attr(0644,apache,apache) %verify(not md5 size mtime) %{ncdir}/.htaccess
%dir %attr(0750,apache,apache) %{ncdir}/config
%{ncdir}/config/.htaccess
%{ncdir}/config/config.sample.php
%config(noreplace) %attr(0640,root,apache) %{ncdir}/config/package.config.php
%dir %attr(0755,apache,apache) %{ncdir}/custom_apps
%dir %attr(0750,apache,apache) %{ncdir}/data
%{_datadir}/selinux/packages/linuxfabrik_nextcloud.cil
%{_libexecdir}/%{name}/
%{_unitdir}/nextcloud-jobs.service
%{_unitdir}/nextcloud-jobs.timer

%files httpd
%doc nextcloud-httpd.conf.example

%files mysql

%files postgresql

%files sqlite

%changelog
