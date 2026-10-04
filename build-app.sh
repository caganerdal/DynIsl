#!/bin/zsh
set -e
cd "$(dirname "$0")"
swift build -c release
APP=build/DynIsl.app
VERSION=$(cat VERSION)
BUILD=$(git rev-list --count HEAD 2>/dev/null || echo 1)
SRC=$(pwd)
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/DynIsl "$APP/Contents/MacOS/"
mkdir -p "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>DynIsl</string>
  <key>CFBundleDisplayName</key><string>DynIsl</string>
  <key>CFBundleIdentifier</key><string>local.dynamicisland.demo</string>
  <key>CFBundleExecutable</key><string>DynIsl</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>DynIslSourcePath</key><string>${${SRC//&/&amp;}//</&lt;}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSCalendarsFullAccessUsageDescription</key><string>Yaklaşan toplantıları adada göstermek ve başlamadan önce haber vermek için.</string>
  <key>NSCalendarsUsageDescription</key><string>Yaklaşan toplantıları adada göstermek için.</string>
  <key>NSLocationUsageDescription</key><string>Bulunduğun yerin hava durumunu adada göstermek için (yaklaşık konum).</string>
  <key>NSLocationWhenInUseUsageDescription</key><string>Bulunduğun yerin hava durumunu adada göstermek için (yaklaşık konum).</string>
  <key>NSBluetoothAlwaysUsageDescription</key><string>Bluetooth cihazları (AirPods vb.) bağlandığında adada göstermek için.</string>
  <key>NSDesktopFolderUsageDescription</key><string>Masaüstündeki dosyaları türüne ve ayına göre klasörlere düzenlemek için.</string>
  <key>NSDownloadsFolderUsageDescription</key><string>İndirilenler klasöründe uzun süredir açılmamış dosyaları listelemek ve indirmeleri adada göstermek için.</string>
  <key>NSAppleEventsUsageDescription</key><string>Spotify ve Apple Music’te çalan şarkıyı göstermek ve kontrol etmek için.</string>
</dict></plist>
PLIST
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 -E '"(Apple Development|DynIsl)' | sed -E 's/.*"(.*)"/\1/')
SIGN_OPTS=(--force --options runtime --entitlements Resources/DynIsl.entitlements)
if [[ -n "$IDENTITY" ]]; then
  codesign "${SIGN_OPTS[@]}" --sign "$IDENTITY" "$APP"
  echo "İmza: $IDENTITY"
else
  codesign "${SIGN_OPTS[@]}" --sign - "$APP"
  echo "İmza: geçici (ad-hoc) — izinler derlemeden sonra tekrar sorulabilir"
fi
if [[ "$1" == "install" ]]; then
  DEST=/Applications/DynIsl.app
  pkill -x DynIsl && sleep 0.5 || true
  rm -rf "$DEST"
  ditto "$APP" "$DEST"
  echo "Kuruldu: $DEST"
  mkdir -p "$HOME/.local/bin"
  LINK="$HOME/.local/bin/island"
  if [[ ! -e "$LINK" && ! -L "$LINK" ]] || [[ "$(readlink "$LINK")" == *"/DynIsl.app/"* ]]; then
    ln -sf "$DEST/Contents/MacOS/DynIsl" "$LINK"
    echo "Komut: island  (~/.local/bin/island)"
  else
    echo "Uyarı: ~/.local/bin/island zaten başka bir dosya, dokunulmadı"
  fi
  open "$DEST"
else
  echo "Hazır: $APP  (açmak için: open $APP)"
fi
