# Version and release are injected by build/create-rpm.sh via --define. Provide
# defaults so the spec still parses (e.g. for `dnf builddep`) without them.
%{!?pkg_version: %global pkg_version 0}
%{!?pkg_release: %global pkg_release 0}

# Repository path below repo.linuxfabrik.ch, see packages/linuxfabrik-release/
# and CONTRIBUTING.md "Repository layout". EL takes the major version at build
# time, since EL 8 has no $releasever_major. Fedora keeps $releasever, so the
# repository follows a system upgrade. SLES 16 does not define %%{sle_version},
# so the major version comes from %%{suse_version} (1500, 1600). The path is sle,
# not sles: it serves SLES, SLED and openSUSE Leap alike.
%if 0%{?rhel}
%global repo_path el/%{rhel}
%endif
%if 0%{?fedora}
%global repo_path fedora/$releasever
%endif
%if 0%{?suse_version}
%global repo_path sle/%(echo $((%{suse_version} / 100)))
%global repo_dir %{_sysconfdir}/zypp/repos.d
%else
%global repo_dir %{_sysconfdir}/yum.repos.d
%endif

Name:           linuxfabrik-release
Version:        %{pkg_version}
Release:        %{pkg_release}%{?dist}
Summary:        Linuxfabrik repository configuration

License:        Unlicense
URL:            https://github.com/Linuxfabrik/packaging
Source0:        %{name}-%{version}.tar.gz

BuildArch:      noarch

# The configuration points to one EL major version; refuse to install the EL 9
# package on EL 10 and the like. Same guard as epel-release.
%if 0%{?rhel}
Requires:       (redhat-release >= %{rhel} with redhat-release < %{lua: print(rpm.expand("%{rhel}") + 1)})
%endif

%description
This package contains the repository configuration for repo.linuxfabrik.ch and
the GPG key the packages and the repository metadata are signed with. The
release channel is enabled, the testing channel is configured but disabled.

%prep
%autosetup -n %{name}-%{version}

%build
sed --in-place 's|@REPO_PATH@|%{repo_path}|g' linuxfabrik.repo

%install
install -D -p -m 0644 RPM-GPG-KEY-linuxfabrik %{buildroot}%{_sysconfdir}/pki/rpm-gpg/RPM-GPG-KEY-linuxfabrik
install -D -p -m 0644 linuxfabrik.repo %{buildroot}%{repo_dir}/linuxfabrik.repo

%files
%{_sysconfdir}/pki/rpm-gpg/RPM-GPG-KEY-linuxfabrik
%config(noreplace) %{repo_dir}/linuxfabrik.repo
%if 0%{?suse_version}
# SLES does not own /etc/pki/rpm-gpg
%dir %{_sysconfdir}/pki
%dir %{_sysconfdir}/pki/rpm-gpg
%endif

# Written by build/create-rpm.sh for the version being built.
%changelog
