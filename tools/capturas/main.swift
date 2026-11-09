import AppKit
import SwiftUI

// Genera las capturas del README con las vistas reales de Bautiza y datos de demostración.
// Se ejecuta con ./capturas.sh; no toca la configuración real (usa BAUTIZA_DATOS).
// uso: capturas <carpeta de trabajo> <carpeta de salida>

let trabajo = URL(fileURLWithPath: CommandLine.arguments[1])
let salida = URL(fileURLWithPath: CommandLine.arguments[2])
let descargas = trabajo.appendingPathComponent("Descargas")
setenv("BAUTIZA_DATOS", trabajo.appendingPathComponent("datos").path, 1)
try? FileManager.default.createDirectory(at: descargas, withIntermediateDirectories: true)
try? FileManager.default.createDirectory(at: salida, withIntermediateDirectories: true)

let app = NSApplication.shared
app.setActivationPolicy(.regular)

// MARK: - Documentos de demostración

func crearPDF(_ nombre: String, _ texto: String, escaneado: Bool = false) {
    var caja = CGRect(x: 0, y: 0, width: 595, height: 842)
    let ctx = CGContext(descargas.appendingPathComponent(nombre) as CFURL, mediaBox: &caja, nil)!
    ctx.beginPDFPage(nil)
    let atribuido = NSAttributedString(string: texto, attributes: [.font: NSFont.systemFont(ofSize: 13)])
    if escaneado {
        // Una imagen sin texto seleccionable, como un escaneo: obliga a usar OCR.
        let imagen = NSImage(size: caja.size, flipped: false) { r in
            NSColor.white.setFill(); r.fill()
            atribuido.draw(in: r.insetBy(dx: 50, dy: 60))
            return true
        }
        ctx.draw(imagen.cgImage(forProposedRect: nil, context: nil, hints: nil)!, in: caja)
    } else {
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        atribuido.draw(in: caja.insetBy(dx: 50, dy: 60))
    }
    ctx.endPDFPage()
    ctx.closePDF()
}

func crearExcel(_ nombre: String, _ celdas: [String]) {
    let tmp = trabajo.appendingPathComponent("xlsx")
    try? FileManager.default.createDirectory(at: tmp.appendingPathComponent("xl"), withIntermediateDirectories: true)
    let xml = "<?xml version=\"1.0\"?><sst>" + celdas.map { "<si><t>\($0)</t></si>" }.joined() + "</sst>"
    try! xml.write(to: tmp.appendingPathComponent("xl/sharedStrings.xml"), atomically: true, encoding: .utf8)
    let zip = Process()
    zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
    zip.currentDirectoryURL = tmp
    zip.arguments = ["-qr", descargas.appendingPathComponent(nombre).path, "xl"]
    try! zip.run()
    zip.waitUntilExit()
}

crearPDF("pliego_licitacion_vehiculos_v2.pdf", """
    AVON COSMETICS, S.A.
    CIF A-28123456

    PLIEGO DE CONDICIONES
    Licitación para el suministro en renting de 40 vehículos comerciales

    1. Objeto. El presente pliego regula la licitación...
    2. Plazo de presentación de ofertas: hasta el 15/11/2026.

    En Madrid, a 26 de octubre de 2026

    Firmado digitalmente por GARCIA LOPEZ ANA - 12345678Z
    """)
crearPDF("Factura_000245.pdf", """
    SUMINISTROS LEVANTE S.L.  -  B-46987654
    FACTURA Nº 2026/0245
    Fecha de factura: 14/10/2026
    Vencimiento: 14/11/2026

    Cliente: Mi Empresa S.L.
    Concepto: Material de oficina ........ 245,00 €
    """)
crearPDF("scan0001.pdf", """
    CONTRATO DE MANTENIMIENTO

    Entre AVON COSMETICS S.A. y Mi Empresa S.L.

    Fecha: 3 de septiembre de 2026

    El presente contrato regula el mantenimiento de la flota.
    """, escaneado: true)
crearPDF("documento (3).pdf", """
    REGISTRO CIVIL DE MADRID
    CERTIFICADO LITERAL DE NACIMIENTO

    Fecha de nacimiento: 12 de marzo de 1990

    Expedido en Madrid, a 20 de octubre de 2026
    """)
