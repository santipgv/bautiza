import Foundation

/// Guarda ajustes, entidades, reglas e historial en ~/Library/Application Support/Bautiza.
@MainActor
final class Store: ObservableObject {
    @Published var ajustes = AppSettings() {
        didSet {
            if oldValue.idioma != ajustes.idioma {
                Loc.aplicar(ajustes.idioma)
                alCambiarIdioma?()
            }
            guardarConfiguracion()
        }
    }
    var alCambiarIdioma: (() -> Void)?
    @Published var entidades: [Entity] = [] { didSet { guardarConfiguracion() } }
    @Published var reglas: [Rule] = [] { didSet { guardarConfiguracion() } }
    @Published var historial: [HistoryEntry] = [] { didSet { guardarHistorial() } }

    private var cargando = true

    init() {
        let conf = Store.leerConfiguracion()
        ajustes = conf.ajustes
        Loc.aplicar(conf.ajustes.idioma)
        entidades = conf.entidades
        reglas = conf.reglas
        if let data = try? Data(contentsOf: Store.rutaHistorial),
           let h = try? JSONDecoder.bautiza.decode([HistoryEntry].self, from: data) {
            historial = h
        }
        cargando = false
        if !FileManager.default.fileExists(atPath: Store.rutaConfiguracion.path) { guardarConfiguracion() }
    }

    var configuracion: Configuracion {
        Configuracion(ajustes: ajustes, entidades: entidades, reglas: reglas)
    }

    // MARK: - Disco

    /// BAUTIZA_DATOS permite usar otra carpeta (pruebas, capturas) sin tocar la configuración real.
    nonisolated static var carpetaDatos: URL {
        if let otra = ProcessInfo.processInfo.environment["BAUTIZA_DATOS"], !otra.isEmpty {
            return URL(fileURLWithPath: otra, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Bautiza", isDirectory: true)
    }
    nonisolated static var rutaConfiguracion: URL { carpetaDatos.appendingPathComponent("configuracion.json") }
    nonisolated static var rutaHistorial: URL { carpetaDatos.appendingPathComponent("historial.json") }
    nonisolated static var rutaPendientes: URL { carpetaDatos.appendingPathComponent("pendientes.json") }

    private struct Archivo: Codable {
        var ajustes: AppSettings
        var entidades: [Entity]
        var reglas: [Rule]
    }

    /// Lee la configuración tolerando campos que falten (versiones antiguas del archivo).
    nonisolated static func leerConfiguracion() -> Configuracion {
        guard let data = try? Data(contentsOf: rutaConfiguracion),
              let raiz = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return Configuracion(ajustes: AppSettings(), entidades: ejemploEntidades, reglas: ejemploReglas)
        }
        var ajustes = fusionar(raiz["ajustes"], con: AppSettings()) ?? AppSettings()
        let entidades = (raiz["entidades"] as? [Any] ?? []).compactMap { fusionar($0, con: Entity(nombre: "")) }
        var reglas = (raiz["reglas"] as? [Any] ?? []).compactMap { fusionar($0, con: Rule(nombre: "")) }
        let ajustesGuardados = raiz["ajustes"] as? [String: Any]
        // Antes solo había una carpeta vigilada.
        if ajustesGuardados?["carpetas"] == nil, let una = ajustesGuardados?["carpeta"] as? String {
            ajustes.carpetas = [una]
        }
        // Configuraciones anteriores a los tipos de archivo: les añadimos la regla de documentos personales.
        if ajustesGuardados?["tiposVigilados"] == nil {
            reglas.insert(reglaPersonal, at: 0)
        }
        // Configuraciones anteriores al inglés: añadimos las palabras clave en inglés a las reglas de serie.
        if (ajustesGuardados?["versionDatos"] as? Int ?? 0) < 3 {
            for i in reglas.indices {
                if let extra = palabrasInglesas[reglas[i].nombre] {
                    let tenia = Set(reglas[i].palabrasClave.map(Texto.normalizar))
                    reglas[i].palabrasClave += extra.filter { !tenia.contains(Texto.normalizar($0)) }
                }
            }
        }
        return Configuracion(ajustes: ajustes, entidades: entidades, reglas: reglas)
    }

    /// Completa un objeto JSON con los valores por defecto antes de decodificarlo.
    nonisolated private static func fusionar<T: Codable>(_ objeto: Any?, con defecto: T) -> T? {
        guard let objeto = objeto as? [String: Any],
              let dataDefecto = try? JSONEncoder.bautiza.encode(defecto),
              let base = try? JSONSerialization.jsonObject(with: dataDefecto) as? [String: Any] else { return nil }
        let combinado = base.merging(objeto) { _, nuevo in nuevo }
        guard let data = try? JSONSerialization.data(withJSONObject: combinado) else { return nil }
        return try? JSONDecoder.bautiza.decode(T.self, from: data)
    }

    private func guardarConfiguracion() {
        guard !cargando else { return }
        escribir(Archivo(ajustes: ajustes, entidades: entidades, reglas: reglas), en: Store.rutaConfiguracion)
    }

    private func guardarHistorial() {
        guard !cargando else { return }
        escribir(Array(historial.prefix(500)), en: Store.rutaHistorial)
    }

    private func escribir<T: Encodable>(_ valor: T, en url: URL) {
        try? FileManager.default.createDirectory(at: Store.carpetaDatos, withIntermediateDirectories: true)
        if let data = try? JSONEncoder.bautiza.encode(valor) { try? data.write(to: url, options: .atomic) }
    }

    // MARK: - Ejemplos para el primer arranque

    nonisolated static let ejemploEntidades = [
        Entity(nombre: "AVON", alias: ["Avon Cosmetics"], tipo: .cliente),
    ]

    nonisolated static let versionDatosActual = 3

    nonisolated private static let palabrasInglesas = [
        "Personal": ["birth certificate", "marriage certificate", "medical report", "medical record",
                     "prescription", "payslip", "pay slip", "tax return", "proof of address"],
        "Facturas": ["invoice"],
        "Licitaciones": ["tender", "request for proposal"],
    ]

    nonisolated static let reglaPersonal = Rule(
        nombre: "Personal",
        palabrasClave: [
            "certificado de nacimiento", "certificado literal de nacimiento", "certificado de matrimonio",
            "libro de familia", "certificado de empadronamiento", "volante de empadronamiento",
            "informe de vida laboral", "informe medico", "historia clinica", "receta medica",
            "pago de salarios", "declaracion de la renta", "impuesto sobre la renta de las personas fisicas",
            "birth certificate", "marriage certificate", "medical report", "medical record", "prescription",
            "payslip", "pay slip", "tax return", "proof of address",
        ],
        modoEntidad: .vacia)

    nonisolated static let ejemploReglas = [
        reglaPersonal,
        Rule(nombre: "Licitaciones", palabrasClave: ["licitación", "pliego", "tender", "request for proposal"]),
        Rule(nombre: "Facturas", palabrasClave: ["factura", "invoice"], asuntoFijo: "Factura"),
    ]
}

extension JSONEncoder {
    static var bautiza: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

extension JSONDecoder {
    static var bautiza: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
