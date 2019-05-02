#!/bin/bash

_DIST=$1

PKG_DIR=$(pwd)

function die()
{
  echo $*
  exit 1
}

[[ ! -z "$_DIST" ]] || die "Usage: $0 <dist-tarball>"
[[ -f "$_DIST" ]] || die "Can't find dist package [$_DIST]."
[[ -d osx ]] || die "Run me from the top-level packaging directory."

pushd $(dirname "$_DIST") >/dev/null || die "Can't change into trunk dir."
_DIST="$(pwd)/$(basename $_DIST)"
popd >/dev/null

mkdir -p output || die "Can't create output dir."

rm -rf build/osx-build 2>/dev/null

mkdir -p build/osx-build || die "Can't create build dir."
cd build/osx-build || die "Can't enter build dir."

tar xfz $_DIST || die "Can't unpack tarball."
cd * || die "Can't enter unpacked dir."

PACKAGE_NAME="$(basename $_DIST)"
PACKAGE_NAME="${PACKAGE_NAME%%-*}"
PACKAGE_VERSION="$(basename $_DIST)"
PACKAGE_VERSION="${PACKAGE_VERSION##*-}"
PACKAGE_VERSION="${PACKAGE_VERSION%.tar.gz}"

BUILD_DIR=$(pwd)

mkdir build || die "Can't create build dir."
cd build || die "Can't enter build dir."

OPENSSL_PKGCONFIG_PATH=$(brew info openssl@1.1 | grep PKG_CONFIG_PATH | sed -e 's/^[^"]*"//' -e 's/".*//')
export PKG_CONFIG_PATH=$OPENSSL_PKGCONFIG_PATH:/usr/local/lib/pkgconfig

cmake -DEnableTests=No -DEnableMacOSBundle=Yes .. || die "CMake failed."
make || die "make failed."
make "${PACKAGE_NAME}_man_pdf" || die "make pdfs failed."

cd $PKG_DIR/build/osx-build || die "Can't enter osx-build."

mkdir -p $PACKAGE_NAME.app/Contents || die "Can't create app bundle dir."
cd $PACKAGE_NAME.app/Contents || die "Can't enter app bundle dir."

mkdir -p MacOS Resources/Scripts Resources/libs Resources/bin || die "Can't create content dirs."

for F in $PKG_DIR/osx/*.in; do
  NEW_FN="$(basename $F)"
  NEW_FN="${NEW_FN%%.in}"

  sed \
    -e "s/__PACKAGE_NAME__/$PACKAGE_NAME/g" \
    -e "s/__PACKAGE_VERSION__/$PACKAGE_VERSION/g" \
    < $F \
    > $NEW_FN || die "Can't transform template."
done

osacompile -o Resources/Scripts/main.scpt main.applescript || die "Can't compile script."
rm -f main.applescript

cp $PKG_DIR/osx/applet MacOS || die "Can't copy applet."
cp $BUILD_DIR/COPYING $BUILD_DIR/ChangeLog $BUILD_DIR/README Resources || die "Can't copy documents."
cp $BUILD_DIR/build/config/$PACKAGE_NAME.conf Resources || die "Can't copy config file."
cp $PKG_DIR/osx/applet.icns $PKG_DIR/osx/applet.rsrc Resources || die "Can't copy applet resources."

cd $BUILD_DIR || die "Can't enter build dir."

for F in $(grep add_executable src/CMakeLists.txt | sed -e 's/^[^(]*(//' -e 's/ .*//' -e "s/\${PROJECT_NAME}/$PACKAGE_NAME/g"); do
  cp build/src/$F $PKG_DIR/build/osx-build/$PACKAGE_NAME.app/Contents/Resources/bin || die "Can't copy binary [$F]."
done

cd $PKG_DIR/build/osx-build || die "Can't enter osx-build."

for F in $PACKAGE_NAME.app/Contents/Resources/bin/*; do
  dylibbundler -od -b -x $F -d $PACKAGE_NAME.app/Contents/Resources/libs
done

cd $PKG_DIR || die "Can't enter packaging dir."

mkdir build/osx-build/manual || die "Can't create manual dir."
cp $BUILD_DIR/build/man/*.pdf build/osx-build/manual || die "Can't copy manual PDFs."
cp $BUILD_DIR/COPYING $BUILD_DIR/ChangeLog $BUILD_DIR/README build/osx-build || die "Can't copy documents to image root."
rm -rf $BUILD_DIR || die "Can't remove temporary build dir."

hdiutil create \
  -fs HFSX -layout SPUD -format UDZO -scrub -uid 99 -gid 99 -ov \
  -volname "$PACKAGE_NAME $PACKAGE_VERSION" \
  "$PACKAGE_NAME-$PACKAGE_VERSION.dmg" \
  -srcfolder build/osx-build

mv $PACKAGE_NAME-$PACKAGE_VERSION.dmg output/ || die "Can't move output image."

rm -rf build/osx-build
rmdir build 2>/dev/null
