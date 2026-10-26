import AppKit
import UserNotifications

/// Notificaciones con botones Aceptar / Editar / Ignorar.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    weak var processor: Processor?

    /// Solo funcionan dentro de Bautiza.app (no con `swift run`).
    private var disponible: Bool { Bundle.main.bundleIdentifier != nil }

    func configurar() {
        guard disponible else { return }
        UNUserNotificationCenter.current().delegate = self
        configurarBotones()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Se repite al cambiar de idioma para traducir los botones.
    func configurarBotones() {
        guard disponible else { return }
        let categoria = UNNotificationCategory(
            identifier: "PROPUESTA",
            actions: [
                UNNotificationAction(identifier: "ACEPTAR", title: L("Aceptar", "Accept")),
                UNNotificationAction(identifier: "EDITAR", title: L("Editar…", "Edit…"), options: [.foreground]),
                UNNotificationAction(identifier: "IGNORAR", title: L("Ignorar", "Ignore"), options: [.destructive]),
            ],
            intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([categoria])
    }

    func proponer(_ p: Propuesta) {
        guard disponible else { return }
        let c = UNMutableNotificationContent()
        c.title = L("¿Renombrar?", "Rename?")
        c.subtitle = p.url.lastPathComponent
        c.body = p.nombre + (p.dudas.isEmpty ? "" : "\n⚠︎ " + p.dudas.joined(separator: " · "))
        c.categoryIdentifier = "PROPUESTA"
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: p.id.uuidString, content: c, trigger: nil))
    }

    func avisar(_ titulo: String, _ cuerpo: String) {
        guard disponible else { return }
        let c = UNMutableNotificationContent()
        c.title = titulo
        c.body = cuerpo
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    func retirar(_ id: UUID) {
        guard disponible else { return }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id.uuidString])
    }

    private func responder(_ id: String, _ accion: String) {
        guard let processor, let p = processor.pendientes.first(where: { $0.id.uuidString == id }) else {
            Ventanas.shared.mostrarPendientes()
            return
        }
        switch accion {
        case "ACEPTAR": processor.aplicar(p, nombre: p.nombre)
        case "IGNORAR": processor.ignorar(p)
        default: Ventanas.shared.mostrarPendientes()
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.identifier
        let accion = response.actionIdentifier
        Task { @MainActor in
            self.responder(id, accion)
            completionHandler()
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
