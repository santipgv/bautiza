import Foundation

/// Lee un archivo y decide fecha, entidad, asunto y firma, y con ello el nombre nuevo.
enum FieldResolver {
    static func analizar(_ url: URL, _ conf: Configuracion) async -> Propuesta {
        let contenido = TextExtractor.extraer(url)
        let ajustes = conf.ajustes
        let ext = url.pathExtension.lowercased()
        let nombreOriginal = url.deletingPathExtension().lastPathComponent
        let textoN = Texto.normalizar(String(contenido.texto.prefix(80_000)))
        let nombreN = Texto.normalizar(nombreOriginal)
        let origenesN = contenido.origenes.map(Texto.normalizar)
        var dudas: [String] = []

        // Entidad: CIF, nombre o alias en el texto; si no, en el nombre del archivo o la web de origen.
        var entidad: Entity?
        var entidadNombre: String?
        var entidadOrigen = L("no encontrada", "not found")
        var personal = false
        var entidadSugerida: String?
        if case let (e, origen)? = buscarEntidad(textoN, en: conf.entidades, extra: [nombreN] + origenesN) {
            entidad = e
            entidadOrigen = origen
        }

        var regla = buscarRegla(ext: ext, texto: textoN + " " + nombreN, entidad: entidad, origenes: origenesN, conf.reglas)

        // La regla manda sobre la entidad si lo dice.
        func aplicarModoRegla() {
            guard let regla else { return }
            switch regla.modoEntidad {
            case .deducir: break
            case .vacia:
                personal = true
                entidad = nil
                entidadOrigen = L("regla «\(regla.nombre)»: personal", "rule “\(regla.nombre)”: personal")
            case .fija:
                entidad = nil
                entidadNombre = regla.entidadFija.noVacio
                entidadOrigen = L("regla «\(regla.nombre)»", "rule “\(regla.nombre)”")
            }
        }
        aplicarModoRegla()
        let deducirEntidad = (regla?.modoEntidad ?? .deducir) == .deducir

        // Fecha en el texto (la IA puede corregirla luego si hay dudas).
        let enDocumento = ajustes.fuenteFecha == .soloDescarga ? nil : buscarFecha(textoN)

        // IA local para asunto, entidad, si es personal y fecha dudosa.
        var ia: ResultadoIA?
        let necesitaAsunto = regla?.asuntoFijo.noVacio == nil
        let fechaDudosa = ajustes.fuenteFecha != .soloDescarga && enDocumento?.segura != true
        if ajustes.usarIA, !contenido.texto.recortado.isEmpty,
           necesitaAsunto || (deducirEntidad && entidad == nil) || fechaDudosa {
            ia = await LocalAI.analizar(texto: contenido.texto, nombreArchivo: url.lastPathComponent,
                                        instrucciones: ajustes.instruccionesIA)
        }
        if deducirEntidad, entidad == nil, let ia {
            if ia.personal {
                personal = true
                entidadOrigen = L("IA: documento personal", "AI: personal document")
            } else {
                for candidato in [ia.emisor, ia.destinatario].compactMap({ $0 }) {
                    if let e = entidadPorNombre(candidato, conf.entidades) {
                        entidad = e
                        entidadOrigen = L("IA", "AI")
                        break
                    }
                }
                if entidad != nil {
                    regla = buscarRegla(ext: ext, texto: textoN + " " + nombreN, entidad: entidad, origenes: origenesN, conf.reglas)
                    aplicarModoRegla()
                } else if let sugerida = ia.emisor.flatMap(Texto.limpiarEmpresa),
                          !esPropia(sugerida, ajustes.misEmpresas) {
                    entidadNombre = sugerida
                    entidadOrigen = L("IA (no está en tu lista)", "AI (not in your list)")
                    entidadSugerida = sugerida
                    dudas.append(L("Entidad «\(sugerida)» deducida por la IA; no está en tu lista", "“\(sugerida)” suggested by the AI; not in your list"))
                }
            }
        }
        if deducirEntidad, !personal, entidad == nil, entidadNombre == nil,
           let sugerida = Texto.empresaEnTexto(contenido.texto, excluir: ajustes.misEmpresas) {
            entidadNombre = sugerida
            entidadOrigen = L("texto (no está en tu lista)", "text (not in your list)")
            entidadSugerida = sugerida
            dudas.append(L("Entidad «\(sugerida)» encontrada en el texto; no está en tu lista", "“\(sugerida)” found in the text; not in your list"))
        }
        if let entidad { entidadNombre = entidad.nombre }
        if !personal, entidadNombre == nil { dudas.append(L("No se ha encontrado cliente ni proveedor", "No client or supplier found")) }

        // Fecha
        var fecha: Date?
        var fechaOrigen = L("no encontrada", "not found")
        if let enDocumento, enDocumento.segura || ia?.fecha == nil {
            fecha = enDocumento.fecha
            fechaOrigen = L("documento", "document")
            if !enDocumento.segura { dudas.append(L("Hay varias fechas en el documento; revisa que sea la correcta", "Several dates in the document; check this is the right one")) }
        } else if ajustes.fuenteFecha != .soloDescarga, let f = ia?.fecha {
            fecha = f
            fechaOrigen = L("IA", "AI")
        } else if ajustes.fuenteFecha != .soloDocumento {
            fecha = contenido.fechaDescarga
            fechaOrigen = L("descarga", "download")
        } else {
            dudas.append(L("No hay fecha en el documento", "No date in the document"))
        }

        // Firma
        let (firmada, firmaOrigen) = detectarFirma(contenido, textoN: textoN, nombreN: nombreN)

        // Asunto
        var asunto: String?
        var asuntoOrigen = ""
        if let regla, let fijo = regla.asuntoFijo.noVacio {
            asunto = fijo
            asuntoOrigen = L("regla «\(regla.nombre)»", "rule “\(regla.nombre)”")
        } else if let a = ia?.asunto.map(Texto.frase),
                  // Una sola palabra («Nacimiento») suele quedarse corta: mejor el encabezado si lo hay.
                  a.split(separator: " ").count > 1 || Texto.encabezado(contenido.texto, excluir: []) == nil {
            asunto = a
            asuntoOrigen = L("IA", "AI")
        } else if let t = Texto.tituloUtil(contenido.titulo) {
            asunto = t
            asuntoOrigen = L("título del PDF", "PDF title")
        } else if let e = Texto.encabezado(contenido.texto, excluir: conf.entidades.flatMap { [$0.nombre] + $0.alias } + ajustes.misEmpresas) {
            asunto = e
            asuntoOrigen = L("encabezado del documento", "document heading")
        } else {
            asunto = Texto.asuntoDesdeNombre(nombreOriginal)
            asuntoOrigen = L("nombre original", "original name")
            dudas.append(L("Asunto tomado del nombre original del archivo", "Subject taken from the original file name"))
        }
        if let a = asunto, a.count > 60 { asunto = String(a.prefix(60)).recortado }

        // Nombre y carpeta
        let ctx = TemplateContext(
            fecha: fecha,
            formatoFecha: ajustes.formatoFecha,
            valores: [
                "entidad": personal ? "" : (entidadNombre ?? ajustes.textoSinEntidad),
                "asunto": asunto ?? "",
                "original": nombreOriginal,
                "tipo": entidad?.tipo.titulo ?? "",
                "regla": regla?.nombre ?? "",
            ],
            firmada: firmada)
        let plantilla = regla?.plantilla.noVacio ?? ajustes.plantillaPorDefecto
        let base = TemplateEngine.render(plantilla, ctx).noVacio ?? nombreOriginal
        let nombre = ext.isEmpty ? base : "\(base).\(ext)"

        var carpeta = url.deletingLastPathComponent()
        if let destino = regla?.destino.noVacio {
            carpeta = rutaDestino(destino, ctx)
        }

        return Propuesta(
            url: url, nombre: nombre, carpetaDestino: carpeta, regla: regla?.nombre,
            fecha: fecha, fechaOrigen: fechaOrigen,
            entidad: personal ? nil : entidadNombre, entidadOrigen: entidadOrigen,
            asunto: asunto, asuntoOrigen: asuntoOrigen,
            firmada: firmada, firmaOrigen: firmaOrigen,
            dudas: dudas, ocr: contenido.ocr, usoIA: ia != nil,
            entidadSugerida: personal ? nil : entidadSugerida)
    }

