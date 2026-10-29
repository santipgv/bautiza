#!/bin/zsh
# Compila Bautiza y crea build/Bautiza.app
set -e
cd "$(dirname "$0")"

# Algunas instalaciones de Command Line Tools traen un module.modulemap antiguo
# que choca con el nuevo; lo ocultamos solo para esta compilación.
EXTRA=()
VIEJO=/Library/Developer/CommandLineTools/usr/include/swift/module.modulemap
if [[ -f $VIEJO && -f ${VIEJO:h}/bridging.modulemap ]]; then
  mkdir -p compat
  : > compat/vacio.modulemap
  cat > compat/overlay.yaml <<YAML
{ "version": 0, "case-sensitive": "false", "roots": [{ "type": "directory", "name": "${VIEJO:h}",
  "contents": [{ "type": "file", "name": "module.modulemap", "external-contents": "$PWD/compat/vacio.modulemap" }] }] }
YAML
  EXTRA=(-vfsoverlay compat/overlay.yaml -Xcc -ivfsoverlay -Xcc compat/overlay.yaml)
fi

# Binario universal: Apple Silicon e Intel.
mkdir -p .build/release
for ARQ in arm64 x86_64; do
  swiftc -O -swift-version 5 -target "$ARQ-apple-macosx14.0" "${EXTRA[@]}" \
    Sources/Bautiza/*.swift -o .build/release/Bautiza-$ARQ
done
lipo -create .build/release/Bautiza-arm64 .build/release/Bautiza-x86_64 -output .build/release/Bautiza

APP=build/Bautiza.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Bautiza "$APP/Contents/MacOS/Bautiza"
cp Info.plist "$APP/Contents/Info.plist"
cp -R Resources/ "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
echo "Listo: $APP"

if [[ "$1" == "--zip" ]]; then
  ditto -c -k --keepParent "$APP" build/Bautiza.zip
  echo "Listo: build/Bautiza.zip"
fi