crearExcel("presupuesto_v3_FINAL.xlsx",
           ["AVON COSMETICS S.A.", "PRESUPUESTO RENTING FLOTA", "Fecha: 22/10/2026", "Vehículo", "Cuota mensual"])

// MARK: - Captura de vistas

let fondo = LinearGradient(
    colors: [Color(red: 0.24, green: 0.36, blue: 0.93), Color(red: 0.58, green: 0.30, blue: 0.86)],
    startPoint: .topLeading, endPoint: .bottomTrailing)

/// Pinta una vista a 2x tal como se ve en pantalla.
@MainActor
func capturar<V: View>(_ vista: V, ancho: CGFloat, alto: CGFloat? = nil) -> NSImage {
    let host = NSHostingView(rootView: vista.background(Color(nsColor: .windowBackgroundColor)))
    host.appearance = NSAppearance(named: .aqua)
    let ventana = NSWindow(contentRect: NSRect(x: -5000, y: -5000, width: ancho, height: alto ?? 600),
                          styleMask: [.titled], backing: .buffered, defer: false)
    ventana.appearance = NSAppearance(named: .aqua)
    ventana.contentView = host
    if let alto {
        host.frame.size = CGSize(width: ancho, height: alto)
    } else {
        host.frame.size = CGSize(width: ancho, height: 2000)
        host.layoutSubtreeIfNeeded()
        host.frame.size = CGSize(width: ancho, height: host.fittingSize.height)
    }
    ventana.setContentSize(host.frame.size)
    NSApp.activate(ignoringOtherApps: true)
    ventana.makeKeyAndOrderFront(nil)
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(1.2))
    let b = host.bounds
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(b.width * 2), pixelsHigh: Int(b.height * 2),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = b.size
    host.cacheDisplay(in: b, to: rep)
    ventana.orderOut(nil)
    let imagen = NSImage(size: b.size)
    imagen.addRepresentation(rep)
    return imagen
}

/// Ventana con barra de título sobre el fondo de color.
struct Marco: View {
    let imagen: NSImage
    var titulo: String?

    var body: some View {
        VStack(spacing: 0) {
            if let titulo {
                ZStack {
                    Text(titulo).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Circle().fill(Color(red: 1, green: 0.37, blue: 0.34))
                        Circle().fill(Color(red: 1, green: 0.74, blue: 0.18))
                        Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.25))
                        Spacer()
                    }
                    .frame(height: 12)
                    .padding(.horizontal, 14)
                }
                .frame(height: 30)
                .background(Color(nsColor: .windowBackgroundColor))
                Divider()
            }
            Image(nsImage: imagen).resizable().frame(width: imagen.size.width, height: imagen.size.height)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.black.opacity(0.12)))
        .shadow(color: .black.opacity(0.35), radius: 28, y: 14)
    }
}

@MainActor
func guardar<V: View>(_ vista: V, _ nombre: String) {
    let r = ImageRenderer(content: vista.environment(\.colorScheme, .light))
    r.scale = 2
    guard let cg = r.cgImage else { print("✗ \(nombre)"); return }
    try! NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!
        .write(to: salida.appendingPathComponent(nombre))
    print("✓ \(nombre) \(cg.width)x\(cg.height)")
}

struct Panel: View {
    let titulo: String
    let filas: [(nombre: String, ext: String)]
    var resaltar = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(.blue)
                Text(titulo).font(.system(size: 14, weight: .semibold))
            }
            .padding(14)
            Divider()
            ForEach(Array(filas.enumerated()), id: \.offset) { i, f in
                HStack(spacing: 10) {
                    Image(nsImage: NSWorkspace.shared.icon(for: .init(filenameExtension: f.ext) ?? .data))
                        .resizable().frame(width: 30, height: 30)
                    Text(f.nombre)
                        .font(.system(size: 15, weight: resaltar ? .medium : .regular,
                                      design: resaltar ? .monospaced : .default))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 7)
                .padding(.horizontal, 12)
                .background(i % 2 == 1 ? Color.black.opacity(0.035) : .clear)
            }
        }
        .frame(width: 520, alignment: .leading)
        .padding(.bottom, 8)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 24, y: 12)
    }
}

