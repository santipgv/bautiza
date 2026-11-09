import AppKit
import ServiceManagement
import SwiftUI
import UserNotifications

struct SettingsView: View {
    /// Ajustes se abre en la última pestaña usada.
    @AppStorage("pestanaAjustes") private var pestaña = "general"

    var body: some View {
        TabView(selection: $pestaña) {
            AjustesGenerales().tabItem { Label("General", systemImage: "gearshape") }.tag("general")
            EntidadesView().tabItem { Label(L("Clientes y proveedores", "Clients and suppliers"), systemImage: "building.2") }
                .tag("entidades")
            ReglasView().tabItem { Label(L("Reglas", "Rules"), systemImage: "list.bullet.rectangle") }.tag("reglas")
            ProbarView().tabItem { Label(L("Probar", "Try it"), systemImage: "wand.and.stars") }.tag("probar")
            HistorialView().tabItem { Label(L("Historial", "History"), systemImage: "clock.arrow.circlepath") }
                .tag("historial")
            PermisosView().tabItem { Label(L("Permisos", "Permissions"), systemImage: "lock.shield") }.tag("permisos")
        }
        .padding()
        .frame(minWidth: 680, minHeight: 480)
    }
}

// MARK: - General

struct AjustesGenerales: View {
    @EnvironmentObject var store: Store
    @State private var alIniciar = SMAppService.mainApp.status == .enabled
    @State private var misEmpresas = ""

