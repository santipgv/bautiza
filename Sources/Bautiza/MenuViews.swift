import AppKit
import SwiftUI

struct MenuContent: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var processor: Processor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bautiza").font(.headline)
                    Text(store.ajustes.pausado ? L("En pausa", "Paused") : L("Vigilando", "Watching") + " " + resumenCarpetas)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle(L("Activo", "Active"), isOn: Binding(get: { !store.ajustes.pausado }, set: { store.ajustes.pausado = !$0 }))
                    .toggleStyle(.switch).labelsHidden().controlSize(.small)
            }

            if !processor.analizando.isEmpty {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(L("Leyendo \(processor.analizando.count) archivo(s)…", "Reading \(processor.analizando.count) file(s)…")).font(.caption)
                }
            }

            if !processor.pendientes.isEmpty {
                Button {
                    Ventanas.shared.mostrarPendientes()
                } label: {
                    Label(L("Revisar \(processor.pendientes.count) pendiente(s)", "Review \(processor.pendientes.count) pending"), systemImage: "tray.full")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            if let error = processor.ultimoError {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }

            Divider()
            Text(L("Últimos renombrados", "Recently renamed")).font(.caption).foregroundStyle(.secondary)
            if store.historial.isEmpty {
                Text(L("Todavía nada", "Nothing yet")).font(.callout).foregroundStyle(.tertiary)
            }
            ForEach(store.historial.prefix(5)) { e in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(e.nombreNuevo).lineLimit(1).truncationMode(.middle)
                            .strikethrough(e.deshecho)
                        Text(e.nombreOriginal).font(.caption2).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    if !e.deshecho {
                        Button { processor.deshacer(e) } label: { Image(systemName: "arrow.uturn.backward") }
                            .buttonStyle(.borderless).help(L("Deshacer", "Undo"))
                    }
                }
            }

            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Button(L("Renombrar un archivo…", "Rename a file…")) {
                    if let url = elegirArchivo(empezandoEn: AppModel.shared.carpetaVigilada) {
                        processor.analizar(url, origen: .manual)
                    }
                }
                Button(L("Ajustes…", "Settings…")) { Ventanas.shared.mostrarAjustes() }
                Button(L("Salir de Bautiza", "Quit Bautiza")) { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 340)
    }
}

extension MenuContent {
    /// "~/Downloads" o "~/Downloads y 2 más".
    var resumenCarpetas: String {
        guard let primera = store.ajustes.carpetas.first else { return L("ninguna carpeta", "no folder") }
        let resto = store.ajustes.carpetas.count - 1
        return rutaCorta(primera) + (resto > 0 ? L(" y \(resto) más", " and \(resto) more") : "")
    }
}

struct PendientesView: View {
    @EnvironmentObject var processor: Processor

    var body: some View {
        VStack(spacing: 0) {
            if processor.pendientes.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle").font(.largeTitle).foregroundStyle(.secondary)
                    Text(L("No hay nada pendiente", "Nothing waiting")).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(processor.pendientes) { p in TarjetaPendiente(p: p) }
                    }
                    .padding()
                }
                Divider()
                HStack {
                    Text(L("\(processor.pendientes.count) pendiente(s)", "\(processor.pendientes.count) pending")).foregroundStyle(.secondary)
                    Spacer()
                    Button(L("Aceptar todos", "Accept all")) {
                        for p in processor.pendientes { processor.aplicar(p, nombre: p.nombre) }
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 520, minHeight: 300)
    }
}

struct TarjetaPendiente: View {
    let p: Propuesta
    @EnvironmentObject var processor: Processor
    @State private var nombre = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "doc")
                Text(p.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button { NSWorkspace.shared.open(p.url) } label: { Image(systemName: "eye") }
                    .buttonStyle(.borderless).help(L("Abrir el archivo", "Open the file"))
            }
            .font(.caption).foregroundStyle(.secondary)

            TextField(L("Nuevo nombre", "New name"), text: $nombre)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
                .onSubmit { processor.aplicar(p, nombre: nombre) }

            DetallesPropuesta(p: p)

            if p.mueveDeCarpeta {
                Label(L("Se moverá a", "Will be moved to") + " \(rutaCorta(p.carpetaDestino.path))", systemImage: "folder")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(p.dudas, id: \.self) { d in
                Label(d, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }

            if let sugerida = p.entidadSugerida {
                HStack(spacing: 8) {
                    Text(L("¿Añadir «\(sugerida)» a tu lista como…", "Add “\(sugerida)” to your list as…"))
                        .font(.caption).foregroundStyle(.secondary)
                    Button(L("Cliente", "Client")) { processor.añadirEntidad(sugerida, tipo: .cliente) }
                    Button(L("Proveedor", "Supplier")) { processor.añadirEntidad(sugerida, tipo: .proveedor) }
                }
                .controlSize(.small)
            }

            HStack {
                Button(L("Ignorar", "Ignore")) { processor.ignorar(p) }
                if p.duplicadoDe != nil {
                    Button(L("Mover a la Papelera", "Move to Trash"), role: .destructive) { processor.tirarDuplicado(p) }
                }
                Spacer()
                Button(L("Aceptar", "Accept")) { processor.aplicar(p, nombre: nombre) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
        .onAppear { nombre = p.nombre }
    }
}

/// Qué dato ha salido de dónde.
struct DetallesPropuesta: View {
    let p: Propuesta

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
            fila(L("Fecha", "Date"), p.fecha.map { $0.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: Loc.locale)) }, p.fechaOrigen)
            fila(L("Entidad", "Entity"), p.entidad, p.entidadOrigen)
            fila(L("Asunto", "Subject"), p.asunto, p.asuntoOrigen)
            fila(L("Firmada", "Signed"), p.firmada ? L("Sí", "Yes") : L("No", "No"), p.firmaOrigen)
            fila(L("Regla", "Rule"), p.regla ?? L("Por defecto", "Default"), [p.ocr ? "OCR" : nil, p.usoIA ? "IA" : nil].compactMap { $0 }.joined(separator: " · "))
        }
        .font(.caption)
    }

    private func fila(_ etiqueta: String, _ valor: String?, _ origen: String) -> some View {
        GridRow {
            Text(etiqueta).foregroundStyle(.secondary)
            Text(valor ?? "—")
            Text(origen).foregroundStyle(.tertiary)
        }
    }
}
