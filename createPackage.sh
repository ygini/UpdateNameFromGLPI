#!/bin/bash

if [ "$EUID" -ne 0 ]
  then echo "Please run this script as root"
  exit 1
fi

SCRIPT_PATH=$(cd $(dirname "${BASH_SOURCE[0]}") && pwd)
app_to_package="$1"
launchd_to_package="$SCRIPT_PATH/LaunchD/com.github.ygini.UpdateNameFromGLPI.plist"

if [ -z "$app_to_package" ]
then
    echo "You must provide an app to package as first argument"
    exit 2
elif [ ! -e "$app_to_package/Contents/Info.plist" ]
then
    echo "Provided app seems invalid"
    echo "App path: $app_to_package"
    exit 3
fi

if [ ! -e "$launchd_to_package" ]
then
    echo "Impossible to find LaunchD file"
    echo "LaunchD path: $launchd_to_package"
    exit 4
fi

BUILD_DIR=$(mktemp -d)
echo "Working folder: $BUILD_DIR"

building_app_path="$BUILD_DIR/Library/Application Support/com.github.ygini.UpdateNameFromGLPI"
mkdir -p "$building_app_path"

building_launchd_path="$BUILD_DIR/Library/LaunchDaemons"
mkdir -p "$building_launchd_path"

cp -r "$app_to_package" "$building_app_path"
cp "$launchd_to_package" "$building_launchd_path"

chown -R root:wheel "$BUILD_DIR"

pkgbuild --root "$BUILD_DIR" --identifier "com.abelionni.pkg.UpdateNameFromGLPI" --version $(date +%Y.%m.%d.%H.%M.%S) --scripts "$SCRIPT_PATH/package_scripts" "$SCRIPT_PATH/UpdateNameFromGLPI.pkg"

echo "Cleaning temp folder"

rm -rf "$BUILD_DIR"

exit 0
