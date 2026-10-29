import Foundation
import NaturalLanguage
#if canImport(FoundationModels)
import FoundationModels
#endif

struct ResultadoIA {
    var asunto: String?
    var emisor: String?
    var destinatario: String?
    var personal = false
    var fecha: Date?
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
@Generable
struct DocumentoIA {
    @Guide(description: "De qué trata el documento en 2 a 4 palabras, en el mismo idioma que el documento, solo la primera letra en mayúscula, sin fechas ni nombres de empresas. Ejemplos: Licitación renting vehículos, Contrato de mantenimiento, Oferta comercial, Service agreement")
    var asunto: String
    @Guide(description: "Empresa u organización que emite el documento. Cadena vacía si no se sabe")
    var emisor: String
    @Guide(description: "Empresa u organización a la que va dirigido. Cadena vacía si no se sabe")
    var destinatario: String
    @Guide(description: "true si es un documento de la vida personal del usuario y no de trabajo con una empresa")
    var personal: Bool
    @Guide(description: "Fecha de emisión o firma del documento en formato AAAA-MM-DD. Cadena vacía si no aparece")
    var fecha: String
}
#endif

/// IA de Apple en el propio Mac (Apple Intelligence). Gratis y sin enviar nada fuera.
enum LocalAI {
    static var estado: String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return L("La IA de Apple está disponible en este Mac.", "Apple's AI is available on this Mac.")
            case .unavailable(.appleIntelligenceNotEnabled):
                return L("Activa Apple Intelligence en Ajustes del Sistema para usar la IA.", "Turn on Apple Intelligence in System Settings to use the AI.")
            case .unavailable(.modelNotReady):
                return L("El modelo de Apple todavía se está descargando.", "Apple's model is still downloading.")
            case .unavailable(.deviceNotEligible):
                return L("Este Mac no es compatible con la IA de Apple.", "This Mac doesn't support Apple's AI.")
            case .unavailable:
                return L("La IA de Apple no está disponible ahora mismo.", "Apple's AI isn't available right now.")
            }
        }
        return L("La IA de Apple requiere macOS 26.", "Apple's AI requires macOS 26.")
        #else
        return L("Esta versión se compiló sin la IA de Apple: actualiza las Command Line Tools y vuelve a compilar.", "This build has no Apple AI: update the Command Line Tools and rebuild.")
        #endif
    }

    static func analizar(texto: String, nombreArchivo: String, instrucciones: String) async -> ResultadoIA? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else { return nil }
            let sesion = LanguageModelSession(instructions: """
                Clasificas documentos para ponerles un nombre de archivo corto. \
                Escribe el asunto en el mismo idioma que el documento y sé breve.

                Instrucciones del usuario:
                \(instrucciones)
                """)
            // El modelo pequeño tiende a responder en español; le decimos el idioma del documento.
            let idioma = NLLanguageRecognizer.dominantLanguage(for: String(texto.prefix(2000)))
            let nombreIdioma = idioma.flatMap { Locale(identifier: "es").localizedString(forLanguageCode: $0.rawValue) } ?? "el del documento"
            let prompt = """
                Idioma del documento: \(nombreIdioma). Escribe el asunto en ese idioma.
                Nombre del archivo: \(nombreArchivo)

                Texto del documento:
                \(texto.prefix(2500))
                """
            guard let r = try? await sesion.respond(to: prompt, generating: DocumentoIA.self) else { return nil }
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            f.locale = Locale(identifier: "en_US_POSIX")
            return ResultadoIA(asunto: r.content.asunto.noVacio,
                               emisor: r.content.emisor.noVacio,
                               destinatario: r.content.destinatario.noVacio,
                               personal: r.content.personal,
                               fecha: f.date(from: r.content.fecha.recortado))
        }
        #endif
        return nil
    }
}
