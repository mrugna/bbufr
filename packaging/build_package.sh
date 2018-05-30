#!/bin/sh

if [ $# -lt 4 ]; then
  echo "Usage: $0 <package> <version> <buildnr> <node_name> ( <spec>)"
  exit 127
fi

CHANGELOG_MESSAGE="Autobuild"

PACKAGE_NAME=$1
PACKAGE_VERSION=$2
BUILD_NUMBER=$3
NODE_NAME=$4
SPECFILE=$PACKAGE_NAME.spec
INSTALL_ARTIFACTS=false

if [ $# -gt 4 ]; then
  SPECFILE=$5
fi

if [ $# -gt 5 ]; then
  INSTALL_ARTIFACTS=$6
fi

get_os_version()
{
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=`echo $NAME | sed -e "s/Linux//g" | sed -e"s/^[[:space:]]*//g" | sed -e's/[[:space:]]*$//g'`
    VER=$VERSION_ID
  elif type lsb_release >/dev/null 2>&1; then
    OS=$(lsb_release -si)
    VER=$(lsb_release -sr)
  elif [ -f /etc/lsb-release ]; then
    . /etc/lsb-release
    OS=$DISTRIB_ID
    VER=$DISTRIB_RELEASE
  elif [ -f /etc/debian_version ]; then
    OS=Debian
    VER=$(cat /etc/debian_version)
  elif [ -f /etc/redhat-release ]; then
    OS=`cat /etc/redhat-release | cut -d' ' -f1`
    VER=`cat /etc/redhat-release | cut -d' ' -f4 | cut -d'.' -f1`
  else
    OS=$(uname -s)
    VER=$(uname -r)
  fi
  echo "$OS-$VER"
}

prepare_and_build_debian()
{
  #git log b34a9525c2537e303a8a247f23c05088a015380b.. --pretty=%B
  if [ -d "debian" ]; then
    \rm -fr "debian"
  fi
  cp -r packaging/debian .
  dch --distribution UNRELEASED --package $1 --newversion $2 "Autogenerated packaging"
  debuild -b -uc -us
  if [ $? -eq 0 -a "$3" = "true" ]; then
      sudo dpkg -i ../$1*_$2*.deb
  fi
}

prepare_and_build_centos()
{
  if [ ! -z "${RPM_ROOT}" ]; then
    RPM_TOP_DIR="${RPM_ROOT}"
  else
    RPM_TOP_DIR=`rpmbuild --eval '%_topdir'`
  fi
  RPM_ARCH_DIR=`rpmbuild --eval '%_arch'`
  RPM_PCK_DIR=`rpmbuild --eval '%_rpmdir/%_arch'`
  #First we need to create a source tarball. Remove the old one
  if [ -f "$RPM_TOP_DIR/SOURCES/$2-$3.tar.gz" ]; then
    \rm -f "$RPM_TOP_DIR/SOURCES/$2-$3.tar.gz"
  fi
  CFILES=`ls -1 packaging/centos/ | egrep '.conf$' | wc -l`
  if [ $CFILES -gt 0 ]; then
    cp -f packaging/centos/*.conf "$RPM_TOP_DIR/SOURCES/"
  fi
  #HOW DO WE DETERMINE BUILDROOT? NOW, just fake it...
  git archive --format="tar.gz" --prefix="$2-$3/" master -o "$RPM_TOP_DIR/SOURCES/$2-$3.tar.gz"
  if [ $? -ne 0 ]; then
    echo "Failed to create source archive..."
    exit 127
  fi
  rpmbuild --define="version $3" --define "snapshot $4" -v -ba $1
  if [ $? -eq 0 -a "$5" = "true" ]; then
    if [ "$RPM_PCK_DIR" != "" ]; then
      sudo rpm -Uvh "$RPM_PCK_DIR/$2*-$3-$4*.$RPM_ARCH_DIR.rpm"
    fi
  fi
}

if [ "$BUILD_NUMBER" = "" ]; then
  BUILD_NUMBER=1
fi

OS_VARIANT=`get_os_version`

echo "Building $PACKAGE_NAME-$PACKAGE_VERSION-$BUILD_NUMBER on $OS_VARIANT on node $NODE_NAME"

if [ "$OS_VARIANT" = "Ubuntu-16.04" ]; then
  echo "Debian build"
  prepare_and_build_debian $PACKAGE_NAME $PACKAGE_VERSION-$BUILD_NUMBER $INSTALL_ARTIFACTS
elif [ "$OS_VARIANT" = "CentOS-7" ]; then
  echo "Redhat build"
  prepare_and_build_centos $SPECFILE $PACKAGE_NAME $PACKAGE_VERSION $BUILD_NUMBER $INSTALL_ARTIFACTS
fi


