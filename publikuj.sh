#!/bin/zsh
# Podpisana i znotaryzowana apka do wysłania innym: build/Stackie-<wersja>.zip
# Wymaga: certyfikatu „Developer ID Application” w pęku kluczy i profilu notarytool „stackie”
# (jednorazowo: xcrun notarytool store-credentials stackie --apple-id <mail> --team-id <TEAM>).
#   ./publikuj.sh            podpis + notaryzacja + zip
#   ./publikuj.sh --github   to samo i nowe wydanie na GitHubie (woreczko/stackie)
set -e
cd "${0:A:h}"
VER=$(sed -n 's/^let APP_VERSION = "\(.*\)"/\1/p' Sources/Welcome.swift)
ID=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)
[[ -z "$ID" ]] && { echo "Brak certyfikatu „Developer ID Application” w pęku kluczy."; exit 1; }
./zbuduj.sh --tylko-buduj
A=build/Stosik.app
echo "Podpisuję: $ID"
codesign --force --options runtime --timestamp --entitlements Stosik.entitlements --sign "$ID" "$A"
codesign --verify --strict --verbose=2 "$A"
ZIP=build/Stackie-$VER.zip
rm -f "$ZIP"; ditto -c -k --keepParent "$A" "$ZIP"
echo "Wysyłam do Apple (notaryzacja, zwykle 1–5 minut)…"
xcrun notarytool submit "$ZIP" --keychain-profile stackie --wait
xcrun stapler staple "$A"
spctl --assess --type execute --verbose "$A"
rm -f "$ZIP"; ditto -c -k --keepParent "$A" "$ZIP"
echo "Gotowe: $ZIP"
if [[ "$1" == "--github" ]]; then
  gh release create "v$VER" "$ZIP" --repo woreczko/stackie --target main --title "Stackie $VER" --notes-file "wersje/notatki-$VER.md"
fi
