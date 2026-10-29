import Foundation

/// De dónde viene un archivo a analizar.
enum Origen {
    /// Lo ha detectado la vigilancia: puede renombrarse solo según el modo.
    case vigilancia
    /// Lo ha elegido el usuario: siempre se le enseña la propuesta.
    case manual
    /// Estaba pendiente al cerrar la app: vuelve a la lista sin avisar.
    case recuperado
}

/// Coordina análisis, aprobación, renombrado y deshacer.
@MainActor
final class Processor: ObservableObject {
    @Published var pendientes: [Propuesta] = [] { didSet { guardarPendientes() } }
    @Published var analizando: Set<String> = []
    @Published var ultimoError: String?

    let store: Store
    var notifier: Notifier?
    /// Rutas que hemos creado nosotros, para no volver a procesarlas.
    private var rutasPropias: Set<String> = []

    init(store: Store) {
        self.store = store
    }

    func nuevoArchivo(_ url: URL) {
        guard !store.ajustes.pausado,
              let tipo = TipoArchivo.de(url.pathExtension),
              store.ajustes.tiposVigilados.contains(tipo) else { return }
        let ruta = url.standardizedFileURL.path
        guard !rutasPropias.contains(ruta),
              !analizando.contains(ruta),
              !pendientes.contains(where: { $0.url.standardizedFileURL.path == ruta }) else { return }
        analizar(url, origen: .vigilancia)
    }

    func analizar(_ url: URL, origen: Origen) {
        let ruta = url.standardizedFileURL.path
        analizando.insert(ruta)
        let conf = store.configuracion
        let dondeBuscar = carpetasParaDuplicados(de: url)
        Task {
            let propuesta = await Task.detached { () -> Propuesta in
                var p = await FieldResolver.analizar(url, conf)
                if let copia = Duplicados.buscar(url, en: dondeBuscar) {
                    p.duplicadoDe = copia
                    p.dudas.insert(L("Ya tienes este archivo: «\(copia.lastPathComponent)»",
                                     "You already have this file: “\(copia.lastPathComponent)”"), at: 0)
                }
                return p
            }.value
            analizando.remove(ruta)
            decidir(propuesta, origen: origen)
        }
    }

    /// La carpeta del archivo, las vigiladas y aquellas a las que se movieron archivos renombrados.
    private func carpetasParaDuplicados(de url: URL) -> [URL] {
        let movidas = store.historial.prefix(300).filter { !$0.deshecho }
            .map { URL(fileURLWithPath: $0.nuevo).deletingLastPathComponent() }
        let vigiladas = store.ajustes.carpetas.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
        return [url.deletingLastPathComponent()] + vigiladas + movidas
    }

    private func decidir(_ p: Propuesta, origen: Origen) {
        let automatico: Bool
        switch origen {
        case .vigilancia:
            if p.nombre == p.url.lastPathComponent, !p.mueveDeCarpeta, p.duplicadoDe == nil { return }
            let modo = store.ajustes.modo
            // Un duplicado siempre se pregunta: puede que quieras tirarlo en vez de renombrarlo.
            automatico = p.duplicadoDe == nil
                && (modo == .automatico || (modo == .confirmarSiDudas && p.dudas.isEmpty))
        case .manual, .recuperado:
            automatico = false
        }
        if automatico {
            if let destino = aplicar(p, nombre: p.nombre) {
                notifier?.avisar(L("Renombrado", "Renamed"), destino.lastPathComponent)
            }
        } else {
            pendientes.removeAll { $0.url.standardizedFileURL.path == p.url.standardizedFileURL.path }
            pendientes.append(p)
            switch origen {
            case .manual: Ventanas.shared.mostrarPendientes()
            case .vigilancia: notifier?.proponer(p)
            case .recuperado: break
            }
        }
    }

