#!/bin/bash
# Volumio Image Builder
# Copyright Michelangelo Guarise - Volumio.org
#
# TODO: Add gé credits
#
# Dependencies:
# parted squashfs-tools dosfstools multistrap qemu binfmt-support qemu-user-static kpartx
# Edit 03 05 2018

#Set fonts for Help.
NORM=$(tput sgr0)
BOLD=$(tput bold)
REV=$(tput smso)

ARCH=none
#Help function
function HELP {
  echo "

Usage: ./build.sh -b x86 -d x86 -v 1.0

"
  exit 1
}

#$1 = ${BUILD} $2 = ${VERSION} $3 = ${DEVICE}"
function check_os_release {
  ARCH_BUILD=$1
  HAS_VERSION=$(grep -c VOLUMIO_VERSION "build/${ARCH_BUILD}/root/etc/os-release")
  VERSION=$2
  DEVICE=$3

  if [ "$HAS_VERSION" -ne "0" ]; then
    # os-release already has a VERSION number
    # cut the last 2 lines in case other devices are being built from the same rootfs
    head -n -2 "build/${ARCH_BUILD}/root/etc/os-release" > "build/${ARCH_BUILD}/root/etc/tmp-release"
    mv "build/${ARCH_BUILD}/root/etc/tmp-release" "build/${ARCH_BUILD}/root/etc/os-release"
  fi
  echo "VOLUMIO_VERSION=\"${VERSION}\"" >> "build/${ARCH_BUILD}/root/etc/os-release"
  echo "VOLUMIO_HARDWARE=\"${DEVICE}\"" >> "build/${ARCH_BUILD}/root/etc/os-release"
}


#Check the number of arguments. If none are passed, print help and exit.
NUMARGS=$#
if [ "$NUMARGS" -eq 0 ]; then
  HELP
fi

while getopts b:v:d:l:p:t:e FLAG; do
  case $FLAG in
    b)
      BUILD=$OPTARG
      ;;
    d)
      DEVICE=$OPTARG
      ;;
    v)
      VERSION=$OPTARG
      ;;
    l)
      #Create docker layer
      CREATE_DOCKER_LAYER=1
      DOCKER_REPOSITORY_NAME=$OPTARG
      ;;
    p)
      PATCH=$OPTARG
      ;;
    h)  #show help
      HELP
      ;;
    t)
      VARIANT=$OPTARG
      ;;
    /?) #unrecognized option - show help
      echo -e \\n"Option -${BOLD}$OPTARG${NORM} not allowed."
      HELP
      ;;
  esac
done

shift $((OPTIND-1))

echo "Checking whether we are running as root"
if [ "$(id -u)" -ne 0 ]; then
  echo "Please run the build script as root"
  exit
fi

if [ -z "${VARIANT}" ]; then
   VARIANT="volumio"
fi

if [ -n "$BUILD" ]; then
  CONF="recipes/$BUILD.conf"
  
  echo 'Building X86 Base System with Debian'
  ARCH="i386"
  BUILD="x86"

  if [ -d "build/$BUILD" ]; then
    echo "Build folder exists, cleaning it"
    rm -rf "build/$BUILD"
  elif [ -d build ]; then
    echo "Build folder exists, leaving it"
  else
    echo "Creating build folder"
    mkdir build
  fi

  mkdir "build/$BUILD"
  mkdir "build/$BUILD/root"
  
  multistrap -a "$ARCH" -f "$CONF"
  cp scripts/volumioconfig.sh "build/$BUILD/root"

  mount /dev "build/$BUILD/root/dev" -o bind
  mount /proc "build/$BUILD/root/proc" -t proc
  mount /sys "build/$BUILD/root/sys" -t sysfs

  echo 'Cloning Volumio Node Backend'
  mkdir "build/$BUILD/root/volumio"  
  if [ -n "$PATCH" ]; then
      echo "Cloning Volumio with all its history"
      git clone https://github.com/WeDloMiS/Volumio2.git build/$BUILD/root/volumio
  else
      git clone --depth 1 -b master --single-branch https://github.com/WeDloMiS/Volumio2.git build/$BUILD/root/volumio
  fi
  
  echo 'Cloning Volumio UI'
  git clone --depth 1 -b dist --single-branch https://github.com/WeDloMiS/Volumio2-UI.git "build/$BUILD/root/volumio/http/www"
  
  echo "Adding os-release infos"
  {
    echo "VOLUMIO_BUILD_VERSION=\"$(git rev-parse HEAD)\""
    echo "VOLUMIO_FE_VERSION=\"$(git --git-dir "build/$BUILD/root/volumio/http/www/.git" rev-parse HEAD)\""
    echo "VOLUMIO_BE_VERSION=\"$(git --git-dir "build/$BUILD/root/volumio/.git" rev-parse HEAD)\""
    echo "VOLUMIO_ARCH=\"${BUILD}\""
  } >> "build/$BUILD/root/etc/os-release"
  rm -rf build/$BUILD/root/volumio/http/www/.git
su -
./volumioconfig.sh
EOF
  else
    echo ':arm:M::\x7fELF\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x28\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/usr/bin/qemu-arm-static:' > /proc/sys/fs/binfmt_misc/register
    chroot "build/$BUILD/root" /volumioconfig.sh
  fi

  echo "Base System Installed"
  rm "build/$BUILD/root/volumioconfig.sh"
  ###Dirty fix for mpd.conf TODO use volumio repo
  cp volumio/etc/mpd.conf "build/$BUILD/root/etc/mpd.conf"

  CUR_DATE=$(date)
  #Write some Version informations
  echo "Writing system information"
  echo "VOLUMIO_VARIANT=\"${VARIANT}\"
VOLUMIO_TEST=\"FALSE\"
VOLUMIO_BUILD_DATE=\"${CUR_DATE}\"
" >> "build/${BUILD}/root/etc/os-release"

  echo "Unmounting Temp devices"
  umount -l "build/$BUILD/root/dev"
  umount -l "build/$BUILD/root/proc"
  umount -l "build/$BUILD/root/sys"
  # Setting up cgmanager under chroot/qemu leaves a mounted fs behind, clean it up
  umount -l "build/$BUILD/root/run/cgmanager/fs"
  sh scripts/configure.sh -b "$BUILD"
fi

if [ -n "$PATCH" ]; then
  echo "Copying Patch to Rootfs"
  cp -rp "$PATCH"  "build/$BUILD/root/"
else
  PATCH='volumio'
fi

echo 'Writing x86 Image File'
check_os_release "x86" "$VERSION" "$DEVICE"
sh scripts/x86image.sh -v "$VERSION" -p "$PATCH";

#When the tar is created we can build the docker layer
if [ "$CREATE_DOCKER_LAYER" = 1 ]; then
  echo 'Creating docker layer'
  DOCKER_UID="$(sudo docker import "VolumioRootFS$VERSION.tar.gz" "$DOCKER_REPOSITORY_NAME")"
  echo "$DOCKER_UID"
fi
