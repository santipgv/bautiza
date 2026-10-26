import Foundation

enum Idioma: String, Codable, CaseIterable, Identifiable {
    case automatico, es, en
    var id: String { rawValue }
    var titulo: String {
        switch self {
        case .automatico: return L("Automático (el del Mac)", "Automatic (Mac language)")
        case .es: return "Español"
        case .en: return "English"
        }
    }
}

enum Loc {
    /// Lo fija Store a partir de los ajustes; también lo leen los análisis en segundo plano.
    static var ingles = sistemaEnIngles

    static var sistemaEnIngles: Bool {
        !(Locale.preferredLanguages.first ?? "es").hasPrefix("es")
    }

    static func aplicar(_ idioma: Idioma) {
        ingles = idioma == .en || (idioma == .automatico && sistemaEnIngles)
    }

    static var locale: Locale { Locale(identifier: ingles ? "en_US" : "es_ES") }
}

/// Texto en español e inglés escrito junto, en el mismo sitio donde se usa.
func L(_ es: String, _ en: String) -> String {
    Loc.ingles ? en : es
}
