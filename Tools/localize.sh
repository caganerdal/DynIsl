#!/bin/zsh
set -e
cd "$(dirname "$0")/.."
CATALOG=Resources/Localizable.xcstrings
TMP=$(mktemp -d)
swift build -c release -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$TMP" >/dev/null
[[ -f $CATALOG ]] || echo '{"sourceLanguage":"tr","strings":{},"version":"1.0"}' > $CATALOG
xcrun xcstringstool sync $CATALOG --stringsdata "$TMP"/*.stringsdata --skip-marking-strings-stale
xcrun xcstringstool compile $CATALOG --output-directory Resources/Localizations --language en
rm -r "$TMP"
echo "Güncellendi: $CATALOG ve Resources/Localizations/en.lproj"
