#!/bin/zsh
# Buduje Stosik.app i wkłada do ~/Applications.   ./zbuduj.sh        ./zbuduj.sh --tylko-buduj
set -e
cd "${0:A:h}"
B=build; A="$B/Stosik.app"
rm -rf "$B"; mkdir -p "$A/Contents/MacOS" "$A/Contents/Resources" "$B/ikona.iconset"
# jedna apka dla Maców z Apple Silicon i z Intelem
swiftc -swift-version 5 -O -target arm64-apple-macos14.0 Sources/*.swift -o "$B/Stosik-arm64"
swiftc -swift-version 5 -O -target x86_64-apple-macos14.0 Sources/*.swift -o "$B/Stosik-x86_64"
lipo -create "$B/Stosik-arm64" "$B/Stosik-x86_64" -o "$A/Contents/MacOS/Stosik"
rm "$B/Stosik-arm64" "$B/Stosik-x86_64"
STOSIK_ICON="$B/ikona.png" "$A/Contents/MacOS/Stosik"
for s in 16 32 128 256 512; do
  sips -z $s $s "$B/ikona.png" --out "$B/ikona.iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$B/ikona.png" --out "$B/ikona.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$B/ikona.iconset" -o "$A/Contents/Resources/ikona.icns"
# nazwa apki w Finderze i powiadomieniach: po polsku Stosik, po angielsku Stackie
mkdir -p "$A/Contents/Resources/pl.lproj" "$A/Contents/Resources/en.lproj"
printf '"CFBundleDisplayName" = "Stosik";\n"CFBundleName" = "Stosik";\n' > "$A/Contents/Resources/pl.lproj/InfoPlist.strings"
cat > "$A/Contents/Resources/en.lproj/InfoPlist.strings" <<'S'
"CFBundleDisplayName" = "Stackie";
"CFBundleName" = "Stackie";
"NSMicrophoneUsageDescription" = "Stackie only listens while you dictate tasks.";
"NSSpeechRecognitionUsageDescription" = "Stackie turns your dictated tasks into text.";
S
cat > "$A/Contents/Info.plist" <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>pl.stosik.app</string>
<key>CFBundleName</key><string>Stosik</string>
<key>CFBundleDisplayName</key><string>Stosik</string>
<key>CFBundleExecutable</key><string>Stosik</string>
<key>CFBundleIconFile</key><string>ikona</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>CFBundleDevelopmentRegion</key><string>pl</string>
<key>CFBundleLocalizations</key><array><string>pl</string><string>en</string></array>
<key>NSMicrophoneUsageDescription</key><string>Stosik słucha tylko wtedy, gdy dyktujesz zadania.</string>
<key>NSSpeechRecognitionUsageDescription</key><string>Stosik zamienia podyktowane zadania na tekst.</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
P
ID=$(security find-identity -v -p codesigning | awk 'NR==1{print $2}')
codesign --force --sign "${ID:--}" "$A" 2>/dev/null || codesign --force --sign - "$A"
[[ "$1" == "--tylko-buduj" ]] && exit 0
mkdir -p ~/Applications
pkill -x Stosik 2>/dev/null && sleep 1 || true
rm -rf ~/Applications/Stosik.app
ditto "$A" ~/Applications/Stosik.app
open ~/Applications/Stosik.app