    // MARK: - Entidad

    static func buscarEntidad(_ textoN: String, en entidades: [Entity], extra: [String]) -> (Entity, String)? {
        let compacto = Texto.compactar(textoN)
        var mejor: (Entity, Int)?
        for e in entidades {
            let cif = Texto.compactar(e.cif)
            if cif.count >= 8, compacto.contains(cif) { return (e, "CIF") }
            let cabecera = String(textoN.prefix(1500))
            let apariciones = nombres(e).reduce(0) {
                let total = Texto.ocurrencias($1, en: textoN)
                return $0 + total + (Texto.ocurrencias($1, en: cabecera) > 0 ? 3 : 0)
            }
            if apariciones > (mejor?.1 ?? 0) { mejor = (e, apariciones) }
        }
        if let mejor { return (mejor.0, L("texto", "text")) }
        for e in entidades {
            for n in nombres(e) where n.count >= 3 {
                if extra.contains(where: { Texto.ocurrencias(n, en: $0) > 0 }) { return (e, L("nombre del archivo u origen", "file name or source")) }
            }
        }
        return nil
    }

    private static func nombres(_ e: Entity) -> [String] {
        ([e.nombre] + e.alias).map(Texto.normalizar).map(\.recortado).filter { $0.count >= 2 }
    }

