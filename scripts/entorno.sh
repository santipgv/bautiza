# Banderas comunes de swiftc para build.sh y test.sh (se carga con `source`).
#
# Algunas instalaciones de Command Line Tools traen un module.modulemap antiguo
# que choca con el nuevo; lo ocultamos solo para la compilación.
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
