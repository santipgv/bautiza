import Foundation

/// Vigila una carpeta y avisa de cada archivo nuevo cuando termina de descargarse.
final class FolderWatcher {
    /// Extensiones de descargas a medias (Chrome, Safari, Firefox…).
    static let temporales: Set<String> = ["crdownload", "download", "part", "partial", "tmp", "opdownload"]

    private let carpeta: URL
    private let alDetectar: (URL) -> Void
    private var fuente: DispatchSourceFileSystemObject?
    private var temporizador: Timer?
    private var conocidos: Set<String> = []
    private var enEspera: Set<String> = []

    init(carpeta: URL, alDetectar: @escaping (URL) -> Void) {
        self.carpeta = carpeta
        self.alDetectar = alDetectar
    }

    func iniciar() {
        conocidos = Set(listar())
        let fd = open(carpeta.path, O_EVTONLY)
        if fd >= 0 {
            let s = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .link], queue: .main)
            s.setEventHandler { [weak self] in self?.revisar() }
            s.setCancelHandler { close(fd) }
            s.resume()
            fuente = s
        }
        // Red de seguridad por si algún cambio no genera evento.
        temporizador = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.revisar() }
    }

    func detener() {
        fuente?.cancel()
        fuente = nil
        temporizador?.invalidate()
        temporizador = nil
    }

    private func listar() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: carpeta.path)) ?? []
    }

    private func revisar() {
        let actuales = Set(listar())
        let nuevos = actuales.subtracting(conocidos)
        conocidos = actuales
        for nombre in nuevos where esCandidato(nombre) && !enEspera.contains(nombre) {
            enEspera.insert(nombre)
            esperarEstable(carpeta.appendingPathComponent(nombre), tamañoPrevio: -1, intentos: 0)
        }
    }

    private func esCandidato(_ nombre: String) -> Bool {
        guard !nombre.hasPrefix("."),
              !FolderWatcher.temporales.contains((nombre as NSString).pathExtension.lowercased()) else { return false }
        var esCarpeta: ObjCBool = false
        let ruta = carpeta.appendingPathComponent(nombre).path
        return FileManager.default.fileExists(atPath: ruta, isDirectory: &esCarpeta) && !esCarpeta.boolValue
    }

    /// Espera a que el tamaño deje de cambiar antes de tocar el archivo.
    private func esperarEstable(_ url: URL, tamañoPrevio: Int, intentos: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            let nombre = url.lastPathComponent
            guard let atributos = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let tamaño = (atributos[.size] as? NSNumber)?.intValue else {
                self.enEspera.remove(nombre) // desapareció (renombrado o borrado)
                return
            }
            if tamaño > 0, tamaño == tamañoPrevio {
                self.enEspera.remove(nombre)
                if self.esReciente(url) { self.alDetectar(url) }
            } else if intentos < 400 {
                self.esperarEstable(url, tamañoPrevio: tamaño, intentos: intentos + 1)
            } else {
                self.enEspera.remove(nombre)
            }
        }
    }

    /// Un archivo que solo se ha renombrado a mano conserva su fecha de llegada: no lo tocamos.
    private func esReciente(_ url: URL) -> Bool {
        let v = try? url.resourceValues(forKeys: [.addedToDirectoryDateKey, .creationDateKey])
        guard let llegada = v?.addedToDirectoryDate ?? v?.creationDate else { return true }
        return Date().timeIntervalSince(llegada) < 15 * 60
    }
}
