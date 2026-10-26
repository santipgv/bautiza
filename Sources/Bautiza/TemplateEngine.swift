import Foundation

struct TemplateContext {
    var fecha: Date?
    var formatoFecha: String
    /// entidad, asunto, original, tipo, regla…
    var valores: [String: String]
    var firmada: Bool
}

/// Plantillas del tipo `{fecha}-{entidad:MAYUS}-{asunto}-{firmada?firmada}`.
///
/// - `{campo}` inserta el valor.
/// - `{campo:formato}` en la fecha es un formato de fecha (`yyyy-MM-dd`); en el resto MAYUS, minus o Titulo.
/// - `{campo?texto}` inserta `texto` solo si el campo tiene valor (o, para `firmada`, si está firmada).
/// Los separadores que quedan huérfanos al faltar un campo se eliminan.
enum TemplateEngine {
    static let campos = ["fecha", "entidad", "asunto", "firmada", "tipo", "original", "regla"]

    /// Los mismos campos con nombre en inglés: {date}-{entity}-{subject}-{signed?signed}
    private static let alias = ["date": "fecha", "entity": "entidad", "subject": "asunto",
                                "signed": "firmada", "type": "tipo", "rule": "regla"]

    private static let token = try! NSRegularExpression(pattern: #"\{([\p{L}0-9_]+)(?:([:?])([^}]*))?\}"#)

    static func render(_ plantilla: String, _ ctx: TemplateContext) -> String {
        let ns = plantilla as NSString
        var resultado = ""
        var ultimo = 0
        for m in token.matches(in: plantilla, range: NSRange(location: 0, length: ns.length)) {
            resultado += ns.substring(with: NSRange(location: ultimo, length: m.range.location - ultimo))
            let escrito = ns.substring(with: m.range(at: 1)).lowercased()
            let campo = alias[escrito] ?? escrito
            let op = m.range(at: 2).location == NSNotFound ? "" : ns.substring(with: m.range(at: 2))
            let arg = m.range(at: 3).location == NSNotFound ? "" : ns.substring(with: m.range(at: 3))
            var v = valor(campo, op, arg, ctx)
            if escrito == "signed", op.isEmpty, !v.isEmpty { v = "signed" }
            resultado += sanear(v)
            ultimo = m.range.location + m.range.length
        }
        resultado += ns.substring(from: ultimo)
        return limpiar(resultado)
    }

    private static func valor(_ campo: String, _ op: String, _ arg: String, _ ctx: TemplateContext) -> String {
        if op == "?" {
            let verdadero = campo == "firmada" ? ctx.firmada : !(texto(campo, ctx).isEmpty)
            return verdadero ? arg : ""
        }
        if campo == "fecha" {
            guard let fecha = ctx.fecha else { return "" }
            let f = DateFormatter()
            f.locale = Loc.locale
            f.dateFormat = (op == ":" && !arg.isEmpty) ? arg : ctx.formatoFecha
            return f.string(from: fecha)
        }
        var v = texto(campo, ctx)
        if op == ":" {
            switch arg.lowercased() {
            case "mayus", "upper": v = v.uppercased()
            case "minus", "lower": v = v.lowercased()
            case "titulo", "title": v = v.capitalized
            default: break
            }
        }
        return v
    }

    private static func texto(_ campo: String, _ ctx: TemplateContext) -> String {
        if campo == "firmada" { return ctx.firmada ? "firmada" : "" }
        if campo == "fecha" { return ctx.fecha == nil ? "" : "x" }
        return ctx.valores[campo] ?? ""
    }

    /// Quita caracteres que no pueden ir en un nombre de archivo.
    static func sanear(_ s: String) -> String {
        s.replacingOccurrences(of: #"[/\\:*?"<>|\n\r\t]+"#, with: " ", options: .regularExpression)
    }

    /// Une guiones repetidos, quita espacios dobles y separadores en los extremos.
    static func limpiar(_ s: String) -> String {
        var r = s.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        r = r.replacingOccurrences(of: #"\s*-(?:\s*-)+\s*"#, with: "-", options: .regularExpression)
        r = r.replacingOccurrences(of: #"\s*_(?:\s*_)+\s*"#, with: "_", options: .regularExpression)
        r = r.trimmingCharacters(in: CharacterSet(charactersIn: " -_."))
        if r.count > 180 { r = String(r.prefix(180)).trimmingCharacters(in: CharacterSet(charactersIn: " -_.")) }
        return r
    }
}