    var body: some View {
        Form {
            Section(L("Idioma", "Language")) {
                Picker(L("Idioma", "Language"), selection: $store.ajustes.idioma) {
                    ForEach(Idioma.allCases) { Text($0.titulo).tag($0) }
                }
            }
            Section(L("Carpetas vigiladas", "Watched folders")) {
                ForEach(store.ajustes.carpetas, id: \.self) { carpeta in
                    HStack {
                        Image(systemName: "folder")
                        Text(rutaCorta(carpeta))
                        Spacer()
                        Button {
                            store.ajustes.carpetas.removeAll { $0 == carpeta }
                            AppModel.shared.reiniciarVigilancia()
                        } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                        .help(L("Dejar de vigilar", "Stop watching"))
                        .accessibilityLabel(L("Dejar de vigilar \(rutaCorta(carpeta))", "Stop watching \(rutaCorta(carpeta))"))
                    }
                }
                Button(L("Añadir carpeta…", "Add folder…")) {
                    if let url = elegirCarpeta() {
                        let ruta = rutaCorta(url.path)
                        if !store.ajustes.carpetas.contains(ruta) { store.ajustes.carpetas.append(ruta) }
                        AppModel.shared.reiniciarVigilancia()
                    }
                }
            }
            Section(L("Qué archivos renombrar al descargarse", "Which files to rename when downloaded")) {
                ForEach(TipoArchivo.allCases) { tipo in
                    Toggle(tipo.titulo, isOn: Binding(
                        get: { store.ajustes.tiposVigilados.contains(tipo) },
                        set: { activo in
                            store.ajustes.tiposVigilados.removeAll { $0 == tipo }
                            if activo { store.ajustes.tiposVigilados.append(tipo) }
                        }))
                }
                Text(L("Los demás se ignoran. Con el botón derecho en Finder puedes renombrar cualquier archivo.", "Others are ignored. You can rename any file by right-clicking it in Finder."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("Aprobación", "Approval")) {
                Picker(L("Cuando llega un archivo", "When a file arrives"), selection: $store.ajustes.modo) {
                    ForEach(ApprovalMode.allCases) { Text($0.titulo).tag($0) }
                }
            }
            Section(L("Fecha", "Date")) {
                Picker(L("Qué fecha usar", "Which date to use"), selection: $store.ajustes.fuenteFecha) {
                    ForEach(DateSource.allCases) { Text($0.titulo).tag($0) }
                }
                TextField(L("Formato", "Format"), text: $store.ajustes.formatoFecha)
                Text(L("Hoy quedaría así: \(ejemploFecha). yyyy = año, MM = mes, dd = día.", "Today it would be: \(ejemploFecha). yyyy = year, MM = month, dd = day."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("Nombre por defecto (si ninguna regla dice otra cosa)", "Default name (unless a rule says otherwise)")) {
                TextField(L("Plantilla", "Template"), text: $store.ajustes.plantillaPorDefecto)
                    .font(.body.monospaced())
                TextField(L("Si no se encuentra la entidad", "If no entity is found"), text: $store.ajustes.textoSinEntidad)
                AyudaPlantilla()
            }
            Section(L("Tu empresa", "Your company")) {
                TextField(L("Nombres de tu empresa", "Your company's names"), text: $misEmpresas, prompt: Text(L("Mi Empresa, Mi Empresa S.L.", "My Company, My Company Ltd")))
                    .onChange(of: misEmpresas) { _, v in store.ajustes.misEmpresas = lista(v) }
                Text(L("Separados por comas. Así no se confunde tu empresa con un cliente o proveedor.", "Comma-separated. Keeps your company from being mistaken for a client or supplier."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("Inteligencia artificial local", "On-device AI")) {
                Toggle(L("Usar la IA de Apple para deducir asunto, entidad y fecha", "Use Apple's AI to work out subject, entity and date"), isOn: $store.ajustes.usarIA)
                Text(LocalAI.estado).font(.caption).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Instrucciones para la IA", "Instructions for the AI"))
                    TextEditor(text: $store.ajustes.instruccionesIA)
                        .font(.callout)
                        .frame(minHeight: 90)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                    Text(L("Explícale con tus palabras qué es personal, qué fecha usar o cómo resumir el asunto. Por ejemplo: «Los documentos del proyecto Faro son de AVON».", "Tell it in your own words what counts as personal, which date to use or how to sum up the subject. For example: “Project Faro documents belong to AVON”."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section(L("Inicio", "Startup")) {
                Toggle(L("Abrir Bautiza al iniciar sesión", "Open Bautiza at login"), isOn: $alIniciar)
                    .onChange(of: alIniciar) { _, activar in
                        do {
                            if activar { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            alIniciar = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
        }
        .formStyle(.grouped)
        .onAppear { misEmpresas = store.ajustes.misEmpresas.joined(separator: ", ") }
    }

    private var ejemploFecha: String {
        let f = DateFormatter()
        f.locale = Loc.locale
        f.dateFormat = store.ajustes.formatoFecha
        return f.string(from: Date())
    }
}

struct AyudaPlantilla: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(L("Campos: {fecha} {entidad} {asunto} {firmada} {tipo} {original}",
                   "Fields: {date} {entity} {subject} {signed} {type} {original} (Spanish names work too)"))
            Text(L("{fecha:yyyy-MM} cambia el formato · {entidad:MAYUS} / :minus / :Titulo",
                   "{date:yyyy-MM} changes the format · {entity:upper} / :lower / :title"))
            Text(L("{firmada?firmada} escribe «firmada» solo si lo está; vale con cualquier texto",
                   "{signed?signed} writes “signed” only if it is; any text works"))
            Text(L("Si falta un dato, los guiones que sobran se quitan solos.", "If something is missing, leftover dashes are removed."))
        }
        .font(.caption).foregroundStyle(.secondary)
    }
}

// MARK: - Entidades

struct EntidadesView: View {
    @EnvironmentObject var store: Store
    @State private var seleccion: UUID?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $seleccion) {
                    ForEach(store.entidades) { e in
                        VStack(alignment: .leading) {
                            Text(e.nombre.isEmpty ? L("Sin nombre", "Untitled") : e.nombre)
                            Text(e.tipo.titulo).font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(e.id)
                    }
                }
                BarraLista(añadir: {
                    let e = Entity(nombre: L("NUEVA", "NEW"))
                    store.entidades.append(e)
                    seleccion = e.id
                }, quitar: seleccion == nil ? nil : {
                    store.entidades.removeAll { $0.id == seleccion }
                    seleccion = nil
                })
            }
            .frame(width: 210)
            Divider()
            if let id = seleccion, store.entidades.contains(where: { $0.id == id }) {
                EditorEntidad(entidad: enlace(id)).id(id)
            } else {
                Indicacion(texto: L("Añade tus clientes y proveedores. Bautiza los busca en el texto por nombre, otros nombres o CIF.", "Add your clients and suppliers. Bautiza looks for them in the text by name, other names or tax ID."))
            }
        }
    }

    private func enlace(_ id: UUID) -> Binding<Entity> {
        Binding(
            get: { store.entidades.first { $0.id == id } ?? Entity(nombre: "") },
            set: { nuevo in
                if let i = store.entidades.firstIndex(where: { $0.id == id }) { store.entidades[i] = nuevo }
            })
    }
}

struct EditorEntidad: View {
    @Binding var entidad: Entity
    @State private var alias = ""

    var body: some View {
        Form {
            TextField(L("Nombre en el archivo", "Name in the file"), text: $entidad.nombre)
            TextField(L("Otros nombres", "Other names"), text: $alias, prompt: Text(L("Avon Cosmetics, Avon España", "Avon Cosmetics, Avon UK")))
                .onChange(of: alias) { _, v in entidad.alias = lista(v) }
            TextField(L("CIF / NIF", "Tax ID (CIF / VAT)"), text: $entidad.cif)
            Picker(L("Tipo", "Type"), selection: $entidad.tipo) {
                ForEach(EntityKind.allCases) { Text($0.titulo).tag($0) }
            }
            Text(L("«Otros nombres» separados por comas: cómo puede aparecer escrito en los documentos. El CIF es la pista más fiable.", "“Other names”, comma-separated: how it may be written in documents. The tax ID is the most reliable clue."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .onAppear { alias = entidad.alias.joined(separator: ", ") }
    }
}

// MARK: - Reglas

struct ReglasView: View {
    @EnvironmentObject var store: Store
    @State private var seleccion: UUID?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $seleccion) {
                    ForEach(store.reglas) { r in
                        HStack {
                            Text(r.nombre.isEmpty ? L("Sin nombre", "Untitled") : r.nombre)
                                .foregroundStyle(r.activa ? .primary : .secondary)
                            Spacer()
                            if !r.activa { Text("off").font(.caption2).foregroundStyle(.secondary) }
                        }
                        .tag(r.id)
                    }
                    .onMove { store.reglas.move(fromOffsets: $0, toOffset: $1) }
                }
                BarraLista(añadir: {
                    let r = Rule(nombre: L("Nueva regla", "New rule"))
                    store.reglas.append(r)
                    seleccion = r.id
                }, quitar: seleccion == nil ? nil : {
                    store.reglas.removeAll { $0.id == seleccion }
                    seleccion = nil
                })
                Text(L("Gana la primera que encaje. Arrastra para ordenar.", "The first match wins. Drag to reorder."))
                    .font(.caption2).foregroundStyle(.secondary).padding(.bottom, 6)
            }
            .frame(width: 210)
            Divider()
            if let id = seleccion, store.reglas.contains(where: { $0.id == id }) {
                EditorRegla(regla: enlace(id)).id(id)
            } else {
                Indicacion(texto: L("Las reglas deciden qué plantilla y qué carpeta usar según el contenido. Si ninguna encaja se usa la plantilla por defecto.", "Rules decide which template and folder to use based on the content. If none matches, the default template is used."))
            }
        }
    }

    private func enlace(_ id: UUID) -> Binding<Rule> {
        Binding(
            get: { store.reglas.first { $0.id == id } ?? Rule(nombre: "") },
            set: { nueva in
                if let i = store.reglas.firstIndex(where: { $0.id == id }) { store.reglas[i] = nueva }
            })
    }
}

struct EditorRegla: View {
    @Binding var regla: Rule
    @State private var palabras = ""
    @State private var extensiones = ""

    var body: some View {
        Form {
            Section {
                TextField(L("Nombre", "Name"), text: $regla.nombre)
                Toggle(L("Activa", "Active"), isOn: $regla.activa)
            }
            Section(L("Cuándo se aplica (las condiciones vacías no cuentan)", "When it applies (empty conditions are ignored)")) {
                TextField(L("El texto contiene alguna de", "Text contains any of"), text: $palabras, prompt: Text(L("licitación, pliego", "tender, invoice")))
                    .onChange(of: palabras) { _, v in regla.palabrasClave = lista(v) }
                TextField(L("Tipo de archivo", "File type"), text: $extensiones, prompt: Text("pdf, docx"))
                    .onChange(of: extensiones) { _, v in regla.extensiones = lista(v) }
                Picker(L("La entidad es", "Entity is"), selection: $regla.tipoEntidad) {
                    Text(L("Cualquiera", "Any")).tag(EntityKind?.none)
                    ForEach(EntityKind.allCases) { Text($0.titulo).tag(EntityKind?.some($0)) }
                }
                TextField(L("Descargado de una web que contiene", "Downloaded from a site containing"), text: $regla.origenContiene, prompt: Text("avon.com"))
            }
            Section(L("Qué hace", "What it does")) {
                TextField(L("Plantilla", "Template"), text: $regla.plantilla, prompt: Text(L("(la de por defecto)", "(the default one)")))
                    .font(.body.monospaced())
                TextField(L("Asunto fijo", "Fixed subject"), text: $regla.asuntoFijo, prompt: Text(L("(deducirlo del documento)", "(work it out from the document)")))
                Picker(L("Entidad", "Entity"), selection: $regla.modoEntidad) {
                    ForEach(ModoEntidad.allCases) { Text($0.titulo).tag($0) }
                }
                if regla.modoEntidad == .fija {
                    TextField(L("Texto de la entidad", "Entity text"), text: $regla.entidadFija, prompt: Text(L("AVON, Proyecto Faro…", "AVON, Project Faro…")))
                }
                HStack {
                    TextField(L("Mover a", "Move to"), text: $regla.destino, prompt: Text(L("(dejarlo en su carpeta)", "(leave it where it is)")))
                    Button(L("Elegir…", "Choose…")) {
                        if let url = elegirCarpeta() { regla.destino = rutaCorta(url.path) }
                    }
                }
                Text(L("La carpeta admite campos, p. ej. ~/Documents/Clientes/{entidad}", "The folder can use fields, e.g. ~/Documents/Clients/{entity}"))
                    .font(.caption).foregroundStyle(.secondary)
                AyudaPlantilla()
            }
        }
        .formStyle(.grouped)
        .onAppear {
            palabras = regla.palabrasClave.joined(separator: ", ")
            extensiones = regla.extensiones.joined(separator: ", ")
        }
    }
}

// MARK: - Probar

struct ProbarView: View {
    @EnvironmentObject var store: Store
    @State private var propuesta: Propuesta?
    @State private var analizando = false
    @State private var encima = false

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Image(systemName: "arrow.down.doc").font(.largeTitle).foregroundStyle(.secondary)
                Text(L("Arrastra aquí un archivo para ver qué nombre le pondría", "Drop a file here to see what name it would get"))
                Button(L("Elegir archivo…", "Choose file…")) {
                    if let url = elegirArchivo(empezandoEn: AppModel.shared.carpetaVigilada) { probar(url) }
                }
                Text(L("No se renombra nada", "Nothing gets renamed")).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 150)
            .background(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
                .foregroundStyle(encima ? Color.accentColor : Color.secondary.opacity(0.4)))
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                probar(url)
                return true
            } isTargeted: { encima = $0 }

            if analizando {
                ProgressView(L("Leyendo…", "Reading…"))
            } else if let p = propuesta {
                VStack(alignment: .leading, spacing: 10) {
                    Text(p.url.lastPathComponent).font(.caption).foregroundStyle(.secondary)
                    Text(p.nombre).font(.title3.monospaced()).textSelection(.enabled)
                    DetallesPropuesta(p: p)
                    if p.mueveDeCarpeta {
                        Label(L("Se movería a", "Would be moved to") + " \(rutaCorta(p.carpetaDestino.path))", systemImage: "folder").font(.caption)
                    }
                    ForEach(p.dudas, id: \.self) { d in
                        Label(d, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer()
        }
        .padding()
    }

    private func probar(_ url: URL) {
        analizando = true
        let conf = store.configuracion
        Task {
            let p = await Task.detached { await FieldResolver.analizar(url, conf) }.value
            propuesta = p
            analizando = false
        }
    }
}

// MARK: - Historial

struct HistorialView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var processor: Processor

    var body: some View {
        if store.historial.isEmpty {
            Indicacion(texto: L("Aquí aparecerá cada archivo renombrado, con opción de deshacer.", "Every renamed file will show up here, with undo."))
        } else {
            List(store.historial) { e in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.nombreNuevo).strikethrough(e.deshecho)
                        Text(L("antes", "before") + ": \(e.nombreOriginal)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(e.fecha.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: Loc.locale))).font(.caption).foregroundStyle(.secondary)
                    Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: e.deshecho ? e.original : e.nuevo)]) } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .buttonStyle(.borderless).help(L("Mostrar en Finder", "Show in Finder"))
                    .accessibilityLabel(L("Mostrar en Finder", "Show in Finder"))
                    Button { processor.deshacer(e) } label: { Image(systemName: "arrow.uturn.backward") }
                        .buttonStyle(.borderless).help(L("Deshacer", "Undo")).disabled(e.deshecho)
                        .accessibilityLabel(L("Deshacer «\(e.nombreNuevo)»", "Undo “\(e.nombreNuevo)”"))
                }
            }
        }
    }
}

