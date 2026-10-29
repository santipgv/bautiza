import AppKit
import Foundation

// Pruebas de Bautiza. Se ejecutan con ./test.sh; salen con código 1 si algo falla.

var fallos = 0
var total = 0

func igual<T: Equatable>(_ obtenido: T, _ esperado: T, _ que: String, linea: Int = #line) {
    total += 1
    if obtenido != esperado {
        fallos += 1
        print("✗ \(que) (línea \(linea))\n    obtenido: \(obtenido)\n    esperado: \(esperado)")
    }
}

func cierto(_ condicion: Bool, _ que: String, linea: Int = #line) {
    igual(condicion, true, que, linea: linea)
}

final class Caja<T>: @unchecked Sendable { var valor: T? }

/// Espera a una función async desde código síncrono.
func esperar<T>(_ trabajo: @escaping () async -> T) -> T {
    let caja = Caja<T>()
    let listo = DispatchSemaphore(value: 0)
    Task.detached {
        caja.valor = await trabajo()
        listo.signal()
    }
    listo.wait()
    return caja.valor!
}

let dia = DateFormatter()
dia.dateFormat = "yyyy-MM-dd"
dia.locale = Locale(identifier: "en_US_POSIX")

let carpeta = FileManager.default.temporaryDirectory.appendingPathComponent("bautiza-pruebas-\(UUID().uuidString)")
try! FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: carpeta) }

/// PDF de una página con texto seleccionable.
func crearPDF(_ nombre: String, _ texto: String) -> URL {
    let url = carpeta.appendingPathComponent(nombre)
    var caja = CGRect(x: 0, y: 0, width: 595, height: 842)
    let ctx = CGContext(url as CFURL, mediaBox: &caja, nil)!
    ctx.beginPDFPage(nil)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSAttributedString(string: texto, attributes: [.font: NSFont.systemFont(ofSize: 12)])
        .draw(in: caja.insetBy(dx: 50, dy: 60))
    ctx.endPDFPage()
    ctx.closePDF()
    return url
}

Loc.aplicar(.es)

// MARK: - Fechas

func fecha(_ texto: String) -> String? {
    FieldResolver.buscarFecha(Texto.normalizar(texto)).map { dia.string(from: $0.fecha) }
}

igual(fecha("En Madrid, a 26 de octubre de 2026"), "2026-10-26", "fecha con mes en letra")
igual(fecha("Plazo de presentación: hasta el 15/11/2026.\nEn Madrid, a 26 de octubre de 2026"), "2026-10-26",
      "la fecha de firma gana al plazo")
igual(fecha("Fecha de factura: 14/10/2026\nVencimiento: 14/11/2026"), "2026-10-14", "fecha de factura, no vencimiento")
igual(fecha("Fecha de nacimiento: 12 de marzo de 1990\nExpedido en Madrid, a 20 de octubre de 2026"), "2026-10-20",
      "certificado: expedición, no nacimiento")
igual(fecha("Invoice date: 14 October 2026\nDue date: 13 November 2026"), "2026-10-14", "factura en inglés")
igual(fecha("Issued on October 21, 2026"), "2026-10-21", "fecha americana")
igual(fecha("Ref 2026-03-05"), "2026-03-05", "fecha ISO")
igual(fecha("26 oct. 2026"), "2026-10-26", "mes abreviado")
igual(fecha("Válido el 31/02/2026"), nil, "fecha imposible")
igual(fecha("Sin fechas aquí, solo 12345678"), nil, "sin fecha")

// MARK: - Plantillas

let ctx = TemplateContext(fecha: dia.date(from: "2026-10-26"), formatoFecha: "yyyyMMdd",
                          valores: ["entidad": "Avon", "asunto": "Licitación vehículos"], firmada: true)
igual(TemplateEngine.render("{fecha}-{entidad:MAYUS}-{asunto}-{firmada?firmada}", ctx),
      "20261026-AVON-Licitación vehículos-firmada", "plantilla completa")
igual(TemplateEngine.render("{date:yyyy-MM}_{entity:lower}_{signed}", ctx), "2026-10_avon_signed", "campos en inglés")
var sinDatos = ctx
sinDatos.firmada = false
sinDatos.valores["entidad"] = ""
igual(TemplateEngine.render("{fecha}-{entidad}-{asunto}-{firmada?firmada}", sinDatos),
      "20261026-Licitación vehículos", "los guiones sobrantes se quitan")
var conBarras = ctx
conBarras.valores["asunto"] = "Pedido 12/34: urgente"
igual(TemplateEngine.render("{asunto}", conBarras), "Pedido 12 34 urgente", "sin caracteres prohibidos")

