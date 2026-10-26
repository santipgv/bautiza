# Bautiza

App de la barra de menús de macOS que vigila Descargas y renombra cada archivo nuevo
leyendo su contenido, por ejemplo: `20261026-AVON-Licitación vehículos-firmada.pdf`.

## Compilar y abrir

```bash
./build.sh
open build/Bautiza.app
```

Para que se quede, copia `build/Bautiza.app` a Aplicaciones y activa
«Abrir Bautiza al iniciar sesión» en Ajustes.

## Idioma

Español o inglés (Ajustes → General → Idioma; por defecto, el del Mac). Los textos están juntos en
el código con `L("español", "english")`. Las plantillas aceptan campos en los dos idiomas:
`{fecha}-{entidad}-{asunto}-{firmada?firmada}` o `{date}-{entity}-{subject}-{signed?signed}`.

## Probar sin renombrar nada

```bash
build/Bautiza.app/Contents/MacOS/Bautiza --probar ~/Downloads/algo.pdf
```

También se puede arrastrar un archivo a la pestaña **Probar** de Ajustes.

## Cómo decide cada dato

| Dato | De dónde sale |
|---|---|
| Fecha | Fecha del documento («En Madrid, a 26 de octubre de 2026», «Fecha: 14/10/2026»…), descartando plazos y vencimientos. Si no hay, la de descarga (configurable). |
| Entidad | Tu lista de clientes y proveedores (nombre, otros nombres, CIF). Si no está, la IA o una empresa con S.A./S.L. del texto, marcada como duda. |
| Asunto | Asunto fijo de la regla → IA de Apple → título del PDF → encabezado del documento → nombre original. |
| Firmada | Firma digital en el PDF, textos como «Firmado digitalmente por» o «DocuSign Envelope ID», o «firmado» en el nombre. |

Los PDF escaneados se leen con OCR (Vision).

## IA de Apple

Se activa sola al compilar con el SDK de macOS 26. Si Ajustes dice que se compiló sin ella:

```bash
softwareupdate --install "Command Line Tools for Xcode 26.6-26.6"
```

y vuelve a ejecutar `./build.sh`. Además hay que tener Apple Intelligence activado.

## Datos

Configuración e historial en `~/Library/Application Support/Bautiza/`.

## Código

- `FolderWatcher` – detecta archivos nuevos y espera a que termine la descarga
- `TextExtractor` – texto de PDF, OCR, Word…, web de origen
- `FieldResolver` – fecha, entidad, asunto, firma y regla
- `TemplateEngine` – plantillas `{fecha}-{entidad}-{asunto}-{firmada?firmada}`
- `LocalAI` – Apple Foundation Models
- `Processor` – aprobación, renombrado, deshacer
- `MenuViews`, `SettingsViews` – interfaz