    @discardableResult
    func aplicar(_ p: Propuesta, nombre: String) -> URL? {
        let fm = FileManager.default
        var limpio = TemplateEngine.sanear(nombre).recortado
        let ext = p.url.pathExtension
        if !ext.isEmpty, (limpio as NSString).pathExtension.lowercased() != ext.lowercased() {
            limpio += ".\(ext.lowercased())"
        }
        do {
            try fm.createDirectory(at: p.carpetaDestino, withIntermediateDirectories: true)
            let destino = rutaLibre(p.carpetaDestino.appendingPathComponent(limpio), origen: p.url)
            rutasPropias.insert(destino.standardizedFileURL.path)
            if destino.standardizedFileURL.path != p.url.standardizedFileURL.path {
                try fm.moveItem(at: p.url, to: destino)
                store.historial.insert(HistoryEntry(original: p.url.path, nuevo: destino.path), at: 0)
            }
            quitar(p)
            ultimoError = nil
            return destino
        } catch {
            ultimoError = L("No se pudo renombrar «\(p.url.lastPathComponent)»", "Couldn't rename “\(p.url.lastPathComponent)”") + ": \(error.localizedDescription)"
            return nil
        }
    }

    /// Manda el duplicado a la Papelera (se puede recuperar desde allí).
    func tirarDuplicado(_ p: Propuesta) {
        do {
            try FileManager.default.trashItem(at: p.url, resultingItemURL: nil)
            quitar(p)
        } catch {
            ultimoError = L("No se pudo mover a la Papelera", "Couldn't move to the Trash") + ": \(error.localizedDescription)"
        }
    }

    /// Añade a tu lista la entidad que se encontró en el texto y vuelve a analizar los pendientes.
    func añadirEntidad(_ nombre: String, tipo: EntityKind) {
        guard !store.entidades.contains(where: { Texto.normalizar($0.nombre) == Texto.normalizar(nombre) }) else { return }
        store.entidades.append(Entity(nombre: nombre, tipo: tipo))
        reanalizarPendientes()
    }

    func reanalizarPendientes() {
        for p in pendientes { analizar(p.url, origen: .recuperado) }
    }

    // MARK: - Pendientes entre sesiones

    private func guardarPendientes() {
        let rutas = pendientes.map(\.url.path)
        try? FileManager.default.createDirectory(at: Store.carpetaDatos, withIntermediateDirectories: true)
        if let data = try? JSONEncoder.bautiza.encode(rutas) {
            try? data.write(to: Store.rutaPendientes, options: .atomic)
        }
    }

    /// Vuelve a poner en la lista lo que quedó sin aprobar la última vez.
    func recuperarPendientes() {
        guard let data = try? Data(contentsOf: Store.rutaPendientes),
              let rutas = try? JSONDecoder.bautiza.decode([String].self, from: data) else { return }
        for ruta in rutas where FileManager.default.fileExists(atPath: ruta) {
            analizar(URL(fileURLWithPath: ruta), origen: .recuperado)
        }
    }

    func ignorar(_ p: Propuesta) {
        rutasPropias.insert(p.url.standardizedFileURL.path)
        quitar(p)
    }

    func deshacer(_ e: HistoryEntry) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: e.nuevo) else {
            ultimoError = L("«\(e.nombreNuevo)» ya no está en su sitio", "“\(e.nombreNuevo)” is no longer there")
            return
        }
        let original = rutaLibre(URL(fileURLWithPath: e.original), origen: URL(fileURLWithPath: e.nuevo))
        rutasPropias.insert(original.standardizedFileURL.path)
        do {
            try fm.moveItem(atPath: e.nuevo, toPath: original.path)
            if let i = store.historial.firstIndex(where: { $0.id == e.id }) { store.historial[i].deshecho = true }
        } catch {
            ultimoError = L("No se pudo deshacer", "Couldn't undo") + ": \(error.localizedDescription)"
        }
    }

    private func quitar(_ p: Propuesta) {
        pendientes.removeAll { $0.id == p.id }
        notifier?.retirar(p.id)
    }

    /// Si el nombre ya existe añade -2, -3…
    private func rutaLibre(_ url: URL, origen: URL) -> URL {
        let fm = FileManager.default
        if url.standardizedFileURL.path == origen.standardizedFileURL.path || !fm.fileExists(atPath: url.path) { return url }
        let carpeta = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var n = 2
        while true {
            let candidato = carpeta.appendingPathComponent(ext.isEmpty ? "\(base)-\(n)" : "\(base)-\(n).\(ext)")
            if !fm.fileExists(atPath: candidato.path) { return candidato }
            n += 1
        }
    }
}