// MARK: - Permisos

/// Estado de todo lo que Bautiza necesita del sistema, con un botón al sitio donde se cambia.
struct PermisosView: View {
    @EnvironmentObject var store: Store
    @State private var notificaciones: UNAuthorizationStatus?
    @State private var refresco = 0

    var body: some View {
        Form {
            Section(L("Carpetas vigiladas", "Watched folders")) {
                ForEach(store.ajustes.carpetas, id: \.self) { carpeta in
                    let ok = puedeLeer(carpeta)
                    FilaPermiso(
                        estado: ok ? .bien : .mal,
                        titulo: rutaCorta(carpeta),
                        detalle: ok ? L("Bautiza puede leerla", "Bautiza can read it")
                                    : L("Sin acceso: permítelo en Archivos y carpetas", "No access: allow it in Files and Folders"),
                        boton: ok ? nil : L("Abrir privacidad…", "Open Privacy…"),
                        url: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")
                }
            }
            Section(L("Sistema", "System")) {
                FilaPermiso(
                    estado: notificaciones == .authorized || notificaciones == .provisional ? .bien
                        : notificaciones == nil || notificaciones == .notDetermined ? .info : .mal,
                    titulo: L("Notificaciones", "Notifications"),
                    detalle: textoNotificaciones,
                    boton: L("Abrir notificaciones…", "Open Notifications…"),
                    url: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(Bundle.main.bundleIdentifier ?? "")")
                FilaPermiso(
                    estado: LocalAI.disponible ? .bien : .info,
                    titulo: L("IA de Apple", "Apple's AI"),
                    detalle: LocalAI.estado,
                    boton: LocalAI.disponible ? nil : L("Abrir Apple Intelligence…", "Open Apple Intelligence…"),
                    url: "x-apple.systempreferences:com.apple.Siri-Settings.extension")
                FilaPermiso(
                    estado: SMAppService.mainApp.status == .enabled ? .bien : .info,
                    titulo: L("Abrir al iniciar sesión", "Open at login"),
                    detalle: SMAppService.mainApp.status == .enabled ? L("Activado", "On")
                        : L("Desactivado: actívalo en la pestaña General", "Off: turn it on in the General tab"),
                    boton: nil, url: nil)
                FilaPermiso(
                    estado: .info,
                    titulo: L("Botón derecho en Finder", "Right-click in Finder"),
                    detalle: L("Si no ves «Renombrar con Bautiza», actívalo en Teclado → Funciones rápidas → Servicios",
                               "If “Rename with Bautiza” is missing, turn it on in Keyboard → Keyboard Shortcuts → Services"),
                    boton: L("Abrir Teclado…", "Open Keyboard…"),
                    url: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
            }
        }
        .formStyle(.grouped)
        .id(refresco)
        .task { await leerNotificaciones() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Al volver de Ajustes del Sistema, el estado puede haber cambiado.
            refresco += 1
            Task { await leerNotificaciones() }
        }
    }

    private func puedeLeer(_ carpeta: String) -> Bool {
        (try? FileManager.default.contentsOfDirectory(atPath: (carpeta as NSString).expandingTildeInPath)) != nil
    }

    private func leerNotificaciones() async {
        guard Bundle.main.bundleIdentifier != nil else { return }
        notificaciones = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private var textoNotificaciones: String {
        switch notificaciones {
        case .authorized, .provisional, .ephemeral: return L("Activadas", "On")
        case .denied: return L("Desactivadas: no verás las propuestas al descargar", "Off: you won't see proposals when downloading")
        default: return L("Aún sin decidir", "Not decided yet")
        }
    }
}

struct FilaPermiso: View {
    enum Estado { case bien, mal, info }
    let estado: Estado
    let titulo: String
    let detalle: String
    let boton: String?
    let url: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icono).foregroundStyle(color)
                .accessibilityLabel(estado == .bien ? L("Correcto", "OK") : estado == .mal ? L("Falta", "Missing") : L("Información", "Info"))
            VStack(alignment: .leading, spacing: 2) {
                Text(titulo)
                Text(detalle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let boton, let url, let destino = URL(string: url) {
                Button(boton) { NSWorkspace.shared.open(destino) }
            }
        }
    }

    private var icono: String {
        switch estado {
        case .bien: return "checkmark.circle.fill"
        case .mal: return "exclamationmark.triangle.fill"
        case .info: return "info.circle"
        }
    }

    private var color: Color {
        switch estado {
        case .bien: return .green
        case .mal: return .orange
        case .info: return .secondary
        }
    }
}

// MARK: - Piezas comunes

struct BarraLista: View {
    let añadir: () -> Void
    let quitar: (() -> Void)?

    var body: some View {
        HStack {
            Button(action: añadir) { Image(systemName: "plus") }
                .help(L("Añadir", "Add")).accessibilityLabel(L("Añadir", "Add"))
            Button { quitar?() } label: { Image(systemName: "minus") }.disabled(quitar == nil)
                .help(L("Quitar el seleccionado", "Remove selected")).accessibilityLabel(L("Quitar el seleccionado", "Remove selected"))
            Spacer()
        }
        .buttonStyle(.borderless)
        .padding(8)
    }
}

struct Indicacion: View {
    let texto: String
    var body: some View {
        Text(texto)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// "a, b ,c" → ["a", "b", "c"]
func lista(_ texto: String) -> [String] {
    texto.split(separator: ",").map { String($0).recortado }.filter { !$0.isEmpty }
}
