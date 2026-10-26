import Foundation

/// Coordina análisis, aprobación, renombrado y deshacer.
@MainActor
final class Processor: ObservableObject {
    @Published var pendientes: [Propuesta] = []
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
        analizar(url, manual: false)
    }

    /// `manual`: el usuario lo eligió desde el menú; siempre se le enseña la propuesta.
    func analizar(_ url: URL, manual: Bool) {
        let ruta = url.standardizedFileURL.path
        analizando.insert(ruta)
        let conf = store.configuracion
        Task {
            let propuesta = await Task.detached { await FieldResolver.analizar(url, conf) }.value
            analizando.remove(ruta)
            decidir(propuesta, manual: manual)
        }
    }

    private func decidir(_ p: Propuesta, manual: Bool) {
        if !manual, p.nombre == p.url.lastPathComponent, !p.mueveDeCarpeta { return }
        let modo = store.ajustes.modo
        let automatico = !manual && (modo == .automatico || (modo == .confirmarSiDudas && p.dudas.isEmpty))
        if automatico {
            if let destino = aplicar(p, nombre: p.nombre) {
                notifier?.avisar(L("Renombrado", "Renamed"), destino.lastPathComponent)
            }
        } else {
            pendientes.append(p)
            if manual {
                Ventanas.shared.mostrarPendientes()
            } else {
                notifier?.proponer(p)
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
