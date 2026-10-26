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

mkdir -p .build/release
swiftc -O -swift-version 5 -target "$(uname -m)-apple-macosx14.0" "${EXTRA[@]}" \
  Sources/Bautiza/*.swift -o .build/release/Bautiza

APP=build/Bautiza.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Bautiza "$APP/Contents/MacOS/Bautiza"
cp Info.plist "$APP/Contents/Info.plist"
cp -R Resources/ "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
echo "Listo: $APP"