// MARK: - Pantallas

@MainActor
func generar() async {
    let store = Store()
    store.ajustes.idioma = .es
    store.ajustes.usarIA = false
    store.ajustes.misEmpresas = ["Mi Empresa"]
    store.entidades = [
        Entity(nombre: "AVON", alias: ["Avon Cosmetics"], cif: "A-28123456", tipo: .cliente),
        Entity(nombre: "LEVANTE", alias: ["Suministros Levante"], cif: "B-46987654", tipo: .proveedor),
    ]
    if let i = store.reglas.firstIndex(where: { $0.nombre == "Licitaciones" }) {
        store.reglas[i].destino = "~/Documents/Clientes/{entidad}/Licitaciones"
    }
    let processor = Processor(store: store)

    let orden = ["pliego_licitacion_vehiculos_v2.pdf", "scan0001.pdf", "Factura_000245.pdf",
                 "presupuesto_v3_FINAL.xlsx", "documento (3).pdf"]
    var propuestas: [Propuesta] = []
    for nombre in orden {
        propuestas.append(await FieldResolver.analizar(descargas.appendingPathComponent(nombre), store.configuracion))
    }
    for p in propuestas { print("  \(p.url.lastPathComponent) → \(p.nombre)") }

    guardar(
        VStack(spacing: 26) {
            Text("Descargas, antes y después de Bautiza").font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
            HStack(spacing: 28) {
                Panel(titulo: "Antes", filas: propuestas.map { ($0.url.lastPathComponent, $0.url.pathExtension) })
                Image(systemName: "arrow.right").font(.system(size: 34, weight: .bold)).foregroundStyle(.white)
                Panel(titulo: "Después", filas: propuestas.map { ($0.nombre, $0.url.pathExtension) }, resaltar: true)
            }
            Text("Lee cada documento: fecha · cliente o proveedor · asunto · si está firmado")
                .font(.system(size: 17, weight: .medium)).foregroundStyle(.white.opacity(0.9))
        }
        .padding(56).background(fondo),
        "1-antes-despues.png")

    processor.pendientes = propuestas.filter {
        ["pliego_licitacion_vehiculos_v2.pdf", "Factura_000245.pdf"].contains($0.url.lastPathComponent)
    }
    let pendientes = capturar(PendientesView().environmentObject(processor), ancho: 640, alto: 520)
    guardar(Marco(imagen: pendientes, titulo: "Pendientes de renombrar").padding(60).background(fondo), "2-pendientes.png")
    processor.pendientes = []

    store.historial = propuestas.reversed().enumerated().map { i, p in
        HistoryEntry(fecha: Date().addingTimeInterval(Double(-i * 900)),
                     original: p.url.path, nuevo: p.carpetaDestino.appendingPathComponent(p.nombre).path)
    }
    let menu = capturar(MenuContent().environmentObject(store).environmentObject(processor), ancho: 340)
    let editor = capturar(EditorRegla(regla: .constant(store.reglas.first { $0.nombre == "Personal" }!)), ancho: 520, alto: 640)
    guardar(
        HStack(alignment: .top, spacing: 40) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Barra de menús", systemImage: "menubar.rectangle").font(.headline).foregroundStyle(.white)
                Marco(imagen: menu)
            }
            VStack(alignment: .leading, spacing: 10) {
                Label("Reglas: lo personal, sin cliente", systemImage: "list.bullet.rectangle").font(.headline).foregroundStyle(.white)
                Marco(imagen: editor, titulo: "Ajustes de Bautiza")
            }
        }
        .padding(60).background(fondo),
        "3-menu-y-reglas.png")

    let general = capturar(AjustesGenerales().environmentObject(store), ancho: 620, alto: 1010)
    guardar(Marco(imagen: general, titulo: "Ajustes de Bautiza").padding(60).background(fondo), "4-ajustes.png")

    let permisos = capturar(PermisosView().environmentObject(store), ancho: 640, alto: 430)
    guardar(Marco(imagen: permisos, titulo: "Ajustes de Bautiza").padding(60).background(fondo), "5-permisos.png")
}

Task { @MainActor in
    await generar()
    exit(0)
}
app.run()
