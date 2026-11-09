#!/bin/zsh
# Regenera las capturas del README (docs/*.jpg) con las vistas reales y datos de demostración.
# Abre ventanas un instante fuera de la pantalla; no toca tu configuración de Bautiza.
set -e
cd "$(dirname "$0")"
source scripts/entorno.sh

FUENTES=(${(f)"$(ls Sources/Bautiza/*.swift | grep -v '/main.swift$')"})
mkdir -p .build/capturas build/capturas
swiftc -swift-version 5 -target "$(uname -m)-apple-macosx14.0" "${EXTRA[@]}" \
  $FUENTES tools/capturas/main.swift -o .build/capturas/capturas

TRABAJO="$(mktemp -d)"
.build/capturas/capturas "$TRABAJO" build/capturas
rm -rf "$TRABAJO"

mkdir -p docs
for png in build/capturas/*.png; do
  sips -s format jpeg -s formatOptions 88 "$png" --out "docs/${${png:t}:r}.jpg" >/dev/null
done
echo "Listo: docs/*.jpg"
