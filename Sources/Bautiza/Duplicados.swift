import CryptoKit
import Foundation

/// Busca un archivo idéntico (mismo contenido) al recién descargado.
enum Duplicados {
    static func buscar(_ url: URL, en carpetas: [URL]) -> URL? {
        guard let tamaño = tamaño(url), tamaño > 0 else { return nil }
        var huella: SHA256.Digest?
        let propio = url.standardizedFileURL.path
        var vistas = Set<String>()
        for carpeta in carpetas where vistas.insert(carpeta.standardizedFileURL.path).inserted {
            let contenido = (try? FileManager.default.contentsOfDirectory(
                at: carpeta, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])) ?? []
            for otro in contenido where otro.standardizedFileURL.path != propio && self.tamaño(otro) == tamaño {
                // Solo calculamos huellas cuando el tamaño coincide.
                if huella == nil { huella = calcularHuella(url) }
                if let huella, calcularHuella(otro) == huella { return otro }
            }
        }
        return nil
    }

    private static func tamaño(_ url: URL) -> Int? {
        try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
    }

    private static func calcularHuella(_ url: URL) -> SHA256.Digest? {
        guard let lector = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? lector.close() }
        var hash = SHA256()
        while let bloque = try? lector.read(upToCount: 1 << 20), !bloque.isEmpty {
            hash.update(data: bloque)
        }
        return hash.finalize()
    }
}
