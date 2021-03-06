#!/bin/bash

_DIST=$1
_SERIES=$2

PKG_DIR=$(pwd)

function die()
{
  echo $*
  exit 1
}

[[ ! -z "$_SERIES" ]] || die "Usage: $0 <dist-tarball> <series>"
[[ -f "$_DIST" ]] || die "Can't find dist package [$_DIST]."
[[ -d ubuntu ]] || die "Run me from the top-level packaging directory."
[[ "$_DIST" == "${_DIST%%.tar.gz}.tar.gz" ]] || die "Tarball name needs to end in .tar.gz."

DIST_NAME="$(basename $_DIST)"
DIST_NAME="${DIST_NAME%%-*}"
CL_FILE="changelog.$DIST_NAME.$_SERIES"

[[ -f "ubuntu/$CL_FILE" ]] || die "Expected to find changelog file [ubuntu/$CL_FILE]."

pushd $(dirname $_DIST) >/dev/null || die "Can't enter dist dir."
_DIST=$(pwd)/$(basename $_DIST)
popd >/dev/null

mkdir -p output || die "Can't create output dir."

rm -rf build/ub-build
mkdir -p build/ub-build || die "Can't create build dir."
cd build/ub-build || die "Can't enter build dir."

TAR_NAME=$(basename $_DIST)
TAR_NAME=${TAR_NAME%%.tar.gz}
cp $_DIST ${TAR_NAME/-/_}.orig.tar.gz || die "Failed to copy tarball."

tar xfz $_DIST || die "Failed to unpack tarball."
cd $(find . -mindepth 1 -maxdepth 1 -type d) || die "Failed to enter source dir."

cp -r $PKG_DIR/debian . || die "Can't copy debian files."
cd debian || die "Can't enter debian"

rm changelog.* || die "Can't remove existing changelog"
cp $PKG_DIR/ubuntu/control.in . || die "Can't copy Ubuntu control file."

$PKG_DIR/scripts/merge-changelogs.py \
  $PKG_DIR/debian/changelog.$DIST_NAME \
  $PKG_DIR/ubuntu/changelog.$DIST_NAME.$_SERIES \
  > changelog \
  || die "Can't merge changelogs"

CL_FULL_VERSION="$(head -n 1 changelog | sed -e 's/.* (//' -e 's/).*//')"

for F in *.in; do
  sed \
    -e "s/__PACKAGE_NAME__/$DIST_NAME/g" \
    -e "s/__PACKAGE_VERSION__/$CL_FULL_VERSION/g" \
    < $F \
    > ${F%%.in}
done
rm -f *.in

debuild -S -sa || die "debuild (source) failed."

cd $PKG_DIR

mv build/ub-build/*.tar.[gx]z output/
mv build/ub-build/*.dsc output/
mv build/ub-build/*.build output/
mv build/ub-build/*.buildinfo output/
mv build/ub-build/*.changes output/

rm -rf build/ub-build
rmdir build 2>/dev/null
