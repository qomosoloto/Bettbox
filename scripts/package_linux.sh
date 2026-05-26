#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_DIST_DIR="$ROOT_DIR/dist/linux"
DIST_DIR="$BASE_DIST_DIR"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/bettbox-packaging"
BUILD_MODE="release"
TARGETS="all"
APP_NAME="Bettbox"
PACKAGE_NAME="bettbox"
VERSION="$(grep -E '^version:' "$ROOT_DIR/pubspec.yaml" | awk '{print $2}' | cut -d+ -f1)"
ARCH="$(uname -m)"

case "$ARCH" in
  x86_64) FLUTTER_ARCH="x64"; PKG_ARCH="x86_64"; CORE_ARCH="amd64"; APPIMAGE_ARCH="x86_64" ;;
  aarch64|arm64) FLUTTER_ARCH="arm64"; PKG_ARCH="aarch64"; CORE_ARCH="arm64"; APPIMAGE_ARCH="aarch64" ;;
  *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;;
esac

usage() {
  cat <<EOF
Usage: $0 [--all|--appimage|--arch] [--debug|--release]

Outputs:
  AppImage:      dist/linux/Bettbox-$VERSION-$APPIMAGE_ARCH.AppImage
  Arch package:  dist/linux/arch/*.pkg.tar.zst
  AUR template:  dist/linux/aur/$PACKAGE_NAME/PKGBUILD

Debug builds are written under dist/linux/debug/.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all) TARGETS="all" ;;
    --appimage) TARGETS="appimage" ;;
    --arch|--pkgbuild|--pacman) TARGETS="arch" ;;
    --debug) BUILD_MODE="debug" ;;
    --release) BUILD_MODE="release" ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
  shift
done

if [[ "$BUILD_MODE" != "release" ]]; then
  DIST_DIR="$BASE_DIST_DIR/$BUILD_MODE"
fi

export FLUTTER_HOME="${FLUTTER_HOME:-$HOME/fvm/default}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$ANDROID_HOME}"
export ANDROID_AVD_HOME="${ANDROID_AVD_HOME:-$HOME/.config/.android/avd}"
export PATH="$FLUTTER_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1" >&2; exit 1; }
}

prepare_bundle() {
  require_cmd flutter
  require_cmd dart
  require_cmd go

  cd "$ROOT_DIR"
  flutter pub get
  dart run build_runner build -d
  dart ./setup.dart linux --arch "$CORE_ARCH" --out core
  flutter build linux "--$BUILD_MODE"

  BUNDLE_DIR="$ROOT_DIR/build/linux/$FLUTTER_ARCH/$BUILD_MODE/bundle"
  if [[ ! -x "$BUNDLE_DIR/$APP_NAME" ]]; then
    echo "Missing Linux bundle executable: $BUNDLE_DIR/$APP_NAME" >&2
    exit 1
  fi
}

install_tree() {
  local dest="$1"
  rm -rf "$dest"
  install -dm755 "$dest/opt/$PACKAGE_NAME" "$dest/usr/bin" "$dest/usr/share/applications" "$dest/usr/share/pixmaps"
  cp -a "$BUNDLE_DIR/." "$dest/opt/$PACKAGE_NAME/"
  install -Dm644 "$ROOT_DIR/assets/images/icon.png" "$dest/usr/share/pixmaps/$PACKAGE_NAME.png"
  ln -s "/opt/$PACKAGE_NAME/$APP_NAME" "$dest/usr/bin/$PACKAGE_NAME"
  cat > "$dest/usr/share/applications/$PACKAGE_NAME.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Bettbox
GenericName=Proxy Client
Comment=Multi-platform proxy client based on Mihomo
Exec=$PACKAGE_NAME
Icon=$PACKAGE_NAME
Terminal=false
Categories=Network;
StartupNotify=true
EOF
}

download_appimagetool() {
  mkdir -p "$CACHE_DIR"
  local tool="$CACHE_DIR/appimagetool-$APPIMAGE_ARCH.AppImage"
  if [[ ! -x "$tool" ]]; then
    curl -fL --retry 3 -o "$tool" \
      "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-$APPIMAGE_ARCH.AppImage"
    chmod +x "$tool"
  fi
  echo "$tool"
}

build_appimage() {
  require_cmd curl
  local appdir="$DIST_DIR/appimage/AppDir"
  install_tree "$appdir"
  ln -sf "usr/share/pixmaps/$PACKAGE_NAME.png" "$appdir/$PACKAGE_NAME.png"
  ln -sf "usr/share/applications/$PACKAGE_NAME.desktop" "$appdir/$PACKAGE_NAME.desktop"

  local tool
  tool="$(download_appimagetool)"
  mkdir -p "$DIST_DIR"
  ARCH="$APPIMAGE_ARCH" "$tool" "$appdir" "$DIST_DIR/$APP_NAME-$VERSION-$APPIMAGE_ARCH.AppImage"
}

write_pkgbuild() {
  local pkgdir="$1"
  local source_sha256="${SOURCE_SHA256:-SKIP}"
  mkdir -p "$pkgdir"
  cat > "$pkgdir/PKGBUILD" <<EOF
# Maintainer: appshub <appshubcc@gmail.com>
pkgname=$PACKAGE_NAME
pkgver=$VERSION
pkgrel=1
pkgdesc="Multi-platform proxy client based on Mihomo"
arch=('$PKG_ARCH')
url="https://github.com/appshubcc/Bettbox"
license=('GPL3')
depends=('gtk3' 'libayatana-appindicator' 'libkeybinder3' 'libx11' 'libxext')
options=('!strip')
source=("$PACKAGE_NAME-$VERSION.tar.gz")
sha256sums=('$source_sha256')

package() {
  cp -a "\$srcdir/pkgroot/." "\$pkgdir/"
}
EOF
}

build_arch_package() {
  require_cmd makepkg
  require_cmd sha256sum
  local root="$DIST_DIR/arch/pkgroot"
  local pkgbuild_dir="$DIST_DIR/arch/$PACKAGE_NAME"
  local source_archive="$pkgbuild_dir/$PACKAGE_NAME-$VERSION.tar.gz"
  install_tree "$root"
  rm -rf "$pkgbuild_dir"
  mkdir -p "$pkgbuild_dir"
  tar -C "$DIST_DIR/arch" -czf "$source_archive" pkgroot
  SOURCE_SHA256="$(sha256sum "$source_archive" | awk '{print $1}')"
  write_pkgbuild "$pkgbuild_dir"
  (cd "$pkgbuild_dir" && makepkg --printsrcinfo > .SRCINFO)
  (cd "$pkgbuild_dir" && makepkg -f)

  mkdir -p "$DIST_DIR/aur/$PACKAGE_NAME"
  cp "$pkgbuild_dir/PKGBUILD" "$pkgbuild_dir/.SRCINFO" "$source_archive" "$DIST_DIR/aur/$PACKAGE_NAME/"
}

prepare_bundle
mkdir -p "$DIST_DIR"

case "$TARGETS" in
  all) build_appimage; build_arch_package ;;
  appimage) build_appimage ;;
  arch) build_arch_package ;;
esac

echo "Linux packaging complete: $DIST_DIR"
