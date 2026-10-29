import Foundation

enum ApprovalMode: String, Codable, CaseIterable, Identifiable {
    case siempreConfirmar, confirmarSiDudas, automatico
    var id: String { rawValue }
    var titulo: String {
        switch self {
        case .siempreConfirmar: return L("Pedir aprobación siempre", "Always ask for approval")
        case .confirmarSiDudas: return L("Pedir aprobación solo si hay dudas", "Ask only when unsure")
        case .automatico: return L("Renombrar automáticamente", "Rename automatically")
        }
    }
}

enum DateSource: String, Codable, CaseIterable, Identifiable {
    case documentoOdescarga, soloDocumento, soloDescarga
    var id: String { rawValue }
    var titulo: String {
        switch self {
        case .documentoOdescarga: return L("Fecha del documento (si no hay, la de descarga)", "Document date (download date if none)")
        case .soloDocumento: return L("Solo la fecha del documento", "Document date only")
        case .soloDescarga: return L("Solo la fecha de descarga", "Download date only")
        }
    }
}

/// Familias de archivos que se pueden activar o desactivar en Ajustes.
enum TipoArchivo: String, Codable, CaseIterable, Identifiable {
    case pdf, word, excel, powerpoint, imagen, texto
    var id: String { rawValue }
    var titulo: String {
        switch self {
        case .pdf: return "PDF"
        case .word: return L("Word y documentos", "Word and documents")
        case .excel: return L("Excel y hojas de cálculo", "Excel and spreadsheets")
        case .powerpoint: return L("PowerPoint y presentaciones", "PowerPoint and presentations")
        case .imagen: return L("Imágenes (JPG, PNG, HEIC…)", "Images (JPG, PNG, HEIC…)")
        case .texto: return L("Texto (TXT, CSV, HTML…)", "Text (TXT, CSV, HTML…)")
        }
    }
    var extensiones: Set<String> {
        switch self {
        case .pdf: return ["pdf"]
        case .word: return ["doc", "docx", "odt", "rtf", "pages"]
        case .excel: return ["xls", "xlsx", "xlsm", "ods", "numbers"]
        case .powerpoint: return ["ppt", "pptx", "odp", "key"]
        case .imagen: return ["jpg", "jpeg", "png", "heic", "tif", "tiff", "gif", "webp"]
        case .texto: return ["txt", "md", "csv", "html", "htm"]
        }
    }
    static func de(_ ext: String) -> TipoArchivo? {
        allCases.first { $0.extensiones.contains(ext.lowercased()) }
    }
}

/// Qué hace una regla con la entidad.
enum ModoEntidad: String, Codable, CaseIterable, Identifiable {
    case deducir, vacia, fija
    var id: String { rawValue }
    var titulo: String {
        switch self {
        case .deducir: return L("Deducirla del documento", "Work it out from the document")
        case .vacia: return L("Dejarla en blanco (documento personal)", "Leave it blank (personal document)")
        case .fija: return L("Usar siempre este texto", "Always use this text")
        }
    }
}

enum EntityKind: String, Codable, CaseIterable, Identifiable {
    case cliente, proveedor, otro
    var id: String { rawValue }
    var titulo: String {
        switch self {
        case .cliente: return L("Cliente", "Client")
        case .proveedor: return L("Proveedor", "Supplier")
        case .otro: return L("Otro", "Other")
        }
    }
}

/// Cliente, proveedor u otra organización que puede aparecer en los documentos.
struct Entity: Codable, Identifiable, Hashable {
    var id = UUID()
    /// Cómo aparece en el nombre del archivo, p. ej. "AVON".
    var nombre: String
    /// Otras formas en que aparece en los documentos, p. ej. "Avon Cosmetics S.A.".
    var alias: [String] = []
    var cif: String = ""
    var tipo: EntityKind = .cliente
}

/// "Cuando pase X, usa esta plantilla y esta carpeta". Gana la primera que encaje.
struct Rule: Codable, Identifiable, Hashable {
    var id = UUID()
    var nombre: String
    var activa = true
    /// Vacío = cualquier tipo de archivo.
    var extensiones: [String] = []
    /// Vacío = no se exige; si hay varias basta con que aparezca una.
    var palabrasClave: [String] = []
    var tipoEntidad: EntityKind? = nil
    /// Texto que debe aparecer en la web de origen de la descarga.
    var origenContiene: String = ""
    /// Vacío = la plantilla por defecto.
    var plantilla: String = ""
    /// Si se rellena, sustituye al asunto deducido (p. ej. "Factura").
    var asuntoFijo: String = ""
    var modoEntidad: ModoEntidad = .deducir
    /// Solo con `modoEntidad == .fija`, p. ej. el nombre de un proyecto.
    var entidadFija: String = ""
    /// Vacío = dejarlo donde está. Admite campos: ~/Documents/Clientes/{entidad}
    var destino: String = ""
}

struct AppSettings: Codable {
    var carpetas = ["~/Downloads"]
    var modo: ApprovalMode = .siempreConfirmar
    var fuenteFecha: DateSource = .documentoOdescarga
    var formatoFecha = "yyyyMMdd"
    var plantillaPorDefecto = "{fecha}-{entidad}-{asunto}-{firmada?firmada}"
    var textoSinEntidad = "SIN-ENTIDAD"
    /// Tu propia empresa: aparece en todo y no debe confundirse con un cliente o proveedor.
    var misEmpresas: [String] = []
    /// Solo estos tipos se renombran al descargarse (el botón derecho vale para todos).
    var tiposVigilados: [TipoArchivo] = [.pdf, .word, .excel]
    /// Se añaden a las instrucciones de la IA.
    var instruccionesIA = """
        Si el documento es personal (DNI, pasaporte, certificados de nacimiento o matrimonio, \
        temas médicos, nóminas, vida laboral, impuestos personales, recibos de casa), es personal.
        La fecha es la de emisión o firma del documento, no la de plazos, vencimientos o vigencia.
        """
    var usarIA = true
    var pausado = false
    var idioma: Idioma = .automatico
    /// Para actualizar una sola vez las configuraciones guardadas por versiones anteriores.
    var versionDatos = Store.versionDatosActual
}

struct HistoryEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var fecha = Date()
    var original: String
    var nuevo: String
    var deshecho = false

    var nombreOriginal: String { (original as NSString).lastPathComponent }
    var nombreNuevo: String { (nuevo as NSString).lastPathComponent }
}

/// Copia inmutable de la configuración para analizar fuera del hilo principal.
struct Configuracion {
    var ajustes: AppSettings
    var entidades: [Entity]
    var reglas: [Rule]
}

/// Resultado del análisis de un archivo: el nombre propuesto y de dónde sale cada dato.
struct Propuesta: Identifiable {
    let id = UUID()
    var url: URL
    var nombre: String
    var carpetaDestino: URL
    var regla: String?
    var fecha: Date?
    var fechaOrigen: String
    var entidad: String?
    var entidadOrigen: String
    var asunto: String?
    var asuntoOrigen: String
    var firmada: Bool
    var firmaOrigen: String
    var dudas: [String]
    var ocr: Bool
    var usoIA: Bool
    /// Empresa encontrada en el texto o por la IA que no está en tu lista: se puede añadir con un botón.
    var entidadSugerida: String? = nil
    /// Archivo idéntico que ya tienes.
    var duplicadoDe: URL? = nil

    var mueveDeCarpeta: Bool {
        carpetaDestino.standardizedFileURL.path != url.deletingLastPathComponent().standardizedFileURL.path
    }
}

extension String {
    var recortado: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var noVacio: String? { recortado.isEmpty ? nil : recortado }
}