// MARK: - Texto

igual(Texto.limpiarEmpresa("Avon Cosmetics, S.A."), "Avon Cosmetics", "quita la forma jurídica")
igual(Texto.limpiarEmpresa("Northwind Trading Ltd"), "Northwind Trading", "quita Ltd")
cierto(!Texto.empiezaPalabra("pliego", en: "el despliegue de red"), "pliego no encaja en despliegue")
cierto(Texto.empiezaPalabra("licitacion", en: "varias licitaciones"), "licitación encaja en licitaciones")
igual(Texto.encabezado("REGISTRO CIVIL DE MADRID\nCERTIFICADO LITERAL DE NACIMIENTO\nNombre: X", excluir: []),
      "Certificado literal de nacimiento", "el encabezado prefiere el tipo de documento")
igual(Texto.encabezado("NORTHWIND TRADING LTD\nINVOICE 88213\n", excluir: []), "Invoice", "encabezado con número")
igual(Texto.empresaEnTexto("Cliente: Mi Empresa S.L.\nSUMINISTROS LEVANTE S.L.", excluir: ["Mi Empresa"]),
      "SUMINISTROS LEVANTE", "ignora tu propia empresa")

// MARK: - Análisis completo

var ajustes = AppSettings()
ajustes.usarIA = false
ajustes.misEmpresas = ["Mi Empresa"]
let avon = Entity(nombre: "AVON", alias: ["Avon Cosmetics"], cif: "A-28123456", tipo: .cliente)
let conf = Configuracion(ajustes: ajustes, entidades: [avon], reglas: Store.ejemploReglas)

let pliego = crearPDF("pliego_v2.pdf", """
    AVON COSMETICS, S.A.  CIF A-28123456
    PLIEGO DE CONDICIONES
    Licitación de 40 vehículos. Plazo hasta el 15/11/2026.
    En Madrid, a 26 de octubre de 2026
    Firmado digitalmente por GARCIA LOPEZ ANA
    """)
let p1 = esperar { await FieldResolver.analizar(pliego, conf) }
igual(p1.nombre, "20261026-AVON-Pliego de condiciones-firmada.pdf", "licitación firmada")
igual(p1.regla, "Licitaciones", "regla de licitaciones")
igual(p1.dudas, [], "sin dudas en la licitación")

let certificado = crearPDF("documento (3).pdf", """
    REGISTRO CIVIL
    CERTIFICADO LITERAL DE NACIMIENTO
    Fecha de nacimiento: 2 de mayo de 1988
    Expedido en Madrid, a 20 de octubre de 2026
    """)
let p2 = esperar { await FieldResolver.analizar(certificado, conf) }
igual(p2.nombre, "20261020-Certificado literal de nacimiento.pdf", "personal sin entidad")
igual(p2.entidad, nil, "lo personal no lleva entidad")

let factura = crearPDF("Factura_245.pdf", """
    SUMINISTROS LEVANTE S.L.  B-46987654
    FACTURA Nº 2026/0245
    Fecha de factura: 14/10/2026
    Cliente: Mi Empresa S.L.
    """)
let p3 = esperar { await FieldResolver.analizar(factura, conf) }
igual(p3.nombre, "20261014-SUMINISTROS LEVANTE-Factura.pdf", "factura de proveedor desconocido")
igual(p3.entidadSugerida, "SUMINISTROS LEVANTE", "propone añadir el proveedor")

var confConLevante = conf
confConLevante.entidades.append(Entity(nombre: "LEVANTE", alias: ["Suministros Levante"], tipo: .proveedor))
let p4 = esperar { await FieldResolver.analizar(factura, confConLevante) }
igual(p4.nombre, "20261014-LEVANTE-Factura.pdf", "una vez añadido, lo reconoce")
igual(p4.entidadSugerida, nil, "ya no hay nada que sugerir")

// MARK: - Duplicados

let copia = carpeta.appendingPathComponent("pliego_v2 (1).pdf")
try! FileManager.default.copyItem(at: pliego, to: copia)
igual(Duplicados.buscar(copia, en: [carpeta])?.resolvingSymlinksInPath().path,
      pliego.resolvingSymlinksInPath().path, "detecta una copia exacta")
igual(Duplicados.buscar(factura, en: [carpeta]), nil, "un archivo distinto no es duplicado")

print(fallos == 0 ? "✓ \(total) pruebas correctas" : "✗ \(fallos) de \(total) pruebas fallan")
exit(fallos == 0 ? 0 : 1)
