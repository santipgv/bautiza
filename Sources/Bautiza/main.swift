import Foundation

// Modo prueba desde Terminal: Bautiza --probar archivo.pdf [más archivos…]
// Muestra el nombre que propondría sin tocar nada.
let argumentos = CommandLine.arguments
if argumentos.count >= 3, argumentos[1] == "--probar" {
    final class Caja: @unchecked Sendable { var propuesta: Propuesta? }
    let conf = Store.leerConfiguracion()
    Loc.aplicar(conf.ajustes.idioma)
    print("IA: \(LocalAI.estado)\n")
    for ruta in argumentos.dropFirst(2) {
        let url = URL(fileURLWithPath: ruta)
        let caja = Caja()
        let listo = DispatchSemaphore(value: 0)
        Task.detached {
            caja.propuesta = await FieldResolver.analizar(url, conf)
            listo.signal()
        }
        listo.wait()
        guard let p = caja.propuesta else { continue }
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy"
        print("""
            \(url.lastPathComponent)
              → \(p.nombre)
              fecha:   \(p.fecha.map(f.string) ?? "—") (\(p.fechaOrigen))
              entidad: \(p.entidad ?? "—") (\(p.entidadOrigen))
              asunto:  \(p.asunto ?? "—") (\(p.asuntoOrigen))
              firmada: \(p.firmada ? "sí" : "no") (\(p.firmaOrigen))
              regla:   \(p.regla ?? "por defecto")\(p.ocr ? "  · OCR" : "")\(p.usoIA ? "  · IA" : "")
              carpeta: \(p.carpetaDestino.path)
            """)
        for d in p.dudas { print("  ⚠︎ \(d)") }
        print()
    }
    exit(0)
}

BautizaApp.main()