    static func entidadPorNombre(_ candidato: String, _ entidades: [Entity]) -> Entity? {
        let c = Texto.normalizar(candidato)
        return entidades.first { e in
            nombres(e).contains { n in Texto.ocurrencias(n, en: c) > 0 || (c.count >= 3 && n.contains(c)) }
        }
    }

    private static func esPropia(_ nombre: String, _ propias: [String]) -> Bool {
        let n = Texto.normalizar(nombre)
        return propias.map(Texto.normalizar).map(\.recortado).contains { !$0.isEmpty && (n.contains($0) || $0.contains(n)) }
    }

    // MARK: - Regla

    static func buscarRegla(ext: String, texto: String, entidad: Entity?, origenes: [String], _ reglas: [Rule]) -> Rule? {
        reglas.first { r in
            guard r.activa else { return false }
            let exts = r.extensiones.map { Texto.normalizar($0).trimmingCharacters(in: CharacterSet(charactersIn: ". ")) }.filter { !$0.isEmpty }
            if !exts.isEmpty, !exts.contains(ext) { return false }
            let claves = r.palabrasClave.map { Texto.normalizar($0).recortado }.filter { !$0.isEmpty }
            if !claves.isEmpty, !claves.contains(where: { Texto.empiezaPalabra($0, en: texto) }) { return false }
            if let tipo = r.tipoEntidad, entidad?.tipo != tipo { return false }
            if let origen = r.origenContiene.noVacio.map(Texto.normalizar),
               !origenes.contains(where: { $0.contains(origen) }) { return false }
            return true
        }
    }

    // MARK: - Fecha

    private static let meses: [String: Int] = [
        "ene": 1, "jan": 1, "feb": 2, "mar": 3, "abr": 4, "apr": 4, "may": 5, "jun": 6, "jul": 7,
        "ago": 8, "aug": 8, "sep": 9, "set": 9, "oct": 10, "nov": 11, "dic": 12, "dec": 12,
    ]
    private static let nombresMes: Set<String> = [
        "enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "setiembre",
        "octubre", "noviembre", "diciembre", "january", "february", "march", "april", "june", "july",
        "august", "september", "october", "november", "december",
    ]

    private static func mes(_ palabra: String) -> Int? {
        let p = palabra.lowercased()
        guard p.count == 3 || nombresMes.contains(p) else { return nil }
        return meses[String(p.prefix(3))]
    }

