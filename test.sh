#!/bin/zsh
# Compila y ejecuta las pruebas de Tests/ junto con el código de la app (sin su main.swift).
set -e
cd "$(dirname "$0")"
source scripts/entorno.sh

FUENTES=(${(f)"$(ls Sources/Bautiza/*.swift | grep -v '/main.swift$')"})
mkdir -p .build/tests
swiftc -swift-version 5 -target "$(uname -m)-apple-macosx14.0" "${EXTRA[@]}" \
  $FUENTES Tests/*.swift -o .build/tests/pruebas
BAUTIZA_DATOS="$(mktemp -d)" .build/tests/pruebas
