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
cp -R Resources/Localizations/*.lproj "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>DynIsl</string>
  <key>CFBundleDevelopmentRegion</key><string>tr</string>
  <key>CFBundleLocalizations</key><array><string>tr</string><string>en</string></array>
  <key>CFBundleDisplayName</key><string>DynIsl</string>
  <key>CFBundleIdentifier</key><string>local.dynamicisland.demo</string>
  <key>CFBundleExecutable</key><string>DynIsl</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
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
if [[ "$1" != "dmg" ]]; then
  /usr/libexec/PlistBuddy -c "Add :DynIslSourcePath string $SRC" "$APP/Contents/Info.plist"
fi
LOCAL_ID="DynIsl Local"
make_local_identity() {
  local tmp=$(mktemp -d)
  printf '[req]\ndistinguished_name=dn\nprompt=no\n[dn]\nCN=%s\n[ext]\nbasicConstraints=critical,CA:false\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=critical,codeSigning\n' "$LOCAL_ID" > "$tmp/c.cnf"
  openssl req -x509 -newkey rsa:2048 -nodes -keyout "$tmp/k.pem" -out "$tmp/c.pem" -days 3650 -config "$tmp/c.cnf" -extensions ext >/dev/null 2>&1 &&
  { openssl pkcs12 -export -inkey "$tmp/k.pem" -in "$tmp/c.pem" -out "$tmp/id.p12" -passout pass:dynisl -legacy >/dev/null 2>&1 ||
    openssl pkcs12 -export -inkey "$tmp/k.pem" -in "$tmp/c.pem" -out "$tmp/id.p12" -passout pass:dynisl >/dev/null 2>&1; } &&
  security import "$tmp/id.p12" -P dynisl >/dev/null 2>&1
  local ok=$?
  rm -rf "$tmp"
  return $ok
}
if [[ "$1" == "dmg" ]]; then
  IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 '"Developer ID Application' | sed -E 's/.*"(.*)"/\1/')
  if [[ -z "$IDENTITY" ]]; then
    echo "Developer ID Application sertifikası bulunamadı. Xcode › Settings › Accounts › Manage Certificates › + › Developer ID Application"
    exit 1
  fi
  codesign --force --options runtime --timestamp --entitlements Resources/DynIsl.entitlements --sign "$IDENTITY" "$APP"
  echo "İmza: $IDENTITY"
  DMG="build/DynIsl-$VERSION.dmg"
  STAGE=$(mktemp -d)
  ditto "$APP" "$STAGE/DynIsl.app"
  ln -s /Applications "$STAGE/Applications"
  rm -f "$DMG"
  hdiutil create -volname "DynIsl $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
  rm -rf "$STAGE"
  codesign --force --timestamp --sign "$IDENTITY" "$DMG"
  echo "Apple onayına gönderiliyor (birkaç dakika sürebilir)…"
  xcrun notarytool submit "$DMG" --keychain-profile DynIsl --wait
  xcrun stapler staple "$DMG"
  spctl -a -t open --context context:primary-signature -v "$DMG"
  echo "Hazır: $DMG"
  exit 0
fi
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 '"Apple Development' | sed -E 's/.*"(.*)"/\1/')
if [[ -z "$IDENTITY" ]]; then
  if ! security find-identity -p codesigning 2>/dev/null | grep -q "\"$LOCAL_ID\""; then
    echo "İlk kurulum: izinlerin güncellemelerden sonra korunması için yerel imza sertifikası oluşturuluyor…"
    make_local_identity || true
  fi
  security find-identity -p codesigning 2>/dev/null | grep -q "\"$LOCAL_ID\"" && IDENTITY="$LOCAL_ID"
fi
SIGN_OPTS=(--force --options runtime --entitlements Resources/DynIsl.entitlements)
if [[ -n "$IDENTITY" ]] && codesign "${SIGN_OPTS[@]}" --sign "$IDENTITY" "$APP" 2>/dev/null; then
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
  LINK="$HOME/.local/bin/island"
  if [[ -L "$LINK" && "$(readlink "$LINK")" == *"/DynIsl.app/"* ]]; then
    rm "$LINK"
    echo "Kaldırıldı: eski island komutu (~/.local/bin/island)"
  fi
  open "$DEST"
else
  echo "Hazır: $APP  (açmak için: open $APP)"
fi
