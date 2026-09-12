# Illustrative OBS input recipe. This project publishes source ZIPs, not RPMs.
%global bootstrap_version 2026.09.12
Name:           crystal-bootstrap
Version:        1.21.0
Release:        0
Summary:        Build the Crystal compiler from generated C++ sources
License:        Apache-2.0 AND MIT AND BSD-3-Clause
URL:            https://github.com/soupglasses/crystal-bootstrap
Source0:        %{url}/releases/download/bootstrap-%{bootstrap_version}/crystal-bootstrap-%{bootstrap_version}-crystal-%{version}-llvm20.zip
BuildRequires:  gcc-c++
BuildRequires:  llvm20-devel
BuildRequires:  make
BuildRequires:  python3
BuildRequires:  unzip
BuildRequires:  pkgconfig(bdw-gc)
BuildRequires:  pkgconfig(libutf8proc)
BuildRequires:  pkgconfig(libpcre2-8)
BuildRequires:  pkgconfig(libxml-2.0)
BuildRequires:  pkgconfig(openssl)
BuildRequires:  pkgconfig(zlib)
BuildRequires:  readline-devel
ExclusiveArch:  x86_64

%description
Example source bootstrap recipe. The generated C++ builds an intermediate
compiler, which builds the upstream Crystal compiler from the included source.

%prep
%setup -q -n crystal-bootstrap-%{bootstrap_version}-crystal-%{version}-llvm20

%build
export CRYSTAL_CONFIG_PATH='%{_datadir}/crystal/src'
export CRYSTAL_CONFIG_LIBRARY_PATH='%{_libdir}/crystal'
make CXX=g++ LLVM_CONFIG=llvm-config-20

%install
install -Dm755 build/crystal %{buildroot}%{_bindir}/crystal
mkdir -p %{buildroot}%{_datadir}/crystal
cp -a upstream/src %{buildroot}%{_datadir}/crystal/src
rm -f %{buildroot}%{_datadir}/crystal/src/llvm/ext/llvm_ext.o

%files
%license LICENSE upstream/LICENSE notices/*
%{_bindir}/crystal
%{_datadir}/crystal

%changelog
