import AppKit
import SwiftUI

@MainActor
final class AppModel {
    static let shared = AppModel()

    let store = Store()
    let processor: Processor
    let notifier = Notifier()
    private var watchers: [FolderWatcher] = []

    private init() {
        processor = Processor(store: store)
        processor.notifier = notifier
        notifier.processor = processor
        notifier.configurar()
        store.alCambiarIdioma = { [notifier] in notifier.configurarBotones() }
        reiniciarVigilancia()
        // Después de terminar de crear AppModel: lo que se analiza puede necesitar AppModel.shared.
        DispatchQueue.main.async { [processor] in processor.recuperarPendientes() }
    }

    var carpetasVigiladas: [URL] {
        store.ajustes.carpetas.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) }
    }

    /// La primera carpeta vigilada, para abrir los diálogos de archivo.
    var carpetaVigilada: URL? { carpetasVigiladas.first }

    func reiniciarVigilancia() {
        watchers.forEach { $0.detener() }
        watchers = carpetasVigiladas.map { carpeta in
            FolderWatcher(carpeta: carpeta) { url in
                Task { @MainActor in AppModel.shared.processor.nuevoArchivo(url) }
            }
        }
        watchers.forEach { $0.iniciar() }
    }
}

/// Botón derecho en Finder → Acciones rápidas → «Renombrar con Bautiza».
final class ServicioFinder: NSObject {
    @objc func renombrarArchivos(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        Task { @MainActor in
            for url in urls where !url.hasDirectoryPath {
                AppModel.shared.processor.analizar(url, origen: .manual)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let servicio = ServicioFinder()

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = servicio
        NSUpdateDynamicServices()
    }
}

struct BautizaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegado
    @StateObject private var store = AppModel.shared.store
    @StateObject private var processor = AppModel.shared.processor

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environmentObject(store)
                .environmentObject(processor)
        } label: {
            Image(systemName: processor.pendientes.isEmpty ? "doc.text.magnifyingglass" : "doc.badge.ellipsis")
        }
        .menuBarExtraStyle(.window)
    }
}

/// Ventanas normales (ajustes, pendientes) para una app que solo vive en la barra de menús.
@MainActor
final class Ventanas {
    static let shared = Ventanas()
    private var abiertas: [String: NSWindow] = [:]

    func mostrarAjustes() {
        mostrar("ajustes", L("Ajustes de Bautiza", "Bautiza Settings"), CGSize(width: 760, height: 560)) { SettingsView() }
    }

    func mostrarPendientes() {
        mostrar("pendientes", L("Pendientes de renombrar", "Waiting to be renamed"), CGSize(width: 640, height: 480)) { PendientesView() }
    }

    private func mostrar<V: View>(_ id: String, _ titulo: String, _ tamaño: CGSize, contenido: () -> V) {
        NSApp.activate(ignoringOtherApps: true)
        if let w = abiertas[id] {
            w.title = titulo
            w.makeKeyAndOrderFront(nil)
            return
        }
        let vista = contenido()
            .environmentObject(AppModel.shared.store)
            .environmentObject(AppModel.shared.processor)
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: tamaño),
                         styleMask: [.titled, .closable, .resizable, .miniaturizable],
                         backing: .buffered, defer: false)
        w.title = titulo
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: vista)
        w.setContentSize(tamaño)
        w.center()
        abiertas[id] = w
        w.makeKeyAndOrderFront(nil)
    }
}

@MainActor
func elegirArchivo(empezandoEn carpeta: URL? = nil) -> URL? {
    NSApp.activate(ignoringOtherApps: true)
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.directoryURL = carpeta
    return panel.runModal() == .OK ? panel.url : nil
}

@MainActor
func elegirCarpeta() -> URL? {
    NSApp.activate(ignoringOtherApps: true)
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    return panel.runModal() == .OK ? panel.url : nil
}

/// ~/Downloads en vez de /Users/fulano/Downloads.
func rutaCorta(_ ruta: String) -> String {
    (ruta as NSString).abbreviatingWithTildeInPath
}