    private static let patronTexto = try! NSRegularExpression(pattern: #"(?<!\d)(\d{1,2})(?:\s+de)?\s+([a-z]{3,10})\.?(?:\s+de|\s+del)?\s+(\d{4})(?!\d)"#)
    private static let patronIngles = try! NSRegularExpression(pattern: #"\b([a-z]{3,10})\.?\s+(\d{1,2}),?\s+(\d{4})(?!\d)"#)
    private static let patronNumerico = try! NSRegularExpression(pattern: #"(?<!\d)(\d{1,2})[/.-](\d{1,2})[/.-](\d{4}|\d{2})(?!\d)"#)
    private static let patronISO = try! NSRegularExpression(pattern: #"(?<!\d)(\d{4})-(\d{1,2})-(\d{1,2})(?!\d)"#)

    /// Busca la fecha "del documento" entre todas las que aparecen, puntuando por contexto.
    static func buscarFecha(_ t: String) -> (fecha: Date, segura: Bool)? {
        let ns = t as NSString
        let todo = NSRange(location: 0, length: ns.length)
        var candidatos: [(fecha: Date, pos: Int, puntos: Int)] = []

        func grupo(_ m: NSTextCheckingResult, _ i: Int) -> String { ns.substring(with: m.range(at: i)) }
        func añadir(_ d: Int?, _ m: Int?, _ a: Int?, _ pos: Int) {
            guard let d, let m, var a else { return }
            if a < 100 { a += 2000 }
            guard let fecha = fechaValida(d, m, a) else { return }
            let inicio = max(0, pos - 50)
            let antes = ns.substring(with: NSRange(location: inicio, length: pos - inicio))
            var puntos = 0
            if antes.range(of: #",\s*a\s*(?:dia\s*)?$"#, options: .regularExpression) != nil { puntos += 4 }
            if antes.contains("fecha") { puntos += 3 }
            if ["firmad", "emision", "emitid", "date", "dated", "issued", "signed"].contains(where: antes.contains) { puntos += 2 }
            if ["vencimiento", "plazo", "hasta", "limite", "validez", "caduc", "nacimiento", "entrega",
                "due", "deadline", "until", "expir", "valid", "birth", "delivery"].contains(where: antes.contains) { puntos -= 3 }
            candidatos.append((fecha, pos, puntos))
        }

        for m in patronTexto.matches(in: t, range: todo) {
            añadir(Int(grupo(m, 1)), mes(grupo(m, 2)), Int(grupo(m, 3)), m.range.location)
        }
        for m in patronIngles.matches(in: t, range: todo) {
            añadir(Int(grupo(m, 2)), mes(grupo(m, 1)), Int(grupo(m, 3)), m.range.location)
        }
        for m in patronNumerico.matches(in: t, range: todo) {
            añadir(Int(grupo(m, 1)), Int(grupo(m, 2)), Int(grupo(m, 3)), m.range.location)
        }
        for m in patronISO.matches(in: t, range: todo) {
            añadir(Int(grupo(m, 3)), Int(grupo(m, 2)), Int(grupo(m, 1)), m.range.location)
        }

        guard let mejor = candidatos.min(by: { ($0.puntos, -$0.pos) > ($1.puntos, -$1.pos) }) else { return nil }
        let distintas = Set(candidatos.map { Calendar.current.startOfDay(for: $0.fecha) })
        return (mejor.fecha, mejor.puntos > 0 || distintas.count == 1)
    }

    private static func fechaValida(_ d: Int, _ m: Int, _ a: Int) -> Date? {
        let añoActual = Calendar.current.component(.year, from: Date())
        guard (1990...(añoActual + 5)).contains(a), (1...12).contains(m), (1...31).contains(d) else { return nil }
        var c = DateComponents(year: a, month: m, day: d)
        c.hour = 12
        guard let fecha = Calendar(identifier: .gregorian).date(from: c),
              Calendar(identifier: .gregorian).component(.day, from: fecha) == d else { return nil }
        return fecha
    }

    // MARK: - Firma

    private static let marcasFirma = [
        "firmado digitalmente", "firmado electronicamente", "firma electronica valida",
        "docusign envelope id", "digitally signed", "electronically signed", "signaturit", "acrobat sign",
    ]

    static func detectarFirma(_ c: ContenidoDocumento, textoN: String, nombreN: String) -> (Bool, String) {
        if c.firmaDigital { return (true, L("firma digital en el PDF", "digital signature in the PDF")) }
        if let marca = marcasFirma.first(where: textoN.contains) { return (true, L("texto «\(marca)»", "text “\(marca)”")) }
        if nombreN.contains("firmad") || nombreN.contains("signed") { return (true, L("nombre del archivo", "file name")) }
        return (false, L("sin firma detectada", "no signature found"))
    }

    // MARK: - Carpeta destino

    static func rutaDestino(_ destino: String, _ ctx: TemplateContext) -> URL {
        let expandida = (destino as NSString).expandingTildeInPath
        let partes = expandida.split(separator: "/", omittingEmptySubsequences: true).map {
            TemplateEngine.render(String($0), ctx).noVacio ?? "_"
        }
        return URL(fileURLWithPath: "/" + partes.joined(separator: "/"), isDirectory: true)
    }
}

enum Texto {
    static func normalizar(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "es_ES")).lowercased()
    }

    static func compactar(_ s: String) -> String {
        String(String.UnicodeScalarView(normalizar(s).unicodeScalars.filter(CharacterSet.alphanumerics.contains)))
    }

    /// Veces que aparece `aguja` como palabra completa (no dentro de otra palabra).
    static func ocurrencias(_ aguja: String, en pajar: String) -> Int {
        guard !aguja.isEmpty else { return 0 }
        let patron = #"(?<![\p{L}\p{N}])"# + NSRegularExpression.escapedPattern(for: aguja) + #"(?![\p{L}\p{N}])"#
        guard let re = try? NSRegularExpression(pattern: patron) else { return 0 }
        return re.numberOfMatches(in: pajar, range: NSRange(pajar.startIndex..., in: pajar))
    }

    /// `clave` aparece empezando una palabra: "licitacion" encaja en "licitaciones" pero "pliego" no en "despliegue".
    static func empiezaPalabra(_ clave: String, en texto: String) -> Bool {
        let patron = #"(?<![\p{L}\p{N}])"# + NSRegularExpression.escapedPattern(for: clave)
        return texto.range(of: patron, options: .regularExpression) != nil
    }

    /// "Avon Cosmetics, S.A." → "Avon Cosmetics"
    static func limpiarEmpresa(_ s: String) -> String? {
        let sinForma = s.replacingOccurrences(
            of: #"[,\s]+(s\.?\s?a\.?\s?u?\.?|s\.?\s?l\.?\s?u?\.?|s\.?\s?coop\.?|sociedad an[oó]nima|sociedad limitada|inc\.?|ltd\.?|llc|gmbh)\s*$"#,
            with: "", options: [.regularExpression, .caseInsensitive])
        return TemplateEngine.sanear(sinForma).noVacio
    }

    private static let formaJuridica = try! NSRegularExpression(
        pattern: #"([\p{Lu}0-9][\p{L}0-9&.' -]{1,50}?),?\s+(S\.?\s?A\.?(?:\s?U\.?)?|S\.?\s?L\.?(?:\s?U\.?)?|Ltd\.?|Limited|Inc\.?|LLC|GmbH|PLC|Corp\.?)(?![\p{L}])"#)

    /// Primera empresa con S.A./S.L. en el texto que no sea una de las tuyas: "SUMINISTROS LEVANTE S.L." → "SUMINISTROS LEVANTE"
    static func empresaEnTexto(_ texto: String, excluir: [String]) -> String? {
        let propias = excluir.map(normalizar).map(\.recortado).filter { !$0.isEmpty }
        for linea in texto.split(whereSeparator: \.isNewline).prefix(60) {
            let l = String(linea)
            for m in formaJuridica.matches(in: l, range: NSRange(l.startIndex..., in: l)) {
                guard let r = Range(m.range(at: 1), in: l) else { continue }
                let nombre = String(l[r]).recortado
                let n = normalizar(nombre)
                if nombre.count < 3 || propias.contains(where: { n.contains($0) || $0.contains(n) }) { continue }
                return TemplateEngine.sanear(nombre).noVacio
            }
        }
        return nil
    }

    /// Primer titular corto en mayúsculas: "PLIEGO DE CONDICIONES" → "Pliego de condiciones".
    static func encabezado(_ texto: String, excluir: [String]) -> String? {
        let evitar = excluir.map(normalizar).map(\.recortado).filter { $0.count >= 2 }
        var candidatos: [String] = []
        for linea in texto.split(whereSeparator: \.isNewline).prefix(25) {
            var l = String(linea).recortado
            // "INVOICE 88213" / "FACTURA Nº 2026/0245" → nos quedamos con las palabras.
            let palabrasSinNumeros = l.split(separator: " ").filter { !$0.contains(where: \.isNumber) && $0 != "Nº" && $0 != "No." && $0 != "#" }
            if palabrasSinNumeros.count < l.split(separator: " ").count, !palabrasSinNumeros.isEmpty,
               esTipoDocumento(palabrasSinNumeros.joined(separator: " ")) {
                l = palabrasSinNumeros.joined(separator: " ")
            }
            let letras = l.unicodeScalars.filter(CharacterSet.letters.contains)
            let palabras = l.split(separator: " ")
            guard (1...7).contains(palabras.count), palabras.count > 1 || esTipoDocumento(l), l.count <= 60, letras.count >= l.count * 2 / 3,
                  l == l.uppercased() else { continue }
            let n = normalizar(l)
            if evitar.contains(where: { ocurrencias($0, en: n) > 0 }) { continue }
            if n.range(of: #"(?<![\p{L}])(s\.?\s?a|s\.?\s?l|cif|nif|vat|ltd|limited|inc|llc|gmbh|plc)(?![\p{L}])"#, options: .regularExpression) != nil { continue }
            candidatos.append(primeraMayuscula(l.lowercased(with: Locale(identifier: "es_ES"))))
        }
        // Mejor un titular que diga qué es el documento que uno con el nombre del organismo.
        return candidatos.first(where: esTipoDocumento) ?? candidatos.first
    }

    /// Alguna palabra dice qué es el documento: certificado, invoice, contrato…
    private static func esTipoDocumento(_ linea: String) -> Bool {
        normalizar(linea).split(separator: " ").contains { palabra in
            tiposDocumento.contains { palabra.hasPrefix($0) }
        }
    }

    private static let tiposDocumento = [
        "certificad", "contrato", "factura", "pliego", "presupuesto", "informe", "acta", "oferta",
        "propuesta", "solicitud", "nomina", "recibo", "declaracion", "escritura", "convenio", "acuerdo",
        "licitacion", "pedido", "albaran", "memoria", "poliza", "anexo", "adenda", "carta", "notificacion",
        "resolucion", "liquidacion", "extracto", "justificante", "orden", "proyecto", "plan",
        "certificate", "contract", "invoice", "quote", "quotation", "estimate", "report", "minutes",
        "offer", "proposal", "agreement", "tender", "purchase", "statement", "receipt", "policy",
        "letter", "notice", "addendum", "amendment", "memorandum", "application", "payslip",
    ]

    static func tituloUtil(_ titulo: String?) -> String? {
        guard var t = titulo?.recortado, !t.isEmpty else { return nil }
        t = t.replacingOccurrences(of: #"^microsoft (word|excel|powerpoint) - "#, with: "", options: [.regularExpression, .caseInsensitive])
        t = t.replacingOccurrences(of: #"\.(docx?|xlsx?|pptx?|pdf|odt)$"#, with: "", options: [.regularExpression, .caseInsensitive])
        let n = normalizar(t)
        if ["untitled", "sin titulo", "documento", "document", "untitled document"].contains(n) || n.count < 3 { return nil }
        if n.range(of: #"^[\d\W_]+$"#, options: .regularExpression) != nil { return nil }
        return t
    }

    static func asuntoDesdeNombre(_ nombre: String) -> String? {
        var s = nombre.replacingOccurrences(of: #"[_.]+"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\b\d{6,}\b"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s*\(\d+\)$"#, with: "", options: .regularExpression)
        return TemplateEngine.limpiar(s).noVacio
    }

    /// "LICITACION VEHICULOS" o "Contrato Mantenimiento" → "Licitacion vehiculos", "Contrato mantenimiento".
    /// Respeta siglas cortas dentro de una frase normal ("Contrato con IBM").
    static func frase(_ s: String) -> String {
        let t = s.recortado.trimmingCharacters(in: CharacterSet(charactersIn: ".\"«»"))
        let palabras = t.split(separator: " ")
        let todoMayusculas = t == t.uppercased() && t != t.lowercased()
        let todasCapitalizadas = palabras.count > 1 && palabras.allSatisfy { $0.first?.isUppercase == true }
        guard todoMayusculas || todasCapitalizadas else { return primeraMayuscula(t) }
        return primeraMayuscula(t.lowercased(with: Locale(identifier: "es_ES")))
    }

    static func primeraMayuscula(_ s: String) -> String {
        let t = s.recortado.trimmingCharacters(in: CharacterSet(charactersIn: ".\"«»"))
        return t.prefix(1).uppercased() + t.dropFirst()
    }
}
