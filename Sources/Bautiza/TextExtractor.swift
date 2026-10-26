import AppKit
import Foundation
import PDFKit
import Vision

struct ContenidoDocumento {
    var texto = ""
    var titulo: String?
    var firmaDigital = false
    var ocr = false
    /// URLs de las que se descargó (las guarda macOS en los atributos del archivo).
    var origenes: [String] = []
    var fechaDescarga = Date()
}

/// Saca el texto de PDF, imágenes (OCR) y documentos de texto.
enum TextExtractor {
    static let extensionesImagen: Set<String> = ["png", "jpg", "jpeg", "heic", "tif", "tiff", "gif", "bmp", "webp"]
    static let extensionesTexto: Set<String> = ["txt", "rtf", "rtfd", "doc", "docx", "odt", "html", "htm", "md", "csv", "webarchive"]

    static func extraer(_ url: URL) -> ContenidoDocumento {
        var c = ContenidoDocumento()
        c.origenes = origenes(de: url)
        let valores = try? url.resourceValues(forKeys: [.addedToDirectoryDateKey, .creationDateKey])
        c.fechaDescarga = valores?.addedToDirectoryDate ?? valores?.creationDate ?? Date()

        let ext = url.pathExtension.lowercased()
        if ext == "pdf" {
            leerPDF(url, &c)
        } else if extensionesImagen.contains(ext) {
            if let imagen = NSImage(contentsOf: url),
               let cg = imagen.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                c.texto = reconocerTexto(cg)
                c.ocr = true
            }
        } else if ["xlsx", "xlsm"].contains(ext) {
            c.texto = textoDeZip(url, ["xl/sharedStrings.xml", "docProps/core.xml"])
        } else if ext == "pptx" {
            c.texto = textoDeZip(url, ["ppt/slides/slide*.xml", "docProps/core.xml"])
        } else if ["ods", "odp"].contains(ext) {
            c.texto = textoDeZip(url, ["content.xml"])
        } else if extensionesTexto.contains(ext) {
            if let s = try? NSAttributedString(url: url, options: [:], documentAttributes: nil) {
                c.texto = s.string
            }
        }
        return c
    }

    /// Los formatos de Office modernos son ZIP con XML dentro: sacamos el texto de las etiquetas.
    private static func textoDeZip(_ url: URL, _ partes: [String]) -> String {
        let proceso = Process()
        proceso.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        proceso.arguments = ["-p", url.path] + partes
        let salida = Pipe()
        proceso.standardOutput = salida
        proceso.standardError = FileHandle.nullDevice
        guard (try? proceso.run()) != nil else { return "" }
        let data = salida.fileHandleForReading.readDataToEndOfFile()
        proceso.waitUntilExit()
        let xml = String(decoding: data.prefix(2_000_000), as: UTF8.self)
        let texto = xml
            .replacingOccurrences(of: #"</(a:p|w:p|si|text:p|row)>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
        return texto.split(whereSeparator: \.isNewline)
            .map { $0.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression).recortado }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func leerPDF(_ url: URL, _ c: inout ContenidoDocumento) {
        guard let doc = PDFDocument(url: url) else { return }
        c.titulo = doc.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String

        var partes: [String] = []
        for i in 0..<min(doc.pageCount, 30) {
            if let s = doc.page(at: i)?.string { partes.append(s) }
        }
        c.texto = partes.joined(separator: "\n")

        // Sin texto seleccionable: es un escaneado, toca OCR de las primeras páginas y la última.
        if c.texto.recortado.count < 40 {
            var paginas = Array(0..<min(doc.pageCount, 3))
            if doc.pageCount > 3 { paginas.append(doc.pageCount - 1) }
            c.texto = paginas.compactMap { doc.page(at: $0) }.map(ocr).joined(separator: "\n")
            c.ocr = true
        }

        // Un PDF firmado digitalmente lleva un diccionario de firma con /ByteRange.
        if let data = try? Data(contentsOf: url, options: .alwaysMapped) {
            c.firmaDigital = data.range(of: Data("/ByteRange".utf8)) != nil
        }
    }

    private static func ocr(_ pagina: PDFPage) -> String {
        let caja = pagina.bounds(for: .mediaBox)
        let escala = 2200 / max(caja.width, caja.height, 1)
        let imagen = pagina.thumbnail(of: CGSize(width: caja.width * escala, height: caja.height * escala), for: .mediaBox)
        guard let cg = imagen.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return "" }
        return reconocerTexto(cg)
    }

    static func reconocerTexto(_ imagen: CGImage) -> String {
        let peticion = VNRecognizeTextRequest()
        peticion.recognitionLevel = .accurate
        peticion.recognitionLanguages = ["es-ES", "en-US"]
        peticion.usesLanguageCorrection = true
        try? VNImageRequestHandler(cgImage: imagen).perform([peticion])
        return (peticion.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    static func origenes(de url: URL) -> [String] {
        let atributo = "com.apple.metadata:kMDItemWhereFroms"
        let tamaño = getxattr(url.path, atributo, nil, 0, 0, 0)
        guard tamaño > 0 else { return [] }
        var data = Data(count: tamaño)
        let leido = data.withUnsafeMutableBytes { getxattr(url.path, atributo, $0.baseAddress, tamaño, 0, 0) }
        guard leido > 0,
              let lista = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String] else { return [] }
        return lista
    }
}
